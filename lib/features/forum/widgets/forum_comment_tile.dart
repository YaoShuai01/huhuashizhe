import 'package:flutter/material.dart';

import '../../../core/accessibility/elder_care_reader.dart';
import '../../../core/theme/app_theme.dart';
import '../data/forum_models.dart';

/// 单条评论
class ForumCommentTile extends StatelessWidget {
  const ForumCommentTile({super.key, required this.comment});

  final ForumComment comment;

  String get _avatarText {
    if (comment.author.isEmpty) return '?';
    return String.fromCharCode(comment.author.runes.first);
  }

  @override
  Widget build(BuildContext context) => ElderCareBlock(
        // 只朗读昵称与评论内容，跳过时间
        readText: '${comment.author}。${comment.content}',
        child: _buildTile(context),
      );

  Widget _buildTile(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Text(
              _avatarText,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        comment.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:  TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.palette.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        forumTimeText(comment.createdAt),
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
                const SizedBox(height: 4),
                Text(
                  comment.content,
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
    );
  }
}
