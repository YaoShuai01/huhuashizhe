import 'dart:async';

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
  Timer? _messageTimer;
  bool _messagePollingStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_messagePollingStarted) return;
    _messagePollingStarted = true;
    final repository = widget.repository ?? ForumScope.of(context);
    // 远端数据源开启消息轮询，让铃铛的未读数接近实时
    if (!repository.supportsRealtimeMessages) return;
    _refreshMessages(repository);
    _messageTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refreshMessages(repository),
    );
  }

  Future<void> _refreshMessages(ForumRepository repository) async {
    try {
      await repository.loadMessages();
    } on ForumException {
      // 轮询失败静默处理，下一轮会重试
    }
  }

  @override
  void dispose() {
    _messageTimer?.cancel();
    super.dispose();
  }

  /// 首页分区胶囊：推荐（精选聚合）+ 全部真实版块
  List<String> _feedTitles(ForumRepository repository) =>
      [forumRecommendedSection, ...repository.sectionTitles];

  /// 选中的小分区失效（数据源变化）时回退到第一个分区
  String? _resolveSection(ForumRepository repository) {
    final titles = _feedTitles(repository);
    if (titles.isEmpty) return null;
    if (_selectedSection != null && titles.contains(_selectedSection)) {
      return _selectedSection;
    }
    return titles.first;
  }

  /// 发帖版块：推荐是聚合分区，不能作为发帖版块
  String? _composeSection(ForumRepository repository) {
    final section = _resolveSection(repository);
    return section == forumRecommendedSection ? null : section;
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
            extra: _composeSection(repository),
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
                  titles: _feedTitles(repository),
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
    final isRecommended = section == forumRecommendedSection;
    if (posts.isEmpty) {
      return ForumEmptyState(
        icon: Icons.forum_outlined,
        text: isRecommended ? '还没有推荐内容' : '「$section」还没有帖子',
        actionLabel: '去发帖',
        onAction: () async {
          if (!await ensureForumLoggedIn(context)) return;
          if (!mounted) return;
          context.push(
            '/forum/compose',
            extra: isRecommended ? null : section,
          );
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
            _buildColumn(repository, left, showSection: isRecommended),
            const SizedBox(width: 10),
            // 右列整体下沉，与左列形成明显的错落感
            _buildColumn(
              repository,
              right,
              topOffset: 26,
              showSection: isRecommended,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColumn(
    ForumRepository repository,
    List<ForumPost> posts, {
    double topOffset = 0,
    bool showSection = false,
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
                  showSection: showSection,
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
            key: ValueKey('forum-section-$title'),
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
