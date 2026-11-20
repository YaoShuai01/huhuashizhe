import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../data/forum_models.dart';
import '../data/forum_repository.dart';
import '../forum_scope.dart';
import '../widgets/forum_category_card.dart';
import '../widgets/forum_empty_state.dart';
import '../widgets/forum_message_bell.dart';
import '../widgets/forum_responsive_body.dart';
import '../widgets/forum_section_tile.dart';

class ForumPage extends StatefulWidget {
  const ForumPage({super.key, this.repository});

  /// 外部注入的数据源，为空时取 ForumScope 或默认实现
  final ForumRepository? repository;

  @override
  State<ForumPage> createState() => _ForumPageState();
}

class _ForumPageState extends State<ForumPage> {
  String? _selectedCategory;

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
        onPressed: () => context.push('/forum/compose'),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('发帖'),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
      ),
      body: AnimatedBuilder(
        animation: repository,
        builder: (context, _) {
          final categories = repository.categories;
          final selected = _resolveSelectedCategory(categories);
          final sections =
              selected == null ? const [] : repository.sectionsOf(selected);

          return ForumResponsiveBody(
            padding: const EdgeInsets.only(top: 10, bottom: 88),
            child: RefreshIndicator(
              onRefresh: repository.refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  ForumCategoryCard(
                    categories: categories,
                    selected: selected ?? '',
                    onSelected: (name) =>
                        setState(() => _selectedCategory = name),
                  ),
                  const SizedBox(height: 4),
                  if (sections.isEmpty)
                    const SizedBox(
                      height: 280,
                      child: ForumEmptyState(
                        icon: Icons.forum_outlined,
                        text: '该分区暂无版块',
                      ),
                    )
                  else
                    for (final section in sections)
                      ForumSectionTile(
                        section: section,
                        postCount: repository.countOf(section.title),
                        onTap: () => context.push(
                          '/forum/section',
                          extra: section.title,
                        ),
                      ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 选中的分区失效（数据源变化）时回退到第一个分区
  String? _resolveSelectedCategory(List<ForumCategory> categories) {
    if (categories.isEmpty) return null;
    final matched = categories.where((c) => c.name == _selectedCategory);
    return matched.isNotEmpty ? matched.first.name : categories.first.name;
  }
}
