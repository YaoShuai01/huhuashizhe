import 'package:flutter/material.dart';

import '../../../core/accessibility/elder_care_reader.dart';
import '../../../core/theme/app_theme.dart';
import '../data/forum_models.dart';

/// 帖子卡片（版块列表、我的帖子共用）
class ForumPostCard extends StatelessWidget {
  const ForumPostCard({
    super.key,
    required this.post,
    required this.onLike,
    this.onTap,
    this.showSection = true,
    this.favorited = false,
    this.onFavorite,
  });

  final ForumPost post;
  final VoidCallback onLike;
  final VoidCallback? onTap;

  /// 是否展示所属版块标签（我的帖子页可关闭）
  final bool showSection;

  /// 当前是否已收藏
  final bool favorited;

  /// 收藏切换回调，为空时不展示收藏入口
  final VoidCallback? onFavorite;

  String get _avatarText {
    if (post.author.isEmpty) return '?';
    return String.fromCharCode(post.author.runes.first);
  }

  @override
  Widget build(BuildContext context) =>
      ElderCareBlock(child: _buildCard(context));

  Widget _buildCard(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                    child: Text(
                      post.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      forumTimeText(post.createdAt),
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
              const SizedBox(height: 8),
              Text(
                post.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                post.content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (showSection)
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (post.pendingReview) _pendingTag(),
                            _tag(post.section),
                          ],
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  if (onFavorite != null)
                    Tooltip(
                      message: favorited ? '取消收藏' : '收藏',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: onFavorite,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Icon(
                            favorited
                                ? Icons.bookmark
                                : Icons.bookmark_border,
                            size: 16,
                            color: favorited
                                ? AppColors.primary
                                : AppColors.textHint,
                          ),
                        ),
                      ),
                    ),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: onLike,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            post.likes > 0
                                ? Icons.favorite
                                : Icons.favorite_border,
                            size: 15,
                            color: post.likes > 0
                                ? AppColors.accent
                                : AppColors.textHint,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${post.likes}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textHint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pendingTag() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        '待复审',
        maxLines: 1,
        style: TextStyle(
          fontSize: 11,
          color: AppColors.accent,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _tag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, color: AppColors.textHint),
      ),
    );
  }
}
