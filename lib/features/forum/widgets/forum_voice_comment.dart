import 'dart:async';
import 'dart:io' show Directory, File;
import 'dart:math' as math;
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
    final duration =
        '${_seconds ~/ 60}:${(_seconds % 60).toString().padLeft(2, '0')}';
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
              FilledButton(onPressed: _cancel, child: const Text('关闭'))
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
  return sendVoiceRecordingComment(
    context: context,
    repository: repository,
    post: post,
    recording: recording,
    replyTo: replyTo,
  );
}

/// 上传并发送一段已录制好的语音评论
Future<ForumComment?> sendVoiceRecordingComment({
  required BuildContext context,
  required ForumRepository repository,
  required ForumPost post,
  required ForumVoiceRecording recording,
  ForumComment? replyTo,
}) async {
  if (!AuthSession.instance.isLoggedIn) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('登录后才能发表评论')));
    return null;
  }

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
    ..showSnackBar(SnackBar(content: Text(error ?? '语音评论已发送')));
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
      icon: const Icon(Icons.graphic_eq, size: 24, color: AppColors.textHint),
    );
  }
}

/// 按住说话按钮：按住录音，左上滑发语音评论，右上滑转为文字
class ForumVoiceHoldButton extends StatefulWidget {
  const ForumVoiceHoldButton({
    super.key,
    required this.repository,
    required this.post,
    required this.controller,
    this.replyTo,
    this.onSent,
  });

  final ForumRepository repository;
  final ForumPost post;

  /// 转文字结果写入该输入框
  final TextEditingController controller;
  final ForumComment? replyTo;
  final VoidCallback? onSent;

  @override
  State<ForumVoiceHoldButton> createState() => _ForumVoiceHoldButtonState();
}

enum _HoldMode { send, cancel, text }

class _HoldInfo {
  const _HoldInfo({this.mode = _HoldMode.send, this.busyLabel});

  final _HoldMode mode;
  final String? busyLabel;
}

class _ForumVoiceHoldButtonState extends State<ForumVoiceHoldButton> {
  final ForumVoiceCommentRecorder _recorder = ForumVoiceCommentRecorder();
  final ValueNotifier<_HoldInfo> _info = ValueNotifier(const _HoldInfo());
  OverlayEntry? _overlay;
  Timer? _ticker;
  bool _pressed = false;
  bool _recording = false;
  bool _busy = false;
  double _dragDx = 0;
  int _elapsed = 0;
  _HoldMode _mode = _HoldMode.send;

  @override
  void dispose() {
    _ticker?.cancel();
    _removeOverlay();
    _info.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _start() async {
    if (_recording || _busy) return;
    _dragDx = 0;
    _mode = _HoldMode.send;
    bool ok;
    try {
      ok = await _recorder.start();
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (!ok) {
      _toast('无法录音，请允许使用麦克风后再试');
      return;
    }
    // 权限弹窗期间已松手，直接放弃本次录音
    if (!_pressed) {
      await _recorder.cancel();
      return;
    }
    _recording = true;
    _elapsed = 0;
    _info.value = const _HoldInfo();
    _showOverlay();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_recording) return;
      _elapsed += 1;
      if (_elapsed >= ForumVoiceCommentRecorder.maxSeconds) _finish();
    });
  }

  void _move(PointerMoveEvent event) {
    if (!_recording) return;
    _dragDx += event.delta.dx;
    final next =
        _dragDx <= -56
            ? _HoldMode.cancel
            : _dragDx >= 56
            ? _HoldMode.text
            : _HoldMode.send;
    if (next != _mode) {
      _mode = next;
      _info.value = _HoldInfo(mode: _mode);
    }
  }

  Future<void> _finish() async {
    if (!_recording) return;
    _recording = false;
    _ticker?.cancel();
    _ticker = null;
    final mode = _mode;
    if (mode == _HoldMode.cancel) {
      _removeOverlay();
      await _recorder.cancel();
      if (mounted) _toast('已取消');
      return;
    }
    ForumVoiceRecording? recording;
    try {
      recording = await _recorder.stop();
    } catch (_) {
      recording = null;
    }
    if (!mounted) return;
    if (recording == null) {
      _removeOverlay();
      _toast('说话时间太短，按住说完再松开');
      return;
    }
    if (mode == _HoldMode.text) {
      await _toText(recording);
      return;
    }
    _removeOverlay();
    final comment = await sendVoiceRecordingComment(
      context: context,
      repository: widget.repository,
      post: widget.post,
      recording: recording,
      replyTo: widget.replyTo,
    );
    if (comment != null && mounted) widget.onSent?.call();
  }

  Future<void> _cancel() async {
    if (!_recording) return;
    _recording = false;
    _ticker?.cancel();
    _ticker = null;
    _removeOverlay();
    await _recorder.cancel();
  }

  Future<void> _toText(ForumVoiceRecording recording) async {
    _busy = true;
    _info.value = const _HoldInfo(busyLabel: '正在转文字…');
    try {
      final text = await widget.repository.transcribeAudio(
        bytes: recording.bytes,
        dialect: forumVoiceDialectInput.value.accent,
      );
      if (!mounted) return;
      final current = widget.controller.text;
      final merged = current.isEmpty ? text : '$current$text';
      widget.controller.value = TextEditingValue(
        text: merged,
        selection: TextSelection.collapsed(offset: merged.length),
      );
      _toast('已转为文字，可编辑后发送');
    } on ForumException catch (error) {
      _toast(error.message);
    } catch (_) {
      _toast('转文字失败，请检查网络后重试');
    } finally {
      _busy = false;
      if (mounted) _removeOverlay();
    }
  }

  void _showOverlay() {
    _removeOverlay();
    _overlay = OverlayEntry(builder: (context) => _HoldOverlay(info: _info));
    Overlay.of(context, rootOverlay: true).insert(_overlay!);
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '按住说话：左滑取消，右滑转文字，松开发送',
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) {
          _pressed = true;
          _start();
        },
        onPointerMove: _move,
        onPointerUp: (_) {
          _pressed = false;
          _finish();
        },
        onPointerCancel: (_) {
          _pressed = false;
          _cancel();
        },
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          child: Icon(
            Icons.mic,
            size: 24,
            color: _recording ? AppColors.error : AppColors.primary,
          ),
        ),
      ),
    );
  }
}

