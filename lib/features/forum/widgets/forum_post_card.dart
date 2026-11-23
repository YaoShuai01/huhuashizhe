import 'package:flutter/material.dart';

import '../../../core/accessibility/elder_care_reader.dart';
import '../../../core/theme/app_theme.dart';
import '../data/forum_models.dart';
import 'forum_post_image.dart';

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
    this.liked = false,
    this.margin,
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

  /// 当前用户是否已点赞
  final bool liked;

  /// 卡片外边距，为空时沿用主题默认值（瀑布流内需传零边距）
  final EdgeInsetsGeometry? margin;

  String get _avatarText {
    if (post.author.isEmpty) return '?';
    return String.fromCharCode(post.author.runes.first);
  }

  @override
  Widget build(BuildContext context) => ElderCareBlock(
    // 只朗读昵称与提问/回答内容，跳过时间、版块与点赞
    readText: '${post.author}。${post.title}。${post.content}',
    child: _buildCard(context),
  );

  Widget _buildCard(BuildContext context) {
    return Card(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (post.images.isNotEmpty)
              ForumPostImage(
                url: post.images.first,
                aspectRatio: 1,
                borderRadius: 0,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAuthorRow(),
                  const SizedBox(height: 7),
                  Text(
                    post.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
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
                  const SizedBox(height: 10),
                  _buildFooter(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthorRow() {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primaryLight.withValues(alpha: 0.16),
            shape: BoxShape.circle,
          ),
          child: Text(
            _avatarText,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                post.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                forumTimeText(post.createdAt),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: AppColors.textHint),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Row(
      children: [
        if (showSection)
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (post.featured) _featuredTag(),
                  if (post.pendingReview) _pendingTag(),
                  _tag('#${post.section}'),
                  for (final tag in post.tags) _tag('#$tag'),
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
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Icon(
                  favorited ? Icons.bookmark : Icons.bookmark_border,
                  size: 16,
                  color: favorited ? AppColors.primary : AppColors.textHint,
                ),
              ),
            ),
          ),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onLike,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color:
                  liked
                      ? AppColors.accent.withValues(alpha: 0.12)
                      : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  liked ? Icons.favorite : Icons.favorite_border,
                  size: 14,
                  color: liked ? AppColors.accent : AppColors.textHint,
                ),
                const SizedBox(width: 3),
                Text(
                  '${post.likes}',
                  style: TextStyle(
                    fontSize: 11,
                    color: liked ? AppColors.accent : AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _featuredTag() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        '精选',
        maxLines: 1,
        style: TextStyle(
          fontSize: 11,
          color: AppColors.accent,
          fontWeight: FontWeight.w600,
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
