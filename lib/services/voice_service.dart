import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../data/local_database.dart';

/// 播报优先级：数值越大越优先，高优先级可打断低优先级
enum VoicePriority { chat, status, alert }

class _SpeechItem {
  final String text;
  final VoicePriority priority;

  const _SpeechItem(this.text, this.priority);
}

/// 全局系统 TTS 语音播报服务
///
/// 所有播报统一走 [instance.speak]，便于集中处理：
/// - 跟随设置项 [settingKey]（默认开启），关闭时立即停止当前播报
/// - 按去重键在窗口内不重复播报，避免识别结果连续刷屏
/// - 优先级 alert > status > chat：AI 朗读不会打断安全告警
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

  /// 去重键 → 最近播报时间
  final Map<String, DateTime> _lastSpokenAt = {};

  final List<_SpeechItem> _queue = [];

  Future<bool>? _initFuture;
  bool _available = false;
  bool _enabled = true;
  bool _draining = false;
  VoicePriority? _currentPriority;

  bool get enabled => _enabled;

  /// 系统是否安装了中文 TTS 引擎
  bool get available => _available;

  /// 是否朗读 AI 助手回复（首次默认开启）
  bool get aiReplyEnabled =>
      LocalDatabase().get(aiReplySettingKey) == null
          ? true
          : LocalDatabase().getBool(aiReplySettingKey);

  /// 应用启动时调用（幂等）；未配置语音数据时静默失败，不影响其他功能
  Future<void> init() async {
    _enabled = LocalDatabase().get(settingKey) == null
        ? true
        : LocalDatabase().getBool(settingKey);
    await _ensureInit();
  }

  Future<bool> _ensureInit() => _initFuture ??= _init();

  Future<bool> _init() async {
    try {
      await _tts.awaitSpeakCompletion(true);
      await _tts.setSpeechRate(0.5); // 0~1，0.5 接近正常语速
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);

      // 部分 ROM 只注册了 zh 而不是 zh-CN，两个都尝试
      for (final lang in const ['zh-CN', 'zh']) {
        final ok = await _tts.isLanguageAvailable(lang);
        if (ok == true) {
          await _tts.setLanguage(lang);
          _available = true;
          debugPrint('[Voice] 本地语音引擎就绪（$lang）');
          return true;
        }
      }

      _available = false;
      debugPrint('[Voice] 未找到中文TTS引擎，语音播报不可用');
      return false;
    } catch (e) {
      _available = false;
      debugPrint('[Voice] 初始化失败（可能是设备缺少中文TTS引擎）: $e');
      return false;
    }
  }

  /// 开关语音播报（设置页调用），持久化到本地
  void setEnabled(bool value) {
    _enabled = value;
    LocalDatabase().setBool(settingKey, value);
    if (!value) {
      unawaited(stop());
    }
  }

  /// 播报一段文本
  ///
  /// - [priority]：播报优先级，高优先级可打断低优先级
  /// - [dedup]：同一 [dedupKey] 的去重窗口
  /// - [dedupKey]：去重键，默认使用文本本身；识别结果建议传类别键，
  ///   避免置信度变化导致去重失效
  void speak(
    String text, {
    VoicePriority priority = VoicePriority.status,
    Duration dedup = const Duration(seconds: 6),
    String? dedupKey,
  }) {
    final content = text.trim();
    if (!_enabled || content.isEmpty) return;

    final key = dedupKey ?? content;
    final now = DateTime.now();
    final last = _lastSpokenAt[key];
    if (last != null && now.difference(last) < dedup) return;
    _lastSpokenAt[key] = now;
    if (_lastSpokenAt.length > 50) {
      _lastSpokenAt.removeWhere(
          (_, at) => now.difference(at) > const Duration(minutes: 10));
    }

    // 新播报到达时清理低优先级待播项；AI/告警只保留最新一条
    _queue.removeWhere((item) => item.priority.index < priority.index);
    if (priority != VoicePriority.status) {
      _queue.removeWhere((item) => item.priority == priority);
    }

    // 更高优先级立即打断；同类 AI/告警以最新一条为准；状态提示按顺序排队
    final preempt = _draining &&
        _currentPriority != null &&
        (priority.index > _currentPriority!.index ||
            (priority == _currentPriority && priority != VoicePriority.status));

    _queue.add(_SpeechItem(content, priority));

    if (preempt) {
      unawaited(_tts.stop());
    } else if (!_draining) {
      unawaited(_drain());
    }
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      final ok = await _ensureInit();
      if (!ok) {
        _queue.clear();
        return;
      }
      while (_enabled && _queue.isNotEmpty) {
        _queue.sort((a, b) => b.priority.index.compareTo(a.priority.index));
        final item = _queue.removeAt(0);
        _currentPriority = item.priority;
        try {
          await _tts.speak(item.text);
        } catch (e) {
          debugPrint('[Voice] 播报异常: $e');
        }
        _currentPriority = null;
      }
    } finally {
      _draining = false;
      _currentPriority = null;
    }
  }

  /// 朗读 AI 助手回复（受“语音播报”和“朗读AI回复”两个开关控制）
  ///
  /// 普通回复（200 字以内）完整朗读；超长内容截断并提示查看屏幕。
  Future<void> speakAiReply(String text) async {
    if (!_enabled || !aiReplyEnabled) return;
    final content = condenseForSpeech(text, maxChars: 300);
    if (content.isEmpty) return;
    speak(
      content,
      priority: VoicePriority.chat,
      dedup: const Duration(seconds: 2),
    );
  }

  /// 朗读屏幕文字（老年关怀模式）
  ///
  /// 不受“语音播报”设置开关影响，点击文字即读；重复点击会打断上一段
  void speakReading(String text) {
    final content = text.trim();
    if (content.isEmpty) return;
    unawaited(_speakReading(content));
  }

  Future<void> _speakReading(String content) async {
    final ok = await _ensureInit();
    if (!ok) return;
    try {
      await _tts.stop();
      await _tts.speak(content);
    } catch (e) {
      debugPrint('[Voice] 朗读文字失败: $e');
    }
  }

  /// 停止当前播报并清空待播队列
  Future<void> stop() async {
    _queue.clear();
    try {
      await _tts.stop();
    } catch (_) {}
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
