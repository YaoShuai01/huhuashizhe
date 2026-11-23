import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../../auth/data/auth_api.dart';

/// 语音输入状态
enum ForumVoiceStatus { idle, listening, processing, error }

/// 语音状态回调，[message] 为错误提示文案
typedef ForumVoiceStatusHandler =
    void Function(ForumVoiceStatus status, String? message);

/// 支持的语音方言，[accent] 对应讯飞识别接口的 accent 参数
enum ForumVoiceDialect {
  mandarin('普通话', 'mandarin'),
  cantonese('粤语', 'cantonese'),
  sichuanese('四川话', 'sichuanese'),
  henanese('河南话', 'henanese'),
  northeastern('东北话', 'northeastern'),
  hunanese('湖南话', 'hunanese');

  const ForumVoiceDialect(this.label, this.accent);

  final String label;
  final String accent;
}

/// 当前选中的方言，发帖与评论语音共用
final ValueNotifier<ForumVoiceDialect> forumVoiceDialectInput =
    ValueNotifier<ForumVoiceDialect>(ForumVoiceDialect.mandarin);

/// 语音识别接口：所有页面通过该接口使用语音输入，
/// 外部可替换为第三方识别服务或测试替身
abstract class ForumVoiceRecognizer {
  /// 开始识别，识别到的文字通过 [onText] 回调（含实时中间结果）
  Future<bool> start({
    required ValueChanged<String> onText,
    required ForumVoiceStatusHandler onStatus,
    ForumVoiceDialect dialect = ForumVoiceDialect.mandarin,
  });

  /// 结束识别
  Future<void> stop();
}

/// 基于系统语音识别服务的实现（普通话）
class PlatformForumVoiceRecognizer implements ForumVoiceRecognizer {
  static const MethodChannel _channel = MethodChannel(
    'com.huhuashizhe/voice_input',
  );

  ValueChanged<String>? _onText;
  ForumVoiceStatusHandler? _onStatus;
  bool _bound = false;

  void _bind() {
    if (_bound) return;
    _channel.setMethodCallHandler(_handleCall);
    _bound = true;
  }

  Future<dynamic> _handleCall(MethodCall call) async {
    if (call.method != 'onVoiceEvent') return null;
    final map = (call.arguments as Map?) ?? const {};
    final text = map['text'] as String?;
    switch (map['state']) {
      case 'listening':
        _onStatus?.call(ForumVoiceStatus.listening, null);
      case 'processing':
        _onStatus?.call(ForumVoiceStatus.processing, null);
      case 'partial':
        if (text != null) _onText?.call(text);
      case 'result':
        if (text != null) _onText?.call(text);
        _onStatus?.call(ForumVoiceStatus.idle, null);
      case 'error':
        _onStatus?.call(ForumVoiceStatus.error, text);
    }
    return null;
  }

  @override
  Future<bool> start({
    required ValueChanged<String> onText,
    required ForumVoiceStatusHandler onStatus,
    ForumVoiceDialect dialect = ForumVoiceDialect.mandarin,
  }) async {
    final permission = await Permission.microphone.request();
    if (!permission.isGranted) {
      onStatus(ForumVoiceStatus.error, '需要麦克风权限才能语音输入');
      return false;
    }

    _onText = onText;
    _onStatus = onStatus;
    _bind();
    try {
      return await _channel.invokeMethod<bool>('start') ?? false;
    } on PlatformException catch (e) {
      onStatus(ForumVoiceStatus.error, e.message ?? '语音输入启动失败');
      return false;
    } on MissingPluginException {
      onStatus(ForumVoiceStatus.error, '当前设备不支持语音输入');
      return false;
    }
  }

  @override
  Future<void> stop() async {
    _onText = null;
    _onStatus?.call(ForumVoiceStatus.idle, null);
    _onStatus = null;
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {
      // 通道不可用时忽略，页面状态已复位
    }
  }
}

