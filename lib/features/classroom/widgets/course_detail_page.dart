import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../data/classroom_store.dart';

class CourseDetailPage extends StatelessWidget {
  /// 课程稳定 id，用于收藏与阅读数；为空时收藏按钮不展示
  final String courseId;
  final String title;
  final String content;
  final String cropType;
  final String category;

  /// 进入本页时的阅读数（列表页已累加过一次）
  final int readCount;

  const CourseDetailPage({
    super.key,
    this.courseId = '',
    required this.title,
    required this.content,
    required this.cropType,
    required this.category,
    this.readCount = 0,
  });

  void _toggleFavorite(BuildContext context, ClassroomStore store) {
    final nowFavorite = store.toggleFavorite(courseId);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(nowFavorite ? '已收藏，可在「我的 - 我的收藏」查看' : '已取消收藏'),
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
        final canFavorite = courseId.isNotEmpty;
        final favorited = canFavorite && store.isFavorite(courseId);
        final reads = canFavorite && readCount == 0 ? store.readCount(courseId) : readCount;

        return Scaffold(
          appBar: AppBar(
            title: const Text('内容详情'),
            actions: [
              if (canFavorite)
                IconButton(
                  tooltip: favorited ? '取消收藏' : '收藏',
                  icon: Icon(favorited ? Icons.bookmark : Icons.bookmark_outline),
                  color: favorited ? AppColors.primary : AppColors.textOnPrimary,
                  onPressed: () => _toggleFavorite(context, store),
                ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Chip(
                      label: Text(cropType, style: const TextStyle(fontSize: 12)),
                      backgroundColor: AppColors.primaryLight.withValues(alpha: 0.15),
                      labelStyle: const TextStyle(color: AppColors.primary),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    const SizedBox(width: 8),
                    Chip(
                      label: Text(category, style: const TextStyle(fontSize: 12)),
                      backgroundColor: context.palette.surfaceVariant,
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, height: 1.4),
                ),
                if (reads > 0) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.visibility_outlined, size: 14, color: context.palette.textHint),
                      const SizedBox(width: 4),
                      Text('$reads 次阅读', style: TextStyle(fontSize: 12, color: context.palette.textHint)),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                Text(
                  content,
                  style: TextStyle(fontSize: 16, height: 1.8, color: context.palette.textSecondary),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
