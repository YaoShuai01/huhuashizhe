import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../classroom/data/classroom_courses.dart';
import '../../classroom/data/classroom_store.dart';
import '../../classroom/widgets/course_card.dart';
import '../data/forum_repository.dart';
import '../forum_scope.dart';
import '../widgets/forum_back_button.dart';
import '../widgets/forum_empty_state.dart';
import '../widgets/forum_post_list.dart';

/// 我的收藏：帖子 / 课程两个分类
class ForumFavoritesPage extends StatelessWidget {
  const ForumFavoritesPage({super.key, this.repository});

  /// 外部注入的数据源，为空时取 ForumScope 或默认实现
  final ForumRepository? repository;

  @override
  Widget build(BuildContext context) {
    final repo = repository ?? ForumScope.of(context);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          leading: const ForumBackButton(),
          title: const Text('我的收藏'),
          bottom: const TabBar(
            tabs: [Tab(text: '帖子'), Tab(text: '课程')],
          ),
        ),
        body: TabBarView(
          children: [
            _PostsTab(repository: repo),
            const _CoursesTab(),
          ],
        ),
      ),
    );
  }
}

class _PostsTab extends StatelessWidget {
  const _PostsTab({required this.repository});

  final ForumRepository repository;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: repository,
      builder: (context, _) {
        final posts = repository.favoritePosts;
        if (posts.isEmpty) {
          return ForumEmptyState(
            icon: Icons.bookmark_border,
            text: '还没有收藏的帖子',
            actionLabel: '去论坛看看',
            onAction: () => context.push('/forum'),
          );
        }
        return ForumPostList(
          posts: posts,
          onLike: repository.toggleLike,
          onRefresh: repository.refresh,
          isFavorite: repository.isFavorite,
          onFavorite: repository.toggleFavorite,
          isLiked: repository.isLiked,
          onTapPost: (post) => context.push('/forum/post', extra: post),
        );
      },
    );
  }
}

class _CoursesTab extends StatelessWidget {
  const _CoursesTab();

  Future<void> _openCourse(BuildContext context, Course course) async {
    final reads = ClassroomStore.instance.incrementRead(course.id);
    await context.push(
      '/classroom/course',
      extra: <String, dynamic>{
        'id': course.id,
        'title': course.title,
        'content': course.content,
        'cropType': course.cropType,
        'category': course.category,
        'readCount': reads,
      },
    );
  }

  void _toggleFavorite(BuildContext context, Course course) {
    final nowFavorite = ClassroomStore.instance.toggleFavorite(course.id);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(nowFavorite ? '已收藏' : '已取消收藏'),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final store = ClassroomStore.instance;

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final courses = store.favoriteCourses;
        if (courses.isEmpty) {
          return ForumEmptyState(
            icon: Icons.menu_book_outlined,
            text: '还没有收藏的课程',
            actionLabel: '去小课堂看看',
            onAction: () => context.push('/services/classroom'),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 88, left: 12, right: 12),
          itemCount: courses.length,
          itemBuilder: (context, index) {
            final course = courses[index];
            return CourseCard(
              course: course,
              readCount: store.readCount(course.id),
              favorited: true,
              onTap: () => _openCourse(context, course),
              onToggleFavorite: () => _toggleFavorite(context, course),
            );
          },
        );
      },
    );
  }
}
