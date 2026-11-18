import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../data/local_database.dart';

/// 全局系统 TTS 语音播报服务
///
/// 所有播报统一走 [instance.speak]，便于集中处理：
/// - 跟随设置项 [settingKey]（默认开启），关闭时立即停止当前播报
/// - 相同文本在去重窗口内不重复播报，避免识别结果连续刷屏
/// - [interrupt] 为 true 时打断当前播报（告警类使用）
///
/// 依赖手机系统自带 TTS 引擎（中文），无需模型文件与网络。
class VoiceService {
  VoiceService._();

  static final VoiceService instance = VoiceService._();

  /// 设置项：语音播报开关
  static const String settingKey = 'voice_prompt';

  /// 设置项：朗读 AI 助手回复（默认开启）
  static const String aiReplySettingKey = 'ai_voice_reply';

  final FlutterTts _tts = FlutterTts();

  /// 文本 → 最近播报时间（用于去重）
  final Map<String, DateTime> _lastSpokenAt = {};

  bool _initialized = false;
  bool _enabled = true;
  bool _speaking = false;

  bool get enabled => _enabled;

  /// 是否朗读 AI 助手回复（首次默认开启）
  bool get aiReplyEnabled =>
      LocalDatabase().get(aiReplySettingKey) == null
          ? true
          : LocalDatabase().getBool(aiReplySettingKey);

  /// 应用启动时调用（幂等）；未配置语音数据时静默失败，不影响其他功能
  Future<void> init() async {
    final db = LocalDatabase();
    // 首次使用默认开启
    _enabled = db.get(settingKey) == null ? true : db.getBool(settingKey);
    if (_initialized) return;
    try {
      await _tts.setLanguage('zh-CN');
      await _tts.setSpeechRate(0.5); // 0~1，0.5 接近正常语速
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      _tts.setCompletionHandler(() => _speaking = false);
      _tts.setCancelHandler(() => _speaking = false);
      _tts.setErrorHandler((message) {
        _speaking = false;
        debugPrint('[Voice] 播报失败: $message');
      });
      _initialized = true;
    } catch (e) {
      debugPrint('[Voice] 初始化失败（可能是设备缺少中文TTS引擎）: $e');
    }
  }

  /// 开关语音播报（设置页调用），持久化到本地
  void setEnabled(bool value) {
    _enabled = value;
    LocalDatabase().setBool(settingKey, value);
    if (!value) {
      _tts.stop();
      _speaking = false;
    }
  }

  /// 播报一段文本
  ///
  /// - [interrupt]：打断当前播报，用于告警
  /// - [dedup]：相同文本的去重窗口
  Future<void> speak(
    String text, {
    bool interrupt = false,
    Duration dedup = const Duration(seconds: 6),
  }) async {
    if (!_enabled || text.isEmpty) return;

    final now = DateTime.now();
    final last = _lastSpokenAt[text];
    if (last != null && now.difference(last) < dedup) return;
    _lastSpokenAt[text] = now;
    if (_lastSpokenAt.length > 50) {
      _lastSpokenAt.removeWhere(
          (_, at) => now.difference(at) > const Duration(minutes: 10));
    }

    try {
      if (!_initialized) await init();
      if (!_initialized) return;
      if (interrupt || _speaking) await _tts.stop();
      _speaking = true;
      await _tts.speak(text);
    } catch (e) {
      _speaking = false;
      debugPrint('[Voice] 播报异常: $e');
    }
  }

  /// 朗读 AI 助手回复（受“语音播报”和“朗读AI回复”两个开关控制）
  Future<void> speakAiReply(String text) async {
    if (!_enabled || !aiReplyEnabled) return;
    await speak(condenseForSpeech(text),
        interrupt: true, dedup: const Duration(seconds: 2));
  }

  /// 压缩为适合播报的开头（最多 [maxChars] 字，尽量在句末断开），
  /// 超出部分提示查看屏幕，避免整段长回复长时间朗读
  static String condenseForSpeech(String text, {int maxChars = 80}) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return '';
    var cut = clean.length;
    if (cut > maxChars) {
      final idx =
          clean.substring(0, maxChars).lastIndexOf(RegExp(r'[。！？!?；;]'));
      cut = idx >= 20 ? idx + 1 : maxChars;
    }
    final head = clean.substring(0, cut);
    return cut < clean.length ? '$head……更多内容请查看屏幕' : head;
  }
}
