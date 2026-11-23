import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/data/auth_session.dart';
import '../data/forum_models.dart';
import '../data/forum_repository.dart';
import '../forum_scope.dart';
import '../services/forum_moderation_service.dart';
import '../widgets/forum_back_button.dart';
import '../widgets/forum_empty_state.dart';
import '../widgets/forum_message_category_card.dart';
import '../widgets/forum_message_tile.dart';
import '../widgets/forum_responsive_body.dart';
import '../widgets/forum_voice_comment.dart';

/// 消息提醒：点赞 / 回复两个分支
class ForumMessagesPage extends StatefulWidget {
  const ForumMessagesPage({super.key, this.repository});

  /// 外部注入的数据源，为空时取 ForumScope 或默认实现
  final ForumRepository? repository;

  @override
  State<ForumMessagesPage> createState() => _ForumMessagesPageState();
}

class _ForumMessagesPageState extends State<ForumMessagesPage> {
  static const Color _likeColor = AppColors.accent;
  static const Color _replyColor = AppColors.primary;
  static const Color _favoriteColor = AppColors.primaryLight;

  ForumMessageKind _kind = ForumMessageKind.like;
  bool _messagesRequested = false;
  ForumRepository? _repository;
  Timer? _messageTimer;

  /// 正在内联回复的消息 id
  String? _replyingMessageId;
  final TextEditingController _replyController = TextEditingController();
  bool _sendingReply = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_messagesRequested) return;
    _messagesRequested = true;
    final repository = widget.repository ?? ForumScope.of(context);
    _repository = repository;
    _loadMessages();
    // 消息页独立打开（首页未挂载）时也能实时刷新
    if (repository.supportsRealtimeMessages) {
      _messageTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => _loadMessages(),
      );
    }
  }

  @override
  void dispose() {
    _messageTimer?.cancel();
    _replyController.dispose();
    super.dispose();
  }

  /// 打开消息页时从服务器拉取最新消息
  Future<void> _loadMessages() async {
    final repository = _repository;
    if (repository == null) return;
    try {
      await repository.loadMessages();
    } on ForumException {
      // 静默失败，下拉刷新可重试
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository ?? ForumScope.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const ForumBackButton(),
        title: const Text('消息提醒'),
        actions: [
          AnimatedBuilder(
            animation: repository,
            builder: (context, _) {
              final hasUnread = repository.hasUnreadMessages;
              return TextButton(
                onPressed: hasUnread ? repository.markAllMessagesRead : null,
                child: Text(
                  '全部已读',
                  style: TextStyle(
                    color: hasUnread
                        ? AppColors.textOnPrimary
                        : AppColors.textOnPrimary.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: repository,
        builder: (context, _) {
          final likeMessages =
              repository.messagesOf(ForumMessageKind.like);
          final replyMessages =
              repository.messagesOf(ForumMessageKind.reply);
          final favoriteMessages =
              repository.messagesOf(ForumMessageKind.favorite);
          final messages = switch (_kind) {
            ForumMessageKind.reply => replyMessages,
            ForumMessageKind.favorite => favoriteMessages,
            _ => likeMessages,
          };

          return ForumResponsiveBody(
            child: RefreshIndicator(
              onRefresh: repository.refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: ForumMessageCategoryCard(
                            label: '点赞',
                            icon: Icons.thumb_up_alt_outlined,
                            color: _likeColor,
                            selected: _kind == ForumMessageKind.like,
                            unreadCount: _unreadCount(likeMessages),
                            onTap: () => setState(
                              () => _kind = ForumMessageKind.like,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ForumMessageCategoryCard(
                            label: '收藏',
                            icon: Icons.bookmark_border,
                            color: _favoriteColor,
                            selected: _kind == ForumMessageKind.favorite,
                            unreadCount: _unreadCount(favoriteMessages),
                            onTap: () => setState(
                              () => _kind = ForumMessageKind.favorite,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ForumMessageCategoryCard(
                            label: '回复',
                            icon: Icons.chat_bubble_outline,
                            color: _replyColor,
                            selected: _kind == ForumMessageKind.reply,
                            unreadCount: _unreadCount(replyMessages),
                            onTap: () => setState(
                              () => _kind = ForumMessageKind.reply,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '消息列表',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        Flexible(
                          child: Text(
                            '共 ${messages.length} 条',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textHint,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (messages.isEmpty)
                    SizedBox(
                      height: 320,
                      child: ForumEmptyState(
                        icon: Icons.notifications_none,
                        text: switch (_kind) {
                          ForumMessageKind.reply => '暂无回复消息',
                          ForumMessageKind.favorite => '暂无收藏消息',
                          _ => '暂无点赞消息',
                        },
                      ),
                    )
                  else
                    for (final message in messages) ...[
                      ForumMessageTile(
                        message: message,
                        onTap: () => repository.markMessageRead(message),
                        onReply:
                            message.kind == ForumMessageKind.reply &&
                                    message.postId != null
                                ? () => _toggleReply(message)
                                : null,
                      ),
                      if (_replyingMessageId == message.id)
                        _inlineReplyComposer(repository, message),
                    ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _toggleReply(ForumMessage message) {
    setState(() {
      if (_replyingMessageId == message.id) {
        _replyingMessageId = null;
      } else {
        _replyingMessageId = message.id;
        _replyController.clear();
      }
    });
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// 在消息内直接回复到对应帖子
  Future<void> _sendInlineReply(
    ForumRepository repository,
    ForumMessage message,
  ) async {
    if (!AuthSession.instance.isLoggedIn) {
      _toast('登录后才能回复');
      return;
    }
    final text = _replyController.text.trim();
    if (text.isEmpty || _sendingReply) return;
    setState(() => _sendingReply = true);

    try {
      final audit = await defaultForumModerationService.review(
        title: '评论：${message.title}',
        content: text,
      );
      if (audit.rejected) {
        if (mounted) _toast('内容未通过审核：${audit.reason}');
        return;
      }

      final postId = message.postId;
      var post = postId == null ? null : repository.postById(postId);
      if (post == null) {
        try {
          await repository.refresh();
        } on ForumException {
          // 刷新失败时继续按未加载处理
        }
        post = postId == null ? null : repository.postById(postId);
      }
      if (post == null) {
        if (mounted) _toast('帖子已被删除或暂未加载');
        return;
      }

      await repository.addComment(post: post, content: text);
      repository.markMessageRead(message);
      _replyController.clear();
      if (!mounted) return;
      setState(() => _replyingMessageId = null);
      _toast('回复已发送');
    } on ForumException catch (error) {
      if (mounted) _toast(error.message);
    } finally {
      if (mounted) setState(() => _sendingReply = false);
    }
  }

  Widget _inlineReplyComposer(
    ForumRepository repository,
    ForumMessage message,
  ) {
    final post = repository.postById(message.postId ?? '');
    return Container(
      color: AppColors.surfaceVariant.withValues(alpha: 0.35),
      padding: const EdgeInsets.fromLTRB(16, 2, 10, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _replyController,
              minLines: 1,
              maxLines: 3,
              maxLength: 450,
              buildCounter:
                  (
                    context, {
                    required currentLength,
                    required isFocused,
                    required maxLength,
                  }) => null,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: '回复这条消息…',
                hintStyle: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textHint,
                ),
                isDense: true,
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (post != null)
            ForumVoiceCommentButton(
              repository: repository,
              post: post,
              onSent: () {
                repository.markMessageRead(message);
                if (!mounted) return;
                setState(() => _replyingMessageId = null);
              },
            ),
          IconButton.filled(
            tooltip: '发送回复',
            onPressed:
                _sendingReply
                    ? null
                    : () => _sendInlineReply(repository, message),
            icon:
                _sendingReply
                    ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.textOnPrimary,
                      ),
                    )
                    : const Icon(Icons.send, size: 18),
          ),
        ],
      ),
    );
  }

  int _unreadCount(List<ForumMessage> messages) =>
      messages.where((m) => m.unread).length;
}
