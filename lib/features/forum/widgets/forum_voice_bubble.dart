import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// 语音评论气泡：点击播放，下方展示自动转写文字
class ForumVoiceBubble extends StatefulWidget {
  const ForumVoiceBubble({
    super.key,
    required this.url,
    this.durationMs = 0,
    this.transcript = '',
  });

  final String url;
  final int durationMs;
  final String transcript;

  @override
  State<ForumVoiceBubble> createState() => _ForumVoiceBubbleState();
}

class _ForumVoiceBubbleState extends State<ForumVoiceBubble> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<void>? _completeSub;
  bool _playing = false;

  String get _durationText {
    final seconds = (widget.durationMs / 1000).round();
    if (seconds <= 0) return '语音';
    return '$seconds″';
  }

  @override
  void initState() {
    super.initState();
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      if (mounted) setState(() => _playing = false);
      return;
    }
    if (widget.url.isEmpty) return;
    try {
      await _player.stop();
      await _player.play(UrlSource(widget.url));
      if (mounted) setState(() => _playing = true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _playing = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('语音播放失败，请稍后重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _toggle,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _playing
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_fill,
                  size: 22,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  _durationText,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.transcript.trim().isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            widget.transcript,
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}
