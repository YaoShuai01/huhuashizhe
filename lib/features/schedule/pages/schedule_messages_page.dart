import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/schedule_api.dart';
import '../../../services/schedule_message_service.dart';
import '../../../services/schedule_service.dart';
import '../models/schedule_models.dart';

/// 轮协匿名留言池
class ScheduleMessagesPage extends StatefulWidget {
  const ScheduleMessagesPage({super.key});

  @override
  State<ScheduleMessagesPage> createState() => _ScheduleMessagesPageState();
}

class _ScheduleMessagesPageState extends State<ScheduleMessagesPage> {
  final ScheduleMessageService _service = ScheduleMessageService.instance;
  final TextEditingController _draftController = TextEditingController();

  bool _loading = true;
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _service.markSeen();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(silent: false));
  }

  @override
  void dispose() {
    _draftController.dispose();
    super.dispose();
  }

  Future<void> _load({required bool silent}) async {
    if (!silent) setState(() => _loading = true);
    try {
      await _service.refresh(silent: silent);
      if (!mounted) return;
      _service.markSeen();
      setState(() => _loading = false);
    } on ScheduleAuthException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast(e.message);
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  Future<void> _publish() async {
    final content = _draftController.text.trim();
    if (content.isEmpty) {
      _toast('请输入留言内容');
      return;
    }
    setState(() => _posting = true);
    try {
      await _service.postMessage(content);
      if (!mounted) return;
      _draftController.clear();
      _service.markSeen();
      setState(() => _posting = false);
      FocusScope.of(context).unfocus();
      _toast('留言已发布');
    } on ScheduleApiException catch (e) {
      if (!mounted) return;
      setState(() => _posting = false);
      _toast(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _posting = false);
      _toast('留言发布失败');
    }
  }

  Future<void> _openReply(ScheduleMessage message) async {
    if (!_service.isOnline) {
      _toast('服务器未启动，暂时无法回复');
      return;
    }
    final controller = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
 (ctx) => Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              20 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '回复留言',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.palette.surfaceVariant,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    message.content,
                    style:  TextStyle(
                      fontSize: 13,
                      color: context.palette.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 1000,
                  maxLines: 4,
                  minLines: 3,
                  decoration: const InputDecoration(
                    hintText: '写下你的回复...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('发布回复'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
    );
    if (ok == true && mounted) {
      final content = controller.text.trim();
      if (content.isEmpty) {
        _toast('请输入回复内容');
        return;
      }
      try {
        await _service.postReply(message.id, content);
        if (!mounted) return;
        _service.markSeen();
        setState(() {});
        _toast('回复已发布');
      } on ScheduleApiException catch (e) {
        if (!mounted) return;
        _toast(e.message);
      } catch (e) {
        if (!mounted) return;
        _toast('回复发布失败');
      }
    }
    controller.dispose();
  }

  Future<void> _deleteMessage(ScheduleMessage message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
 (ctx) => AlertDialog(
            title: const Text('删除留言'),
            content: const Text('删除后，这条留言下的所有回复也会一起消失，确定吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('删除'),
              ),
            ],
          ),
    );
    if (ok != true) return;
    try {
      await _service.deleteMessage(message.id);
      if (!mounted) return;
      setState(() {});
      _toast('留言已删除');
    } on ScheduleApiException catch (e) {
      if (!mounted) return;
      _toast(e.message);
    }
  }

  Future<void> _deleteReply(ScheduleReply reply) async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
 (ctx) => AlertDialog(
            title: const Text('删除回复'),
            content: const Text('确定删除这条回复吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('删除'),
              ),
            ],
          ),
    );
    if (ok != true) return;
    try {
      await _service.deleteReply(reply.id);
      if (!mounted) return;
      setState(() {});
      _toast('回复已删除');
    } on ScheduleApiException catch (e) {
      if (!mounted) return;
      _toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = _service.messages;
    return Scaffold(
      appBar: AppBar(title: const Text('留言池')),
      body: RefreshIndicator(
        onRefresh: () => _load(silent: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            _buildIntro(),
            const SizedBox(height: 12),
            if (!_service.isOnline) ...[
              _buildOfflineBanner(),
              const SizedBox(height: 12),
            ],
            _buildComposer(),
            const SizedBox(height: 14),
            if (_loading && messages.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (messages.isEmpty)
              _buildEmpty()
            else
              for (final message in messages) ...[
                _buildMessageCard(message),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }

  Widget _buildIntro() {
    return  Row(
      children: [
        Icon(Icons.lock_outline, size: 15, color: context.palette.textHint),
        SizedBox(width: 5),
        Expanded(
          child: Text(
            '匿名留言，管理员也看不到你的姓名',
            style: TextStyle(fontSize: 12, color: context.palette.textHint),
          ),
        ),
      ],
    );
  }

  Widget _buildOfflineBanner() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.wifi_off_rounded,
            size: 18,
            color: AppColors.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _service.error ?? '服务器未启动，当前显示本地缓存。',
              style:  TextStyle(
                fontSize: 12,
                height: 1.45,
                color: context.palette.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _load(silent: false),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.warning,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    final online = _service.isOnline;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _draftController,
            minLines: 3,
            maxLines: 5,
            maxLength: 1000,
            enabled: online && !_posting,
            decoration: const InputDecoration(
              hintText: '匿名写下你的压力或想说的话...',
              border: OutlineInputBorder(),
              isDense: true,
              counterText: '',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
               Expanded(
                child: Text(
                  '自己的留言和回复只有自己和管理员能删除',
                  style: TextStyle(fontSize: 11, color: context.palette.textHint),
                ),
              ),
              FilledButton(
                onPressed: online && !_posting ? _publish : null,
                child:
 _posting
                        ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Text('发布留言'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return  Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.forum_outlined, size: 48, color: context.palette.textDisabled),
          SizedBox(height: 12),
          Text(
            '还没有留言，匿名写下第一句吧',
            style: TextStyle(fontSize: 13, color: context.palette.textHint),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageCard(ScheduleMessage message) {
    final isAdmin = ScheduleService.instance.isAdmin;
    final canDelete = isAdmin || message.isMine;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.content,
            style: const TextStyle(fontSize: 14, height: 1.55),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                _formatTime(message.createdAt),
                style:  TextStyle(fontSize: 11, color: context.palette.textHint),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color:
 message.isMine
                          ? AppColors.primary.withValues(alpha: 0.1)
                          : context.palette.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  message.isMine ? '我' : '匿名',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color:
 message.isMine ? AppColors.primary : context.palette.textHint,
                  ),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => _openReply(message),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('回复'),
              ),
              if (canDelete)
                TextButton(
                  onPressed: () => _deleteMessage(message),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.error,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('删除'),
                ),
            ],
          ),
          if (message.replies.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final reply in message.replies) ...[
              _buildReplyRow(reply, isAdmin),
              const SizedBox(height: 6),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildReplyRow(ScheduleReply reply, bool isAdmin) {
    final canDelete = isAdmin || reply.isMine;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 6),
      decoration: BoxDecoration(
        color: context.palette.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            reply.content,
            style: const TextStyle(fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_formatTime(reply.createdAt)}${reply.isMine ? ' · 我' : ''}',
                  style:  TextStyle(
                    fontSize: 10,
                    color: context.palette.textHint,
                  ),
                ),
              ),
              if (canDelete)
                GestureDetector(
                  onTap: () => _deleteReply(reply),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      '删除',
                      style: TextStyle(fontSize: 11, color: AppColors.error),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(String raw) {
    final parsed = DateTime.tryParse(raw)?.toLocal();
    if (parsed == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(parsed.year, parsed.month, parsed.day);
    final diff = today.difference(day).inDays;
    final hm =
        '${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
    if (diff == 0) return '今天 $hm';
    if (diff == 1) return '昨天 $hm';
    if (parsed.year == now.year) return '${parsed.month}月${parsed.day}日 $hm';
    return '${parsed.year}年${parsed.month}月${parsed.day}日 $hm';
  }
}
