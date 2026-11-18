import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/forum_models.dart';

/// 消息类型到图标的映射
IconData forumMessageIcon(ForumMessageKind kind) {
  switch (kind) {
    case ForumMessageKind.announcement:
      return Icons.campaign_outlined;
    case ForumMessageKind.reply:
      return Icons.reply_outlined;
    case ForumMessageKind.moderation:
      return Icons.shield_outlined;
  }
}

/// 单条消息卡片
class ForumMessageTile extends StatelessWidget {
  const ForumMessageTile({
    super.key,
    required this.message,
    required this.onTap,
  });

  final ForumMessage message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = message.unread;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      forumMessageIcon(message.kind),
                      size: 20,
                      color: AppColors.primary,
                    ),
                  ),
                  if (unread)
                    Positioned(
                      right: -1,
                      top: -1,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: AppColors.error,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            message.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: unread
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            forumTimeText(message.createdAt),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textHint,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      message.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
