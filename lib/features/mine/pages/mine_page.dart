import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/accessibility/elder_care_scope.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_version.dart' show appVersion;
import '../../auth/data/auth_api.dart';
import '../../auth/data/auth_session.dart';

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
                    backgroundImage: const AssetImage('assets/images/icom.png'),
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<AuthUser?>(
                    valueListenable: AuthSession.instance.user,
                    builder: (context, account, _) => Column(
                      children: [
                        Text(
                          account?.nickname ?? '未设置昵称',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                        ),
                        if (account != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            '登录号：${account.loginId}',
                            style: const TextStyle(fontSize: 13, color: AppColors.textHint),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => context.push('/mine/account'),
                    child: const Text('点击编辑资料', style: TextStyle(fontSize: 13, color: AppColors.textHint)),
                  ),
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
            _buildAuthMenuItem(context),
            _buildMenuItem(
              icon: Icons.bluetooth_outlined,
              title: '设备连接',
              subtitle: '扫描并连接无人机 WiFi 热点',
              onTap: () => context.push('/mine/device'),
            ),
            _buildMenuItem(
              icon: Icons.settings_outlined,
              title: '设置',
              subtitle: '语言、通知、缓存、深色模式',
              onTap: () => context.push('/mine/settings'),
            ),
            _buildElderCareSwitch(context),
            const SizedBox(height: 12),
            _buildMenuItem(
              icon: Icons.menu_book_outlined,
              title: '操作文档',
              subtitle: '内置用户手册、教学视频',
              onTap: () => context.push('/mine/manual'),
            ),
            _buildMenuItem(
              icon: Icons.article_outlined,
              title: '我的帖子',
              subtitle: '查看我在论坛发布的内容',
              onTap: () => context.push('/forum/my-posts'),
            ),
            _buildMenuItem(
              icon: Icons.bookmark_border,
              title: '我的收藏',
              subtitle: '收藏的帖子都在这里',
              onTap: () => context.push('/forum/favorites'),
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
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('退出登录'),
                        content: const Text('退出后将清除本地账户数据，确定要退出吗？'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              AuthSession.instance.signOut();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('已退出登录')),
                              );
                            },
                            child: const Text('确定', style: TextStyle(color: AppColors.error)),
                          ),
                        ],
                      ),
                    );
                  },
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

  /// 老年关怀模式开关：放大字体 + 长按板块文字朗读
  Widget _buildElderCareSwitch(BuildContext context) {
    final controller = ElderCareScope.of(context);
    return Container(
      color: AppColors.surface,
      child: SwitchListTile(
        secondary: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primaryLight.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.accessibility_new, color: AppColors.primary, size: 20),
        ),
        title: const Text(
          '老年关怀模式',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
        ),
        subtitle: const Text(
          '放大字体，长按板块文字即可朗读整块内容',
          style: TextStyle(fontSize: 12, color: AppColors.textHint),
        ),
        value: controller.enabled,
        activeColor: AppColors.primary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        onChanged: (value) {
          controller.setEnabled(value);
          if (value) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                const SnackBar(
                  content: Text('老年关怀模式已开启：长按板块文字即可朗读'),
                  duration: Duration(seconds: 2),
                ),
              );
          }
        },
      ),
    );
  }

  /// 登录入口：未登录显示「账号登录」，已登录显示「切换账号」
  Widget _buildAuthMenuItem(BuildContext context) {
    return ValueListenableBuilder<AuthUser?>(
      valueListenable: AuthSession.instance.user,
      builder: (context, account, _) => _buildMenuItem(
        icon: Icons.login,
        title: account == null ? '账号登录' : '切换账号',
        subtitle: account == null
            ? '登录号 + 密码登录'
            : '当前账号：${account.nickname}（${account.loginId}）',
        onTap: () async {
          final result = await context.push<AuthUser>('/login');
          if (result != null && context.mounted) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text('已登录：${result.nickname}')));
          }
        },
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