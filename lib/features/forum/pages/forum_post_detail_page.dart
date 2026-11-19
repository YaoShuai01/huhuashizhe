import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/forum_models.dart';
import '../data/forum_repository.dart';
import '../forum_scope.dart';
import '../widgets/forum_back_button.dart';
import '../widgets/forum_comment_tile.dart';
import '../widgets/forum_responsive_body.dart';

/// 帖子详情：查看正文、点赞、收藏与评论
class ForumPostDetailPage extends StatefulWidget {
  const ForumPostDetailPage({super.key, required this.post, this.repository});

  final ForumPost post;

  /// 外部注入的数据源，为空时取 ForumScope 或默认实现
  final ForumRepository? repository;

  @override
  State<ForumPostDetailPage> createState() => _ForumPostDetailPageState();
}

class _ForumPostDetailPageState extends State<ForumPostDetailPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _canSend = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send(ForumRepository repository) {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    repository.addComment(post: widget.post, content: text);
    _controller.clear();
    _focusNode.unfocus();
    setState(() => _canSend = false);
  }

  void _toggleFavorite(ForumRepository repository) {
    final wasFavorite = repository.isFavorite(widget.post);
    repository.toggleFavorite(widget.post);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          wasFavorite ? '已取消收藏' : '已收藏，可在「我的 - 我的收藏」查看',
        ),
        duration: const Duration(milliseconds: 1500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository ?? ForumScope.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const ForumBackButton(),
        title: const Text('帖子详情'),
        actions: [
          AnimatedBuilder(
            animation: repository,
            builder: (context, _) {
              final favorited = repository.isFavorite(widget.post);
              return IconButton(
                tooltip: favorited ? '取消收藏' : '收藏',
                onPressed: () => _toggleFavorite(repository),
                icon: Icon(
                  favorited ? Icons.bookmark : Icons.bookmark_border,
                  color: AppColors.textOnPrimary,
                ),
              );
            },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: repository,
        builder: (context, _) {
          final comments = repository.commentsOf(widget.post.id);
          return ForumResponsiveBody(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(top: 10, bottom: 10),
                    children: [
                      _postHeader(repository),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Text(
                          '全部评论 ${comments.length}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (comments.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: Text(
                              '还没有评论，来说两句',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textHint,
                              ),
                            ),
                          ),
                        )
                      else
                        for (final comment in comments)
                          ForumCommentTile(comment: comment),
                    ],
                  ),
                ),
                _commentBar(repository),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _postHeader(ForumRepository repository) {
    final post = widget.post;
    final avatarText = post.author.isEmpty
        ? '?'
        : String.fromCharCode(post.author.runes.first);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    avatarText,
                    style: const TextStyle(
                      fontSize: 14,
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
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
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
            const SizedBox(height: 12),
            Text(
              post.title,
              style: const TextStyle(
                fontSize: 17,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              post.content,
              style: const TextStyle(
                fontSize: 14,
                height: 1.6,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        post.section,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textHint,
                        ),
                      ),
                    ),
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => repository.toggleLike(post),
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
                          size: 16,
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
                const SizedBox(width: 4),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _toggleFavorite(repository),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          repository.isFavorite(post)
                              ? Icons.bookmark
                              : Icons.bookmark_border,
                          size: 16,
                          color: repository.isFavorite(post)
                              ? AppColors.accent
                              : AppColors.textHint,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          repository.isFavorite(post) ? '已收藏' : '收藏',
                          style: TextStyle(
                            fontSize: 12,
                            color: repository.isFavorite(post)
                                ? AppColors.accent
                                : AppColors.textHint,
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
    );
  }

  Widget _commentBar(ForumRepository repository) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(color: AppColors.surfaceVariant),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                minLines: 1,
                maxLines: 3,
                maxLength: 300,
                buildCounter: (context,
                        {required currentLength,
                        required isFocused,
                        required maxLength}) =>
                    null,
                onChanged: (value) {
                  final canSend = value.trim().isNotEmpty;
                  if (canSend != _canSend) {
                    setState(() => _canSend = canSend);
                  }
                },
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: '写下你的评论…',
                  hintStyle: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textHint,
                  ),
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.surfaceVariant,
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
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: '发送评论',
              onPressed: _canSend ? () => _send(repository) : null,
              icon: const Icon(Icons.send, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}
