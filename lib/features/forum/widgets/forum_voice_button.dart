import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../services/forum_voice_input.dart';

/// 语音输入按钮：点击开始识别，再次点击结束；
/// 识别结果直接写入 [controller]，新建或追加到已有文字之后
class ForumVoiceButton extends StatefulWidget {
  const ForumVoiceButton({
    super.key,
    required this.controller,
    this.recognizer,
    this.iconSize = 28,
  });

  final TextEditingController controller;

  /// 外部注入的识别实现，为空时使用默认系统识别
  final ForumVoiceRecognizer? recognizer;

  final double iconSize;

  @override
  State<ForumVoiceButton> createState() => _ForumVoiceButtonState();
}

class _ForumVoiceButtonState extends State<ForumVoiceButton> {
  bool _listening = false;
  bool _starting = false;

  /// 开始识别时输入框已有内容，作为结果前缀保留
  String _prefix = '';

  ForumVoiceRecognizer get _recognizer =>
      widget.recognizer ?? defaultForumVoiceRecognizer;

  Future<void> _toggle() async {
    if (_starting) return;
    if (_listening) {
      setState(() => _listening = false);
      await _recognizer.stop();
      return;
    }

    setState(() => _starting = true);
    final existing = widget.controller.text;
    _prefix = existing.isEmpty || existing.endsWith(' ') ||
            existing.endsWith('\n')
        ? existing
        : '$existing ';

    final started = await _recognizer.start(
      onText: _applyText,
      onStatus: _applyStatus,
    );
    if (!mounted) return;
    if (!started) {
      setState(() {
        _starting = false;
        _listening = false;
      });
    }
  }

  void _applyText(String text) {
    if (!mounted) return;
    final value = '$_prefix$text';
    widget.controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _applyStatus(ForumVoiceStatus status, String? message) {
    if (!mounted) return;
    switch (status) {
      case ForumVoiceStatus.listening:
        setState(() {
          _listening = true;
          _starting = false;
        });
      case ForumVoiceStatus.processing:
        break;
      case ForumVoiceStatus.idle:
        setState(() {
          _listening = false;
          _starting = false;
        });
      case ForumVoiceStatus.error:
        setState(() {
          _listening = false;
          _starting = false;
        });
        if (message != null) _showTip(message);
    }
  }

  void _showTip(String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 1800),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final color = _listening ? AppColors.error : AppColors.primary;
    return IconButton(
      tooltip: _listening ? '结束语音输入' : '语音输入',
      onPressed: _starting ? null : _toggle,
      iconSize: widget.iconSize,
      icon: Icon(_listening ? Icons.mic : Icons.mic_none, color: color),
    );
  }
}
