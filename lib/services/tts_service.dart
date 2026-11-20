import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// 播报优先级：数值越大越优先，可打断低优先级播报
enum TtsPriority { chat, status, alert }

class _SpeechItem {
  final String text;
  final TtsPriority priority;

  const _SpeechItem(this.text, this.priority);
}

/// 本地离线语音播报服务（基于系统 TTS 引擎，不依赖网络）
///
/// - 全局单例，App 启动时预热
/// - 内部优先级队列：告警 > 状态提示 > AI 朗读
/// - 高优先级播报打断当前低优先级播报
/// - 相同文本短时间重复触发自动去重
class TtsService {
  TtsService._();

  static final TtsService instance = TtsService._();

  static const Duration _duplicateWindow = Duration(seconds: 3);

  final FlutterTts _tts = FlutterTts();
  final List<_SpeechItem> _queue = [];

  Future<bool>? _initFuture;
  bool _available = false;
  bool _enabled = true;
  bool _draining = false;
  TtsPriority? _currentPriority;
  String? _lastText;
  DateTime _lastSpokenAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 系统是否安装了中文语音引擎
  bool get available => _available;
  bool get enabled => _enabled;

  /// 总开关：关闭时立即停止播报并清空队列
  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (!value) stop();
  }

  /// 预热语音引擎（不阻塞启动）
  Future<bool> init() => _ensureInit();

  Future<bool> _ensureInit() => _initFuture ??= _init();

  Future<bool> _init() async {
    try {
      await _tts.awaitSpeakCompletion(true);
      await _tts.setSpeechRate(0.5); // 系统语速 0~1，0.5 为适中
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);

      // 部分 ROM 只注册了 zh 而不是 zh-CN，两个都尝试
      for (final lang in const ['zh-CN', 'zh']) {
        final ok = await _tts.isLanguageAvailable(lang);
        if (ok == true) {
          await _tts.setLanguage(lang);
          _available = true;
          debugPrint('[TTS] 本地语音引擎就绪（$lang）');
          return true;
        }
      }

      _available = false;
      debugPrint('[TTS] 未找到中文语音引擎，语音播报不可用');
      return false;
    } catch (e) {
      _available = false;
      debugPrint('[TTS] 初始化失败: $e');
      return false;
    }
  }

  /// 播报文本。文本为空或总开关关闭时忽略。
  void speak(String text, {TtsPriority priority = TtsPriority.status}) {
    final content = text.trim();
    if (!_enabled || content.isEmpty) return;

    final now = DateTime.now();
    if (content == _lastText &&
        now.difference(_lastSpokenAt) < _duplicateWindow) {
      return;
    }

    // AI 朗读只保留最新一条，避免旧回复排队积压
    if (priority == TtsPriority.chat) {
      _queue.removeWhere((item) => item.priority == TtsPriority.chat);
      if (_draining && _currentPriority == TtsPriority.chat) {
        _tts.stop();
      }
    }

    // 高优先级播报打断当前低优先级播报
    if (_draining &&
        _currentPriority != null &&
        priority.index > _currentPriority!.index) {
      _queue.add(_SpeechItem(content, priority));
      _lastText = content;
      _lastSpokenAt = now;
      _tts.stop();
      return;
    }

    _queue.add(_SpeechItem(content, priority));
    _lastText = content;
    _lastSpokenAt = now;
    unawaited(_drain());
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
          debugPrint('[TTS] 播报失败: $e');
        }
        _currentPriority = null;
      }
    } finally {
      _draining = false;
      _currentPriority = null;
    }
  }

  /// 停止当前播报并清空待播队列
  Future<void> stop() async {
    _queue.clear();
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
