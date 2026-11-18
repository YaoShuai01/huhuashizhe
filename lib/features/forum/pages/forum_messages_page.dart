import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/forum_repository.dart';
import '../forum_scope.dart';
import '../widgets/forum_empty_state.dart';
import '../widgets/forum_message_tile.dart';
import '../widgets/forum_responsive_body.dart';

/// 消息提醒
class ForumMessagesPage extends StatelessWidget {
  const ForumMessagesPage({super.key, this.repository});

  /// 外部注入的数据源，为空时取 ForumScope 或默认实现
  final ForumRepository? repository;

  @override
  Widget build(BuildContext context) {
    final repo = repository ?? ForumScope.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('消息提醒'),
        actions: [
          AnimatedBuilder(
            animation: repo,
            builder: (context, _) {
              final hasUnread = repo.hasUnreadMessages;
              return TextButton(
                onPressed: hasUnread ? repo.markAllMessagesRead : null,
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
        animation: repo,
        builder: (context, _) {
          final messages = repo.messages;
          if (messages.isEmpty) {
            return const ForumEmptyState(
              icon: Icons.notifications_none,
              text: '暂无消息',
            );
          }
          return ForumResponsiveBody(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ListView.builder(
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final message = messages[index];
                return ForumMessageTile(
                  message: message,
                  onTap: () => repo.markMessageRead(message),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
