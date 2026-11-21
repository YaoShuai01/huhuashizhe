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
  });

  final ForumMessage message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) =>
      ElderCareBlock(child: _buildTile(context));

  Widget _buildTile(BuildContext context) {
    final unread = message.unread;
    final color = forumMessageColor(message.kind);

    return Material(
      color: context.palette.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration:  BoxDecoration(
            border: Border(
              bottom: BorderSide(color: context.palette.surfaceVariant),
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
                            color: context.palette.surface,
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
                              color: context.palette.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            forumTimeText(message.createdAt),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:  TextStyle(
                              fontSize: 11,
                              color: context.palette.textHint,
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
                      style:  TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: context.palette.textSecondary,
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
