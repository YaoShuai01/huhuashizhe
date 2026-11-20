import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/accessibility/elder_care_reader.dart';
import '../../../core/theme/app_theme.dart';

/// 服务页：集中展示各类服务入口，目前包含小课堂
class ServicesPage extends StatelessWidget {
  const ServicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('服务')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const Text(
            '常用服务',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          _serviceCard(
            context,
            icon: Icons.school_outlined,
            title: '小课堂',
            desc: '内置植保知识库，涵盖油菜、水稻、小麦等作物的病虫害防治与作业技术',
            onTap: () => context.push('/services/classroom'),
          ),
          const SizedBox(height: 12),
          _serviceCard(
            context,
            icon: Icons.flight_takeoff,
            title: '预约飞防',
            desc: '在线预约专业飞手上门喷洒农药，按亩计价，飞手电话确认后作业',
            onTap: () => context.push('/services/booking'),
          ),
        ],
      ),
    );
  }

  Widget _serviceCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String desc,
    required VoidCallback onTap,
  }) {
    return ElderCareBlock(
      readText: '$title。$desc',
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 24, color: AppColors.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        desc,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: AppColors.textHint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
