import 'package:flutter/material.dart';

import '../../../core/accessibility/elder_care_reader.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/data/auth_session.dart';
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

  /// 作者名：自己改过昵称后，历史帖子也展示新昵称
  String get _authorName => AuthSession.instance.displayName(post.author);

  String get _avatarText {
    if (_authorName.isEmpty) return '?';
    return String.fromCharCode(_authorName.runes.first);
  }

  @override
  Widget build(BuildContext context) {
    // 监听登录用户变化，资料改昵称后论坛立即同步
    return ValueListenableBuilder<AuthUser?>(
      valueListenable: AuthSession.instance.user,
      builder:
          (context, _, __) => ElderCareBlock(
            // 只朗读昵称与提问/回答内容，跳过时间、版块与点赞
            readText: '$_authorName。${post.title}。${post.content}',
            child: _buildCard(context),
          ),
    );
  }

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
                  _buildAuthorRow(context),
                  const SizedBox(height: 7),
                  Text(
                    post.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: context.palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    post.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: context.palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildFooter(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthorRow(BuildContext context) {
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
                _authorName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: context.palette.textPrimary,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                forumTimeText(post.createdAt),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: context.palette.textHint),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(BuildContext context) {
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
                  _tag(context, '#${post.section}'),
                  for (final tag in post.tags) _tag(context, '#$tag'),
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
                  color:
                      favorited ? AppColors.primary : context.palette.textHint,
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
                      : context.palette.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  liked ? Icons.favorite : Icons.favorite_border,
                  size: 14,
                  color: liked ? AppColors.accent : context.palette.textHint,
                ),
                const SizedBox(width: 3),
                Text(
                  '${post.likes}',
                  style: TextStyle(
                    fontSize: 11,
                    color: liked ? AppColors.accent : context.palette.textHint,
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

  Widget _tag(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: context.palette.surfaceVariant,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: context.palette.textHint),
      ),
    );
  }
}
