import 'package:flutter/material.dart';

import '../../../core/accessibility/elder_care_reader.dart';
import '../../../core/theme/app_theme.dart';
import '../data/forum_models.dart';

/// 消息类型到图标的映射
IconData forumMessageIcon(ForumMessageKind kind) {
  switch (kind) {
    case ForumMessageKind.like:
      return Icons.favorite_border;
    case ForumMessageKind.reply:
      return Icons.reply_outlined;
    case ForumMessageKind.favorite:
      return Icons.bookmark_border;
    case ForumMessageKind.announcement:
      return Icons.campaign_outlined;
    case ForumMessageKind.moderation:
      return Icons.shield_outlined;
  }
}

/// 消息类型到主题色的映射
Color forumMessageColor(ForumMessageKind kind) {
  switch (kind) {
    case ForumMessageKind.like:
      return AppColors.accent;
    case ForumMessageKind.reply:
      return AppColors.primary;
    case ForumMessageKind.favorite:
      return AppColors.primaryLight;
    case ForumMessageKind.announcement:
    case ForumMessageKind.moderation:
      return AppColors.primary;
  }
}

/// 单条消息
class ForumMessageTile extends StatelessWidget {
  const ForumMessageTile({
    super.key,
    required this.message,
    required this.onTap,
    this.onReply,
  });

  final ForumMessage message;
  final VoidCallback onTap;

  /// 点击「回复」回调，回复类消息才传入
  final VoidCallback? onReply;

  @override
  Widget build(BuildContext context) =>
      ElderCareBlock(child: _buildTile(context));

  Widget _buildTile(BuildContext context) {
    final unread = message.unread;
    final color = forumMessageColor(message.kind);

    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.surfaceVariant),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      forumMessageIcon(message.kind),
                      size: 22,
                      color: color,
                    ),
                  ),
                  if (unread)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.surface,
                            width: 1.5,
                          ),
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
                    if (onReply != null) ...[
                      const SizedBox(height: 2),
                      Align(
                        alignment: Alignment.centerRight,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: onReply,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.reply,
                                  size: 14,
                                  color: AppColors.primary,
                                ),
                                SizedBox(width: 3),
                                Text(
                                  '回复',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
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
