import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../data/forum_repository.dart';
import '../forum_scope.dart';
import '../widgets/forum_empty_state.dart';
import '../widgets/forum_post_list.dart';

/// 版块帖子列表
class ForumSectionPage extends StatelessWidget {
  const ForumSectionPage({
    super.key,
    required this.section,
    this.repository,
  });

  final String section;

  /// 外部注入的数据源，为空时取 ForumScope 或默认实现
  final ForumRepository? repository;

  @override
  Widget build(BuildContext context) {
    final repo = repository ?? ForumScope.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(section)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/forum/compose', extra: section),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('发帖'),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
      ),
      body: AnimatedBuilder(
        animation: repo,
        builder: (context, _) {
          final posts = repo.postsOf(section);
          if (posts.isEmpty) {
            return ForumEmptyState(
              icon: Icons.forum_outlined,
              text: '「$section」还没有帖子',
              actionLabel: '去发帖',
              onAction: () => context.push('/forum/compose', extra: section),
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
