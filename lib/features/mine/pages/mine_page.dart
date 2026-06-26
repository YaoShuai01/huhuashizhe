import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_version.dart' show appVersion;
import '../widgets/device_scan_page.dart';
import '../pages/mine_sub_pages.dart';
import '../../settings/pages/settings_page.dart';

class MinePage extends StatelessWidget {
  const MinePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              color: AppColors.surface,
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.white,
                    backgroundImage: const AssetImage('assets/images/logo.jpg'),
                  ),
                  const SizedBox(height: 12),
                  const Text('未设置昵称', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  const Text('点击编辑资料', style: TextStyle(fontSize: 13, color: AppColors.textHint)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildMenuItem(
              icon: Icons.account_circle_outlined,
              title: '我的账户',
              subtitle: '本地存储，卸载APP数据会丢失',
              onTap: () => context.push('/mine/account'),
            ),
            _buildMenuItem(
              icon: Icons.bluetooth_outlined,
              title: '设备连接',
              subtitle: '蓝牙设备管理、已配对设备列表',
              onTap: () => context.push('/mine/device'),
            ),
            _buildMenuItem(
              icon: Icons.settings_outlined,
              title: '设置',
              subtitle: '语言、通知、缓存、深色模式',
              onTap: () => context.push('/mine/settings'),
            ),
            const SizedBox(height: 12),
            _buildMenuItem(
              icon: Icons.menu_book_outlined,
              title: '操作文档',
              subtitle: '内置用户手册、教学视频',
              onTap: () {},
            ),
            _buildMenuItem(
              icon: Icons.description_outlined,
              title: '法律文书及用户条款',
              subtitle: '隐私政策、用户协议',
              onTap: () => context.push('/mine/legal'),
            ),
            const SizedBox(height: 12),
            _buildMenuItem(
              icon: Icons.help_outline,
              title: '帮助',
              subtitle: '常见问题FAQ',
              onTap: () => context.push('/mine/help'),
            ),
            _buildMenuItem(
              icon: Icons.feedback_outlined,
              title: '反馈',
              subtitle: '问题反馈、功能建议',
              onTap: () => context.push('/mine/feedback'),
            ),
            _buildMenuItem(
              icon: Icons.info_outline,
              title: '关于',
              subtitle: 'v$appVersion',
              onTap: () => context.push('/mine/about'),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('退出登录', style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      color: AppColors.surface,
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primaryLight.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.primary, size: 20),
        ),
        title: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textDisabled, size: 20),
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      ),
    );
  }
}