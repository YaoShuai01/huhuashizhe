import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// 语音输入状态
enum ForumVoiceStatus { idle, listening, processing, error }

/// 语音状态回调，[message] 为错误提示文案
typedef ForumVoiceStatusHandler = void Function(
  ForumVoiceStatus status,
  String? message,
);

/// 语音识别接口：所有页面通过该接口使用语音输入，
/// 外部可替换为第三方识别服务或测试替身
abstract class ForumVoiceRecognizer {
  /// 开始识别，识别到的文字通过 [onText] 回调（含实时中间结果）
  Future<bool> start({
    required ValueChanged<String> onText,
    required ForumVoiceStatusHandler onStatus,
  });

  /// 结束识别
  Future<void> stop();
}

/// 基于系统语音识别服务的实现（Android SpeechRecognizer）
class PlatformForumVoiceRecognizer implements ForumVoiceRecognizer {
  static const MethodChannel _channel =
      MethodChannel('com.huhuashizhe/voice_input');

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

/// 默认语音识别实现，页面未注入时使用
final ForumVoiceRecognizer defaultForumVoiceRecognizer =
    PlatformForumVoiceRecognizer();
