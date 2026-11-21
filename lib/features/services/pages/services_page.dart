import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/accessibility/elder_care_reader.dart';
import '../../../core/theme/app_theme.dart';

/// 服务页：集中展示各类服务入口（小课堂、预约飞防、论坛）
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
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.82,
            children: [
              _serviceCard(
                context,
                icon: Icons.school_outlined,
                color: AppColors.primary,
                title: '小课堂',
                desc: '内置植保知识库，涵盖油菜、水稻、小麦等作物的病虫害防治与作业技术',
                onTap: () => context.push('/services/classroom'),
              ),
              _serviceCard(
                context,
                icon: Icons.flight_takeoff,
                color: AppColors.accent,
                title: '预约飞防',
                desc: '在线预约专业飞手上门喷洒农药，按亩计价，飞手电话确认后作业',
                onTap: () => context.push('/services/booking'),
              ),
              _serviceCard(
                context,
                icon: Icons.forum_outlined,
                color: AppColors.info,
                title: '论坛',
                desc: '农友交流区、问答区与管理区，发布帖子、评论互动与私信提醒',
                onTap: () => context.push('/forum'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _serviceCard(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String desc,
    required VoidCallback onTap,
  }) {
    return ElderCareBlock(
      readText: '$title。$desc',
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 与数据管理模块卡片一致的方块图标
                Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(icon, size: 34, color: color),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Flexible(
                  child: Text(
                    desc,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
