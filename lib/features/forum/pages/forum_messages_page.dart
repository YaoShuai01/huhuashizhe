import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/forum_models.dart';
import '../data/forum_repository.dart';
import '../forum_scope.dart';
import '../widgets/forum_back_button.dart';
import '../widgets/forum_empty_state.dart';
import '../widgets/forum_message_category_card.dart';
import '../widgets/forum_message_tile.dart';
import '../widgets/forum_responsive_body.dart';

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
                         Expanded(
                          child: Text(
                            '消息列表',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: context.palette.textPrimary,
                            ),
                          ),
                        ),
                        Flexible(
                          child: Text(
                            '共 ${messages.length} 条',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:  TextStyle(
                              fontSize: 12,
                              color: context.palette.textHint,
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
                    for (final message in messages)
                      ForumMessageTile(
                        message: message,
                        onTap: () => repository.markMessageRead(message),
                      ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  int _unreadCount(List<ForumMessage> messages) =>
      messages.where((m) => m.unread).length;
}
