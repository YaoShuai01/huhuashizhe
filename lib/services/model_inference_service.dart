import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// 分类模型推理结果
///
/// 当前使用整帧分类模型（输出类别+置信度）。
/// 预留 boxes 字段：后续升级检测模型后，此处将携带
/// 真实标注框坐标（归一化0~1），UI层直接绘制框选标注。
class InferenceResult {
  final int topIndex;
  final double topConfidence;
  final List<double> probabilities;
  final List<DetectionBox> boxes;

  const InferenceResult({
    required this.topIndex,
    required this.topConfidence,
    required this.probabilities,
    this.boxes = const [],
  });
}

/// 检测框（归一化坐标0~1，预留检测模型升级用）
class DetectionBox {
  final int classIndex;
  final double confidence;
  final double xMin, yMin, xMax, yMax;

  const DetectionBox({
    required this.classIndex,
    required this.confidence,
    required this.xMin,
    required this.yMin,
    required this.xMax,
    required this.yMax,
  });
}

/// YUV→RGB帧转换+TFLite推理常驻后台isolate引擎
///
/// v2.4.1性能优化：此前每帧在主线程执行推理（CPU 100~300ms），导致
/// 摄像头开启后出现周期性卡顿。现改为单常驻isolate：
///   主线程只拷贝相机帧字节 → 后台isolate完成YUV转换与推理 → 回调返回结果。
/// 主线程在整帧处理期间完全不阻塞，消除周期性卡顿。
class ModelInferenceService {
  static const String _modelAsset = 'assets/models/classify_39.tflite';
  static const int _inputSize = 224;

  Isolate? _isolate;
  SendPort? _toIsolate;
  ReceivePort? _fromIsolate;
  ReceivePort? _errorPort;
  Completer<bool>? _initCompleter;
  final Map<int, void Function(InferenceResult)> _pending = {};
  int _reqId = 0;
  bool _loaded = false;
  bool _loading = false;

  bool get isLoaded => _loaded;
  bool get isBusy => _pending.isNotEmpty; // 上一帧未算完时跳过新帧
  bool get hasBoxOutput => false; // 检测模型升级后返回true

  static int get inputSize => _inputSize;

  /// 加载模型并启动常驻推理isolate
  Future<bool> load() async {
    if (_loaded) return true;
    if (_loading) return false;
    _loading = true;
    try {
      // 主isolate读取asset字节（rootBundle仅主isolate可用），buffer跨isolate传递
      final data = await rootBundle.load(_modelAsset);
      final bytes = Uint8List.view(data.buffer, data.offsetInBytes, data.lengthInBytes);

      _fromIsolate = ReceivePort();
      _errorPort = ReceivePort();
      _fromIsolate!.listen(_onMessage);
      _errorPort!.listen((msg) {
        debugPrint('[Inference] isolate错误: $msg');
      });
      _initCompleter = Completer<bool>();
      _isolate = await Isolate.spawn(
        _isolateMain,
        _IsolateInit(bytes, _fromIsolate!.sendPort),
        onError: _errorPort!.sendPort,
        errorsAreFatal: false,
      );
      _loaded = await _initCompleter!.future
          .timeout(const Duration(seconds: 30), onTimeout: () => false);
      debugPrint('[Inference] 后台推理isolate就绪: $_loaded');
      return _loaded;
    } catch (e) {
      debugPrint('[Inference] 加载失败: $e');
      _loaded = false;
      return false;
    } finally {
      _loading = false;
    }
  }

  void _onMessage(dynamic msg) {
    if (msg is _Ready) {
      _toIsolate = msg.port;
      _initCompleter?.complete(true);
    } else if (msg is _InitFailed) {
      if (!(_initCompleter?.isCompleted ?? true)) {
        _initCompleter?.complete(false);
      }
    } else if (msg is _Reply) {
      final cb = _pending.remove(msg.id);
      if (cb != null) cb(msg.result);
    } else if (msg is _Error) {
      // 推理失败：丢弃该帧回调即可，保持_pending清空让后续帧继续
      _pending.remove(msg.id);
    }
  }

