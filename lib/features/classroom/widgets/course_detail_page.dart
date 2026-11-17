import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class CourseDetailPage extends StatelessWidget {
  final String title;
  final String content;
  final String cropType;
  final String category;

  const CourseDetailPage({
    super.key,
    required this.title,
    required this.content,
    required this.cropType,
    required this.category,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('内容详情'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmark_outline),
            onPressed: () {},
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
                  backgroundColor: AppColors.surfaceVariant,
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
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            Text(
              content,
              style: const TextStyle(fontSize: 16, height: 1.8, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}