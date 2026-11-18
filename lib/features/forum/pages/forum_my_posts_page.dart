import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../data/forum_repository.dart';
import '../forum_scope.dart';
import '../widgets/forum_empty_state.dart';
import '../widgets/forum_post_list.dart';

/// 我的帖子
class ForumMyPostsPage extends StatelessWidget {
  const ForumMyPostsPage({super.key, this.repository});

  /// 外部注入的数据源，为空时取 ForumScope 或默认实现
  final ForumRepository? repository;

  @override
  Widget build(BuildContext context) {
    final repo = repository ?? ForumScope.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('我的帖子')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/forum/compose'),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('发帖'),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
      ),
      body: AnimatedBuilder(
        animation: repo,
        builder: (context, _) {
          final posts = repo.myPosts;
          if (posts.isEmpty) {
            return ForumEmptyState(
              icon: Icons.article_outlined,
              text: '还没有发过帖子',
              actionLabel: '去发帖',
              onAction: () => context.push('/forum/compose'),
            );
          }
          return ForumPostList(
            posts: posts,
            onLike: repo.toggleLike,
          );
        },
      ),
    );
  }
}