class _HoldOverlay extends StatefulWidget {
  const _HoldOverlay({required this.info});

  final ValueNotifier<_HoldInfo> info;

  @override
  State<_HoldOverlay> createState() => _HoldOverlayState();
}

class _HoldOverlayState extends State<_HoldOverlay>
    with SingleTickerProviderStateMixin {
  static const Color _bubbleColor = Color(0xFF8CE05A);

  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_HoldInfo>(
      valueListenable: widget.info,
      builder: (context, value, _) {
        final busyLabel = value.busyLabel;
        return SizedBox.expand(
          child: IgnorePointer(
            child: Container(
              color: Colors.black.withValues(alpha: 0.55),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child:
                        busyLabel != null
                            ? _busyCard(busyLabel)
                            : _waveBubble(),
                  ),
                  if (busyLabel == null)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: _bottomPanel(value.mode),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 录音中的绿色气泡，里面跳动声波
  Widget _waveBubble() {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Positioned(
          bottom: -7,
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(width: 14, height: 14, color: _bubbleColor),
          ),
        ),
        Container(
          width: 238,
          height: 92,
          decoration: BoxDecoration(
            color: _bubbleColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: AnimatedBuilder(
              animation: _wave,
              builder: (context, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: List.generate(21, (index) {
                    final phase = _wave.value * 2 * math.pi + index * 0.55;
                    final falloff = 1 - (index - 10).abs() / 24;
                    final height =
                        9 + 26 * (0.5 + 0.5 * math.sin(phase)) * falloff;
                    return Container(
                      width: 3,
                      height: height,
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// 底部操作区：左取消、右转文字、中间松开发送
  Widget _bottomPanel(_HoldMode mode) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 32),
      decoration: const BoxDecoration(
        color: Color(0xFFEDEDED),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: _zone('取消', mode == _HoldMode.cancel, danger: true),
              ),
              const SizedBox(width: 16),
              Expanded(child: _zone('滑到这里 转文字', mode == _HoldMode.text)),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            '松开 发送',
            style: TextStyle(fontSize: 15, color: Color(0xFF333333)),
          ),
        ],
      ),
    );
  }

  Widget _zone(String label, bool active, {bool danger = false}) {
    final color = danger ? const Color(0xFFE53935) : AppColors.primary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? color : Colors.white,
        borderRadius: BorderRadius.circular(29),
        border: Border.all(color: active ? color : const Color(0xFFDDDDDD)),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          color: active ? Colors.white : const Color(0xFF555555),
        ),
      ),
    );
  }

  Widget _busyCard(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}