  /// 提交一帧（YUV快照），在后台isolate完成转换+推理，结果回调返回。
  /// 上一帧未完成时直接跳过本帧（防积压）。
  void inferAsync(FrameSnapshot snapshot, void Function(InferenceResult) onDone) {
    if (!_loaded || _toIsolate == null) return;
    if (_pending.isNotEmpty) return;
    final id = _reqId++;
    _pending[id] = onDone;
    _toIsolate!.send(_Request(id, snapshot));
  }

  void dispose() {
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _isolate = null;
    _fromIsolate?.close();
    _errorPort?.close();
    _fromIsolate = null;
    _errorPort = null;
    _toIsolate = null;
    _pending.clear();
    _loaded = false;
  }

  // ---------------- 后台isolate侧 ----------------

  static Future<void> _isolateMain(_IsolateInit init) async {
    try {
      // 后台isolate内启用GPU/NNAPI，失败回退CPU
      Interpreter? interpreter;
      try {
        final options = InterpreterOptions()..threads = 4;
        options.addDelegate(GpuDelegateV2());
        interpreter = Interpreter.fromBuffer(init.modelBytes, options: options);
        debugPrint('[Inference] isolate内GPU加速已启用');
      } catch (_) {
        interpreter = null;
      }
      if (interpreter == null) {
        try {
          final options = InterpreterOptions()
            ..threads = 4
            ..useNnApiForAndroid = true;
          interpreter = Interpreter.fromBuffer(init.modelBytes, options: options);
          debugPrint('[Inference] isolate内NNAPI加速已启用');
        } catch (_) {
          interpreter = null;
        }
      }
      interpreter ??= Interpreter.fromBuffer(
        init.modelBytes,
        options: InterpreterOptions()..threads = 4,
      );
      debugPrint('[Inference] isolate内CPU多线程推理');

      final numClasses = interpreter.getOutputTensor(0).shape.last;
      final output = [List<double>.filled(numClasses, 0)];
      // 输入张量必须匹配模型输入形状[1,224,224,3]：4层嵌套（含batch维）
      final input = List.generate(
        1,
        (_) => List.generate(
          _inputSize,
          (_) => List.generate(
            _inputSize,
            (_) => List.filled(3, 0.0, growable: false),
            growable: false,
          ),
          growable: false,
        ),
        growable: false,
      );

      final port = ReceivePort();
      init.replyPort.send(_Ready(port.sendPort));
      port.listen((msg) {
        if (msg is! _Request) return;
        try {
          final rgb = msg.snapshot.toRgbResized(_inputSize);
          final n = _inputSize * _inputSize;
          for (var i = 0; i < n; i++) {
            final row = i ~/ _inputSize;
            final col = i % _inputSize;
            final px = input[0][row][col];
            final o = i * 3;
            px[0] = rgb[o] / 255.0;
            px[1] = rgb[o + 1] / 255.0;
            px[2] = rgb[o + 2] / 255.0;
          }
          interpreter!.run(input, output);
          final result = _postProcess(output[0]);
          init.replyPort.send(_Reply(msg.id, result));
        } catch (e) {
          debugPrint('[Inference] 推理异常: $e');
          // 关键：异常也必须回复，否则主线程_pending永久占用，后续帧全部被跳过
          init.replyPort.send(_Error(msg.id, e.toString()));
        }
      });
    } catch (e) {
      init.replyPort.send(_InitFailed(e.toString()));
    }
  }

  static InferenceResult _postProcess(List<double> raw) {
    var sum = 0.0;
    for (final v in raw) {
      sum += v;
    }
    List<double> probs;
    if (sum > 0 && (sum - 1).abs() <= 0.05) {
      probs = List<double>.from(raw); // 已softmax
    } else {
      double maxV = double.negativeInfinity;
      for (final v in raw) {
        if (v > maxV) maxV = v;
      }
      var expSum = 0.0;
      probs = List<double>.filled(raw.length, 0);
      for (var i = 0; i < raw.length; i++) {
        probs[i] = math.exp(raw[i] - maxV);
        expSum += probs[i];
      }
      for (var i = 0; i < probs.length; i++) {
        probs[i] /= expSum;
      }
    }
    var topIdx = 0;
    for (var i = 1; i < probs.length; i++) {
      if (probs[i] > probs[topIdx]) topIdx = i;
    }
    return InferenceResult(
      topIndex: topIdx,
      topConfidence: probs[topIdx],
      probabilities: probs,
    );
  }
}

