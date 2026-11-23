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
    this.onListeningChanged,
    this.onText,
  });

  final TextEditingController controller;

  /// 外部注入的识别实现，为空时使用默认系统识别
  final ForumVoiceRecognizer? recognizer;

  final double iconSize;

  /// 开始 / 结束识别时回调，便于页面展示「正在聆听」状态
  final ValueChanged<bool>? onListeningChanged;

  /// 识别文本写入输入框后回调，参数为完整文本
  final ValueChanged<String>? onText;

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
      _setListening(false);
      await _recognizer.stop();
      return;
    }

    setState(() => _starting = true);
    final existing = widget.controller.text;
    _prefix =
        existing.isEmpty || existing.endsWith(' ') || existing.endsWith('\n')
            ? existing
            : '$existing ';

    final started = await _recognizer.start(
      onText: _applyText,
      onStatus: _applyStatus,
      dialect: forumVoiceDialectInput.value,
    );
    if (!mounted) return;
    if (!started) {
      setState(() {
        _starting = false;
      });
      _setListening(false);
    }
  }

  void _setListening(bool value) {
    if (!mounted) return;
    if (_listening != value) {
      setState(() => _listening = value);
    }
    widget.onListeningChanged?.call(value);
  }

  void _applyText(String text) {
    if (!mounted) return;
    final value = '$_prefix$text';
    widget.controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    widget.onText?.call(value);
  }

  void _applyStatus(ForumVoiceStatus status, String? message) {
    if (!mounted) return;
    switch (status) {
      case ForumVoiceStatus.listening:
        setState(() => _starting = false);
        _setListening(true);
      case ForumVoiceStatus.processing:
        break;
      case ForumVoiceStatus.idle:
        setState(() => _starting = false);
        _setListening(false);
      case ForumVoiceStatus.error:
        setState(() => _starting = false);
        _setListening(false);
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

/// 语音方言选择：普通话走系统识别，其他方言走云端方言识别
class ForumVoiceDialectSelector extends StatelessWidget {
  const ForumVoiceDialectSelector({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ForumVoiceDialect>(
      valueListenable: forumVoiceDialectInput,
      builder:
          (context, dialect, _) => PopupMenuButton<ForumVoiceDialect>(
            tooltip: '选择语音方言',
            initialValue: dialect,
            onSelected: (value) => forumVoiceDialectInput.value = value,
            itemBuilder:
                (context) => [
                  for (final item in ForumVoiceDialect.values)
                    PopupMenuItem(
                      value: item,
                      child: Row(
                        children: [
                          Text(item.label),
                          if (item == forumVoiceDialectInput.value) ...[
                            const Spacer(),
                            const Icon(
                              Icons.check,
                              size: 18,
                              color: AppColors.primary,
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    dialect.label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textHint,
                    ),
                  ),
                  const Icon(
                    Icons.arrow_drop_down,
                    size: 16,
                    color: AppColors.textHint,
                  ),
                ],
              ),
            ),
          ),
    );
  }
}
