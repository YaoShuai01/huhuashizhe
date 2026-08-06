import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../data_module_config.dart';
import 'data_list_page.dart';

/// 数据管理中心主页 - PC端11个数据管理模块入口
class DataCenterPage extends StatelessWidget {
  const DataCenterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('数据管理中心'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部说明
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.storage, color: Colors.white, size: 28),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('植保数据管理', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
                        SizedBox(height: 4),
                        Text('管理油菜植保无人机作业的全部数据', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 模块分类
            _buildSectionTitle('基础数据'),
            const SizedBox(height: 8),
            _buildModuleGrid(context, DataModules.allModules.sublist(0, 3)),
            const SizedBox(height: 20),
            _buildSectionTitle('监测数据'),
            const SizedBox(height: 8),
            _buildModuleGrid(context, DataModules.allModules.sublist(3, 5)),
            const SizedBox(height: 20),
            _buildSectionTitle('作业数据'),
            const SizedBox(height: 8),
            _buildModuleGrid(context, DataModules.allModules.sublist(5, 8)),
            const SizedBox(height: 20),
            _buildSectionTitle('配置与记录'),
            const SizedBox(height: 8),
            _buildModuleGrid(context, DataModules.allModules.sublist(8, 11)),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildModuleGrid(BuildContext context, List<DataModuleConfig> modules) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.95,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: modules.length,
      itemBuilder: (context, index) {
        final module = modules[index];
        return _buildModuleCard(context, module);
      },
    );
  }

  Widget _buildModuleCard(BuildContext context, DataModuleConfig module) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(
              builder: (_) => DataListPage(config: module),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: module.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(module.icon, color: module.color, size: 28),
              ),
              const SizedBox(height: 12),
              Text(
                module.moduleName,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}