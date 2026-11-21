import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/forum_repository.dart';
import '../forum_scope.dart';
import '../widgets/forum_back_button.dart';
import '../widgets/forum_empty_state.dart';
import '../widgets/forum_post_list.dart';

/// 我的收藏
class ForumFavoritesPage extends StatelessWidget {
  const ForumFavoritesPage({super.key, this.repository});

  /// 外部注入的数据源，为空时取 ForumScope 或默认实现
  final ForumRepository? repository;

  @override
  Widget build(BuildContext context) {
    final repo = repository ?? ForumScope.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const ForumBackButton(),
        title: const Text('我的收藏'),
      ),
      body: AnimatedBuilder(
        animation: repo,
        builder: (context, _) {
          final posts = repo.favoritePosts;
          if (posts.isEmpty) {
            return ForumEmptyState(
              icon: Icons.bookmark_border,
              text: '还没有收藏的帖子',
              actionLabel: '去论坛看看',
              onAction: () => context.go('/forum'),
            );
          }
          return ForumPostList(
            posts: posts,
            onLike: repo.toggleLike,
            onRefresh: repo.refresh,
            isFavorite: repo.isFavorite,
            onFavorite: repo.toggleFavorite,
            isLiked: repo.isLiked,
            onTapPost: (post) => context.push('/forum/post', extra: post),
          );
        },
      ),
    );
  }
}
