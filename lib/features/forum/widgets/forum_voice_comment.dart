import 'dart:async';
import 'dart:io' show Directory, File;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/data/auth_session.dart';
import '../data/forum_models.dart';
import '../data/forum_repository.dart';
import '../services/forum_voice_input.dart';

/// 一段录制完成的语音
class ForumVoiceRecording {
  const ForumVoiceRecording({required this.bytes, required this.durationMs});

  final Uint8List bytes;
  final int durationMs;
}

/// 语音评论录制器：输出 16k/16bit/单声道 WAV
class ForumVoiceCommentRecorder {
  static const int maxSeconds = 60;

  final AudioRecorder _recorder = AudioRecorder();
  Stopwatch? _watch;
  String? _path;

  Future<bool> start() async {
    final permission = await Permission.microphone.request();
    if (!permission.isGranted) return false;
    _path =
        '${Directory.systemTemp.path}/forum_voice_comment_'
        '${DateTime.now().microsecondsSinceEpoch}.wav';
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: _path!,
      );
    } catch (_) {
      return false;
    }
    _watch = Stopwatch()..start();
    return true;
  }

  Future<ForumVoiceRecording?> stop() async {
    final watch = _watch;
    if (watch == null) return null;
    watch.stop();
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      path = _path;
    }
    path ??= _path;
    _watch = null;
    _path = null;
    if (path == null) return null;
    try {
      final bytes = await File(path).readAsBytes();
      final durationMs = watch.elapsedMilliseconds;
      unawaited(_delete(path));
      if (bytes.length < 3200 || durationMs < 500) return null;
      return ForumVoiceRecording(bytes: bytes, durationMs: durationMs);
    } catch (_) {
      return null;
    }
  }

  Future<void> cancel() async {
    _watch?.stop();
    _watch = null;
    final path = _path;
    _path = null;
    try {
      await _recorder.cancel();
    } catch (_) {
      // 未开始录制时忽略
    }
    if (path != null) unawaited(_delete(path));
  }

  Future<void> _delete(String path) async {
    try {
      await File(path).delete();
    } catch (_) {
      // 临时文件已删除时忽略
    }
  }
}

/// 打开语音评论录制面板，返回录制结果
Future<ForumVoiceRecording?> showForumVoiceRecorder(BuildContext context) {
  return showModalBottomSheet<ForumVoiceRecording>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (context) => const _VoiceRecorderSheet(),
  );
}

class _VoiceRecorderSheet extends StatefulWidget {
  const _VoiceRecorderSheet();

  @override
  State<_VoiceRecorderSheet> createState() => _VoiceRecorderSheetState();
}

class _VoiceRecorderSheetState extends State<_VoiceRecorderSheet> {
  final ForumVoiceCommentRecorder _recorder = ForumVoiceCommentRecorder();
  Timer? _ticker;
  int _seconds = 0;
  bool _ready = false;
  bool _failed = false;
  bool _stopping = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final ok = await _recorder.start();
    if (!mounted) return;
    if (!ok) {
      setState(() => _failed = true);
      return;
    }
    setState(() => _ready = true);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds += 1);
      if (_seconds >= ForumVoiceCommentRecorder.maxSeconds) _stop();
    });
  }

  Future<void> _stop() async {
    if (_stopping) return;
    _stopping = true;
    _ticker?.cancel();
    final result = await _recorder.stop();
    if (!mounted) return;
    if (result == null) {
      setState(() {
        _stopping = false;
        _failed = true;
      });
      return;
    }
    Navigator.of(context).pop(result);
  }

  Future<void> _cancel() async {
    _ticker?.cancel();
    await _recorder.cancel();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = '${_seconds ~/ 60}:${(_seconds % 60).toString().padLeft(2, '0')}';
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _failed ? '录音失败，请检查麦克风权限' : '正在录音，说完点击停止',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              duration,
              style: const TextStyle(fontSize: 26, color: AppColors.primary),
            ),
            const SizedBox(height: 4),
            Text(
              '最长 60 秒，发送后自动转成文字显示在语音下方',
              style: const TextStyle(fontSize: 12, color: AppColors.textHint),
            ),
            const SizedBox(height: 20),
            if (_failed)
              FilledButton(
                onPressed: _cancel,
                child: const Text('关闭'),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _stopping ? null : _cancel,
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: (_ready && !_stopping) ? _stop : null,
                      icon: const Icon(Icons.stop_circle_outlined, size: 20),
                      label: const Text('停止并发送'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// 录制并发送一条语音评论，返回发送成功的评论
Future<ForumComment?> sendForumVoiceComment({
  required BuildContext context,
  required ForumRepository repository,
  required ForumPost post,
  ForumComment? replyTo,
}) async {
  if (!AuthSession.instance.isLoggedIn) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('登录后才能发表评论')));
    return null;
  }
  final recording = await showForumVoiceRecorder(context);
  if (recording == null || !context.mounted) return null;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _SendingDialog(),
  );

  ForumComment? comment;
  String? error;
  try {
    final audioUrl = await repository.uploadAudio(
      bytes: recording.bytes,
      durationMs: recording.durationMs,
    );
    var transcript = '';
    try {
      transcript = await repository.transcribeAudio(
        bytes: recording.bytes,
        dialect: forumVoiceDialectInput.value.accent,
      );
    } on ForumException {
      // 转写失败不影响发送，语音仍可播放
    }
    comment = await repository.addComment(
      post: post,
      content: transcript,
      replyTo: replyTo,
      audioUrl: audioUrl,
      audioDurationMs: recording.durationMs,
    );
  } on ForumException catch (e) {
    error = e.message;
  } catch (_) {
    error = '语音发送失败，请检查网络后重试';
  }

  if (!context.mounted) return comment;
  Navigator.of(context).pop();
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(error ?? '语音评论已发送')),
    );
  return error == null ? comment : null;
}

class _SendingDialog extends StatelessWidget {
  const _SendingDialog();

  @override
  Widget build(BuildContext context) {
    return const Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('正在发送语音…'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 评论栏里的「发语音」按钮
class ForumVoiceCommentButton extends StatelessWidget {
  const ForumVoiceCommentButton({
    super.key,
    required this.repository,
    required this.post,
    this.replyTo,
    this.onSent,
  });

  final ForumRepository repository;
  final ForumPost post;
  final ForumComment? replyTo;
  final VoidCallback? onSent;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '发语音评论',
      onPressed: () async {
        final comment = await sendForumVoiceComment(
          context: context,
          repository: repository,
          post: post,
          replyTo: replyTo,
        );
        if (comment != null) onSent?.call();
      },
      icon: const Icon(
        Icons.graphic_eq,
        size: 24,
        color: AppColors.textHint,
      ),
    );
  }
}