/// 基于讯飞方言识别的实现：本地录音后上传服务器转为普通话文字
class CloudForumVoiceRecognizer implements ForumVoiceRecognizer {
  CloudForumVoiceRecognizer({Dio? dio, String? baseUrl})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: _normalizeBase(baseUrl ?? defaultForumApiBase),
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
            ),
          );

  static const int _sampleRate = 16000;
  static const int _maxSeconds = 60;

  final Dio _dio;
  final AudioRecorder _recorder = AudioRecorder();

  ValueChanged<String>? _onText;
  ForumVoiceStatusHandler? _onStatus;
  ForumVoiceDialect _dialect = ForumVoiceDialect.mandarin;
  String? _path;
  Timer? _timer;
  bool _recording = false;
  bool _stopping = false;

  static String _normalizeBase(String base) =>
      base.endsWith('/') ? base.substring(0, base.length - 1) : base;

  @override
  Future<bool> start({
    required ValueChanged<String> onText,
    required ForumVoiceStatusHandler onStatus,
    ForumVoiceDialect dialect = ForumVoiceDialect.mandarin,
  }) async {
    if (_recording) return true;

    final permission = await Permission.microphone.request();
    if (!permission.isGranted) {
      onStatus(ForumVoiceStatus.error, '需要麦克风权限才能语音输入');
      return false;
    }

    _onText = onText;
    _onStatus = onStatus;
    _dialect = dialect;
    _path =
        '${Directory.systemTemp.path}/forum_voice_'
        '${DateTime.now().microsecondsSinceEpoch}.pcm';
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: 1,
        ),
        path: _path!,
      );
    } catch (_) {
      onStatus(ForumVoiceStatus.error, '语音输入启动失败，请检查麦克风');
      return false;
    }

    _recording = true;
    _stopping = false;
    onStatus(ForumVoiceStatus.listening, null);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: _maxSeconds), () {
      stop();
    });
    return true;
  }

  @override
  Future<void> stop() async {
    if (!_recording || _stopping) return;
    _stopping = true;
    _timer?.cancel();
    _timer = null;

    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      path = _path;
    }
    _recording = false;
    path ??= _path;
    _path = null;
    if (path == null) {
      _onStatus?.call(ForumVoiceStatus.error, '录音失败，请重试');
      _reset();
      return;
    }

    _onStatus?.call(ForumVoiceStatus.processing, null);
    Uint8List bytes;
    try {
      bytes = await File(path).readAsBytes();
    } catch (_) {
      _onStatus?.call(ForumVoiceStatus.error, '录音读取失败，请重试');
      _cleanup(path);
      _reset();
      return;
    }
    if (bytes.length < _sampleRate) {
      _onStatus?.call(ForumVoiceStatus.error, '说话时间太短，请重试');
      _cleanup(path);
      _reset();
      return;
    }

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/asr',
        data: {'audio': base64Encode(bytes), 'dialect': _dialect.accent},
      );
      final text = (response.data?['text'] as String?)?.trim() ?? '';
      if (text.isEmpty) {
        _onStatus?.call(ForumVoiceStatus.error, '没有识别到内容，请重试');
      } else {
        _onText?.call(text);
        _onStatus?.call(ForumVoiceStatus.idle, null);
      }
    } on DioException catch (e) {
      final data = e.response?.data;
      final message = data is Map ? data['error']?.toString() : null;
      _onStatus?.call(ForumVoiceStatus.error, message ?? '方言识别失败，请检查网络后重试');
    } catch (_) {
      _onStatus?.call(ForumVoiceStatus.error, '方言识别失败，请重试');
    } finally {
      _cleanup(path);
      _reset();
    }
  }

  void _cleanup(String path) {
    try {
      File(path).deleteSync();
    } catch (_) {
      // 临时文件不存在时忽略
    }
  }

  void _reset() {
    _onText = null;
    _onStatus = null;
    _stopping = false;
  }
}

/// 普通话走系统识别（实时、离线），方言走云端识别
class HybridForumVoiceRecognizer implements ForumVoiceRecognizer {
  HybridForumVoiceRecognizer({
    ForumVoiceRecognizer? system,
    ForumVoiceRecognizer? cloud,
  }) : _system = system ?? PlatformForumVoiceRecognizer(),
       _cloud = cloud ?? CloudForumVoiceRecognizer();

  final ForumVoiceRecognizer _system;
  final ForumVoiceRecognizer _cloud;
  ForumVoiceRecognizer? _active;

  @override
  Future<bool> start({
    required ValueChanged<String> onText,
    required ForumVoiceStatusHandler onStatus,
    ForumVoiceDialect dialect = ForumVoiceDialect.mandarin,
  }) {
    final active = dialect == ForumVoiceDialect.mandarin ? _system : _cloud;
    _active = active;
    return active.start(onText: onText, onStatus: onStatus, dialect: dialect);
  }

  @override
  Future<void> stop() async {
    await _active?.stop();
  }
}

/// 默认语音识别实现，页面未注入时使用
final ForumVoiceRecognizer defaultForumVoiceRecognizer =
    HybridForumVoiceRecognizer();
