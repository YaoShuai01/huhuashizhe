import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
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

/// TFLite 分类推理服务（YOLO11s-cls, 39类作物问题, 输入224x224 float32 0~1）
class ModelInferenceService {
  static const String _modelAsset = 'assets/models/classify_39.tflite';
  static const int _inputSize = 224;

  Interpreter? _interpreter;
  List<List<List<List<double>>>>? _input;
  List<List<double>>? _output;
  int _numClasses = 0;
  bool _loaded = false;

  bool get isLoaded => _loaded;
  bool get hasBoxOutput => false; // 检测模型升级后返回true

  /// 加载模型（优先GPU/NNAPI加速，失败回退CPU多线程）
  Future<bool> load() async {
    if (_loaded) return true;
    Interpreter? interpreter;
    // 1) 尝试 GPU 加速
    try {
      final options = InterpreterOptions()..threads = 4;
      options.addDelegate(GpuDelegateV2());
      interpreter = await Interpreter.fromAsset(_modelAsset, options: options);
      debugPrint('[Inference] GPU加速已启用');
    } catch (_) {
      interpreter = null;
    }
    // 2) 尝试 NNAPI 加速
    if (interpreter == null) {
      try {
        final options = InterpreterOptions()
          ..threads = 4
          ..useNnApiForAndroid = true;
        interpreter = await Interpreter.fromAsset(_modelAsset, options: options);
        debugPrint('[Inference] NNAPI加速已启用');
      } catch (_) {
        interpreter = null;
      }
    }
    // 3) 兜底 CPU
    interpreter ??= await Interpreter.fromAsset(
      _modelAsset,
      options: InterpreterOptions()..threads = 4,
    );
    debugPrint('[Inference] 使用CPU多线程推理');
    _interpreter = interpreter;

    _numClasses = _interpreter!.getOutputTensor(0).shape.last;
    _output = [List<double>.filled(_numClasses, 0)];
    _input = List.generate(
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
    _loaded = true;
    return true;
  }

  /// 释放
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _loaded = false;
  }

  /// 对RGB字节(尺寸224x224, RGB888)执行推理，返回softmax概率结果
  InferenceResult infer(Uint8List rgb) {
    if (!_loaded) throw StateError('模型未加载');
    final input = _input!;
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
    final output = _output!;
    _interpreter!.run(input, output);
    return _postProcess(output[0]);
  }

  InferenceResult _postProcess(List<double> raw) {
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

  static int get inputSize => _inputSize;
}

/// YUV420 相机帧 → RGB888，最近邻缩放到目标尺寸（纯函数，可在isolate中执行）
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
