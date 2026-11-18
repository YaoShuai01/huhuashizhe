import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/forum_models.dart';
import 'forum_category_chip.dart';

/// 「所有分区」卡片：分区数量任意、宽度自适应换行
class ForumCategoryCard extends StatelessWidget {
  const ForumCategoryCard({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelected,
    this.title = '所有分区',
  });

  final List<ForumCategory> categories;
  final String selected;
  final ValueChanged<String> onSelected;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (categories.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '暂无分区',
                  style: TextStyle(fontSize: 13, color: AppColors.textHint),
                ),
              )
            else
              Wrap(
                alignment: WrapAlignment.spaceEvenly,
                spacing: 4,
                runSpacing: 8,
                children: [
                  for (final category in categories)
                    ForumCategoryChip(
                      category: category,
                      selected: category.name == selected,
                      onTap: () => onSelected(category.name),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
