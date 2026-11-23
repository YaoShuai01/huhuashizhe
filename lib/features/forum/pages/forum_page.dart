import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../data/forum_models.dart';
import '../data/forum_repository.dart';
import '../forum_login_guard.dart';
import '../forum_scope.dart';
import '../widgets/forum_empty_state.dart';
import '../widgets/forum_message_bell.dart';
import '../widgets/forum_post_card.dart';
import '../widgets/forum_responsive_body.dart';

class ForumPage extends StatefulWidget {
  const ForumPage({super.key, this.repository});

  /// 外部注入的数据源，为空时取 ForumScope 或默认实现
  final ForumRepository? repository;

  @override
  State<ForumPage> createState() => _ForumPageState();
}

class _ForumPageState extends State<ForumPage> {
  String? _selectedSection;

  /// 选中的小分区失效（数据源变化）时回退到第一个分区
  String? _resolveSection(ForumRepository repository) {
    final titles = repository.sectionTitles;
    if (titles.isEmpty) return null;
    if (_selectedSection != null && titles.contains(_selectedSection)) {
      return _selectedSection;
    }
    return titles.first;
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository ?? ForumScope.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('论坛'),
        actions: [
          AnimatedBuilder(
            animation: repository,
            builder: (context, _) {
              final unread =
                  repository.messages.where((message) => message.unread).length;
              return ForumMessageBell(
                unreadCount: unread,
                onTap: () => context.push('/forum/messages'),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          if (!await ensureForumLoggedIn(context) || !context.mounted) return;
          context.push(
            '/forum/compose',
            extra: _resolveSection(repository),
          );
        },
        icon: const Icon(Icons.edit_outlined),
        label: const Text('发帖'),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
      ),
      body: ForumResponsiveBody(
        child: AnimatedBuilder(
          animation: repository,
          builder: (context, _) {
            final section = _resolveSection(repository);
            return Column(
              children: [
                _SectionBar(
                  titles: repository.sectionTitles,
                  selected: section,
                  countOf: repository.countOf,
                  onSelected: (title) =>
                      setState(() => _selectedSection = title),
                ),
                Expanded(
                  child: section == null
                      ? const ForumEmptyState(
                          icon: Icons.forum_outlined,
                          text: '暂无可浏览的版块',
                        )
                      : _buildFeed(repository, section),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 帖子瀑布流：按奇偶分到左右两列，形成错开的双列布局
  Widget _buildFeed(ForumRepository repository, String section) {
    final posts = repository.postsOf(section);
    if (posts.isEmpty) {
      return ForumEmptyState(
        icon: Icons.forum_outlined,
        text: '「$section」还没有帖子',
        actionLabel: '去发帖',
        onAction: () async {
          if (!await ensureForumLoggedIn(context)) return;
          if (!mounted) return;
          context.push('/forum/compose', extra: section);
        },
      );
    }

    final left = <ForumPost>[];
    final right = <ForumPost>[];
    for (var i = 0; i < posts.length; i++) {
      (i.isEven ? left : right).add(posts[i]);
    }

    return RefreshIndicator(
      onRefresh: repository.refresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildColumn(repository, left),
            const SizedBox(width: 10),
            // 右列整体下沉，与左列形成明显的错落感
            _buildColumn(repository, right, topOffset: 26),
          ],
        ),
      ),
    );
  }

  Widget _buildColumn(
    ForumRepository repository,
    List<ForumPost> posts, {
    double topOffset = 0,
  }) {
    return Expanded(
      child: Padding(
        padding: EdgeInsets.only(top: topOffset),
        child: Column(
          children: [
            for (final post in posts)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ForumPostCard(
                  post: post,
                  margin: EdgeInsets.zero,
                  showSection: false,
                  onLike: () => repository.toggleLike(post),
                  liked: repository.isLiked(post),
                  favorited: repository.isFavorite(post),
                  onFavorite: () => repository.toggleFavorite(post),
                  onTap: () => context.push('/forum/post', extra: post),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 顶部小分区入口：横向滚动的一排胶囊按钮
class _SectionBar extends StatelessWidget {
  const _SectionBar({
    required this.titles,
    required this.selected,
    required this.countOf,
    required this.onSelected,
  });

  final List<String> titles;
  final String? selected;
  final int Function(String section) countOf;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: ListView.separated(
        key: const Key('forum-sections'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        itemCount: titles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final title = titles[index];
          final isSelected = title == selected;
          final count = countOf(title);
          return Material(
            color: isSelected ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => onSelected(title),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.surfaceVariant,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: isSelected
                            ? AppColors.textOnPrimary
                            : AppColors.textPrimary,
                      ),
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: 4),
                      Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 12,
                          color: isSelected
                              ? AppColors.textOnPrimary
                                  .withValues(alpha: 0.8)
                              : AppColors.textHint,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
