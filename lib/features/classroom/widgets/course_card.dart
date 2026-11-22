import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/classroom_courses.dart';

/// 小课堂课程卡片：列表页与「我的收藏 - 课程」共用
class CourseCard extends StatelessWidget {
  const CourseCard({
    super.key,
    required this.course,
    required this.readCount,
    required this.favorited,
    required this.onTap,
    this.onToggleFavorite,
  });

  final Course course;
  final int readCount;
  final bool favorited;
  final VoidCallback onTap;

  /// 为空时不展示收藏按钮
  final VoidCallback? onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Chip(
                    label: Text(course.cropType, style: const TextStyle(fontSize: 11)),
                    backgroundColor: AppColors.primaryLight.withValues(alpha: 0.1),
                    labelStyle: const TextStyle(color: AppColors.primary),
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 8),
                  Chip(
                    label: Text(course.category, style: const TextStyle(fontSize: 11)),
                    backgroundColor: context.palette.surfaceVariant,
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                course.title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.4),
              ),
              const SizedBox(height: 8),
              Text(
                course.content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.palette.textSecondary, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.visibility_outlined, size: 14, color: context.palette.textHint),
                  const SizedBox(width: 4),
                  Text('$readCount 次阅读', style: TextStyle(fontSize: 12, color: context.palette.textHint)),
                  const Spacer(),
                  if (onToggleFavorite != null)
                    Tooltip(
                      message: favorited ? '取消收藏' : '收藏',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: onToggleFavorite,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Icon(
                            favorited ? Icons.bookmark : Icons.bookmark_border,
                            size: 18,
                            color: favorited ? AppColors.primary : context.palette.textHint,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