// ---------------- isolate消息载体（纯数据） ----------------

class _IsolateInit {
  final Uint8List modelBytes;
  final SendPort replyPort;
  const _IsolateInit(this.modelBytes, this.replyPort);
}

class _Ready {
  final SendPort port;
  const _Ready(this.port);
}

class _InitFailed {
  final String error;
  const _InitFailed(this.error);
}

class _Request {
  final int id;
  final FrameSnapshot snapshot;
  const _Request(this.id, this.snapshot);
}

class _Reply {
  final int id;
  final InferenceResult result;
  const _Reply(this.id, this.result);
}

class _Error {
  final int id;
  final String message;
  const _Error(this.id, this.message);
}

/// YUV420 相机帧 → RGB888，最近邻缩放到目标尺寸（纯函数）
Uint8List convertYuvToRgbResized({
  required Uint8List yPlane,
  required Uint8List uPlane,
  required Uint8List vPlane,
  required int width,
  required int height,
  required int yRowBytes,
  required int uvRowBytes,
  required int uvPixelStride,
  required int outSize,
}) {
  final out = Uint8List(outSize * outSize * 3);
  final ratioX = width / outSize;
  final ratioY = height / outSize;
  for (var oy = 0; oy < outSize; oy++) {
    var iy = (oy * ratioY).toInt();
    if (iy >= height) iy = height - 1;
    for (var ox = 0; ox < outSize; ox++) {
      var ix = (ox * ratioX).toInt();
      if (ix >= width) ix = width - 1;

      final yVal = yPlane[iy * yRowBytes + ix].toDouble();
      final uvRow = iy >> 1;
      final uvCol = ix >> 1;
      final uVal = uPlane[uvRow * uvRowBytes + uvCol * uvPixelStride];
      final vVal = vPlane[uvRow * uvRowBytes + uvCol * uvPixelStride];

      // BT.601 YUV→RGB
      var r = (yVal + 1.402 * (vVal - 128)).round();
      var g = (yVal - 0.344136 * (uVal - 128) - 0.714136 * (vVal - 128)).round();
      var b = (yVal + 1.772 * (uVal - 128)).round();

      final o = (oy * outSize + ox) * 3;
      out[o] = r < 0 ? 0 : (r > 255 ? 255 : r);
      out[o + 1] = g < 0 ? 0 : (g > 255 ? 255 : g);
      out[o + 2] = b < 0 ? 0 : (b > 255 ? 255 : b);
    }
  }
  return out;
}

/// 相机帧数据快照（纯字节数据，可跨 isolate 传递）
class FrameSnapshot {
  final Uint8List yPlane;
  final Uint8List uPlane;
  final Uint8List vPlane;
  final int width;
  final int height;
  final int yRowBytes;
  final int uvRowBytes;
  final int uvPixelStride;

  const FrameSnapshot({
    required this.yPlane,
    required this.uPlane,
    required this.vPlane,
    required this.width,
    required this.height,
    required this.yRowBytes,
    required this.uvRowBytes,
    required this.uvPixelStride,
  });

  factory FrameSnapshot.fromCameraImage(CameraImage image) {
    return FrameSnapshot(
      yPlane: Uint8List.fromList(image.planes[0].bytes),
      uPlane: Uint8List.fromList(image.planes[1].bytes),
      vPlane: Uint8List.fromList(image.planes[2].bytes),
      width: image.width,
      height: image.height,
      yRowBytes: image.planes[0].bytesPerRow,
      uvRowBytes: image.planes[1].bytesPerRow,
      uvPixelStride: image.planes[1].bytesPerPixel ?? 2,
    );
  }

  /// 转换+缩放到推理输入尺寸
  Uint8List toRgbResized(int outSize) => convertYuvToRgbResized(
        yPlane: yPlane,
        uPlane: uPlane,
        vPlane: vPlane,
        width: width,
        height: height,
        yRowBytes: yRowBytes,
        uvRowBytes: uvRowBytes,
        uvPixelStride: uvPixelStride,
        outSize: outSize,
      );
}
