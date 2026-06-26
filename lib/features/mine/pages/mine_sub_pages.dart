import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/update_service.dart';
import '../../../providers/update_provider.dart';
import '../../../widgets/update_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_version.dart' show appVersion;

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _nicknameCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的账户')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 44,
                    backgroundColor: AppColors.primaryLight.withValues(alpha: 0.15),
                    child: const Icon(Icons.person, size: 48, color: AppColors.primary),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.edit, size: 16, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _nicknameCtrl,
              decoration: const InputDecoration(
                labelText: '昵称',
                hintText: '请输入昵称',
              ),
            ),
            const SizedBox(height: 24),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('数据说明', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    SizedBox(height: 8),
                    Text(
                      '当前版本所有数据存储在本地设备中。卸载APP将导致所有数据丢失，包括预设、作业记录、设备配对信息等。后续版本将支持云端备份功能。',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.6),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  if (_nicknameCtrl.text.trim().isNotEmpty) {
                    Navigator.pop(context);
                  }
                },
                child: const Text('保存'),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: null,
    );
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    super.dispose();
  }
}

class FeedbackPage extends StatelessWidget {
  const FeedbackPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('反馈')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: '请描述您遇到的问题或建议...',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.attach_file),
              label: const Text('上传截图（可选）'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('感谢您的反馈！')),
                  );
                  Navigator.pop(context);
                },
                child: const Text('提交反馈'),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 40),
            Center(
              child: Column(
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: AppColors.primaryLight, width: 2),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset('assets/images/logo.jpg', fit: BoxFit.cover),
                  ),
                  const SizedBox(height: 16),
                  const Text('护花使者', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('v$appVersion', style: TextStyle(color: AppColors.textHint, fontSize: 14)),
                  const SizedBox(height: 4),
                  const Text('智能植保无人机操控平台',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                ],
              ),
            ),
            const SizedBox(height: 32),
            const Divider(),
            ListTile(
              title: const Text('版本信息'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/mine/version'),
            ),
            ListTile(
              title: const Text('功能介绍'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
            ListTile(
              title: const Text('开源许可'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
            const Divider(),
            const SizedBox(height: 16),
            const Text('Copyright 2025 护花使者团队',
                style: TextStyle(color: AppColors.textHint, fontSize: 12)),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    final faqs = [
      {'q': '如何连接遥控器？', 'a': '打开遥控器电源，确保蓝牙可见。在APP中点击"设备连接"，选择发现的遥控器设备进行配对。'},
      {'q': '如何创建飞行任务？', 'a': '在首页点击"创建飞行任务"，在地图上圈选作业区域，AI将自动为您推荐最佳飞行参数。'},
      {'q': '作业区域面积太小怎么办？', 'a': '无人机的作业区域不能小于0.5亩。请扩大圈选范围或选择更大的作业区域。'},
      {'q': '离线可以使用吗？', 'a': '地图圈选、预设管理、作业记录等核心功能支持离线使用。天气数据和AI建议需要网络连接。'},
      {'q': '数据会丢失吗？', 'a': '当前版本数据存储在本地，卸载APP会导致数据丢失。后续版本将支持云端备份功能。'},
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('帮助')),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          ...faqs.map((faq) => Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: ExpansionTile(
                  title: Text(faq['q']!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Text(faq['a']!,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.6)),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class LegalPage extends StatelessWidget {
  const LegalPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('法律文书及用户条款')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('用户协议'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          const Divider(indent: 16),
          ListTile(
            title: const Text('隐私政策'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          const Divider(indent: 16),
          ListTile(
            title: const Text('免责声明'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

class VersionInfoPage extends ConsumerWidget {
  const VersionInfoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('版本信息')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCurrentVersionCard(),
            const SizedBox(height: 16),
            _buildCheckUpdateButton(context, ref),
            const SizedBox(height: 24),
            const Text('更新日志', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ..._buildUpdateHistory(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentVersionCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppColors.primary, AppColors.primaryLight]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Text('当前版本', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 8),
          Text('v$appVersion', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('智能植保无人机操控平台', style: TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildCheckUpdateButton(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () async {
          final notifier = ref.read(updateProvider.notifier);
          await notifier.checkForUpdate();
          if (context.mounted) {
            final state = ref.read(updateProvider);
            if (state.status == UpdateStatus.updateAvailable) {
              UpdateDialog.show(context);
            } else if (state.status == UpdateStatus.upToDate) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('当前已是最新版本')),
              );
            } else if (state.status == UpdateStatus.noRelease) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('暂无更新信息，请稍后再试')),
              );
            } else if (state.status == UpdateStatus.error) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.errorMessage)),
              );
            }
          }
        },
        icon: const Icon(Icons.sync),
        label: const Text('检查更新'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  List<Widget> _buildUpdateHistory() {
    final histories = [
      {
        'version': 'v1.0.6',
        'date': '2025-06-26',
        'content': [
          '新增图层切换按钮（卫星图/标准地图一键切换）',
          '新增地名标注开关（卫星图模式下单独控制地名显示）',
          '修复GPS定位不生效（不限缓存时间+被动定位回退）',
          '闭合区域检测改为像素重叠（十字准心与航点标记视觉重叠）',
        ],
      },
      {
        'version': 'v1.0.5',
        'date': '2025-06-25',
        'content': [
          '修复更新弹窗「下次再说」关闭后绿色头部残留',
          '地图切换为高德卫星图层（符合农业用途）',
          '地图新增缩放限制（3-18级），防止无限缩放导致空白',
          '新增GPS自动定位（进入地图自动获取手机位置）',
          '新增地图比例尺（左下角实时显示，随缩放级别变化）',
          '修复操作提示文字溢出容器（RIGHT OVERFLOWED）',
          '修复APK安装失败问题（增强安装器健壮性）',
          '新增应用从后台恢复时自动刷新更新检测',
        ],
      },
      {
        'version': 'v1.0.4',
        'date': '2025-06-24',
        'content': [
          '修复"下次再说"按钮点击后弹窗不关闭的问题',
          '修复地图空白问题（切换为高德地图瓦片源，国内可用）',
          '修复小课堂课程详情页点击报错（路由推送方式优化）',
        ],
      },
      {
        'version': 'v1.0.3',
        'date': '2025-06-24',
        'content': [
          '修复自动更新弹窗不显示的问题（使用根导航器context）',
          '修复下载后安装按钮无效（新增MethodChannel原生安装）',
          '仓库改为公开，GitHub Release API可正常访问',
        ],
      },
      {
        'version': 'v1.0.2',
        'date': '2025-06-24',
        'content': [
          '修复地图渲染空白问题，添加多瓦片源备用方案',
          '优化航点标记样式（半透明、无数字标识）',
          '子页面隐藏底部Tab栏导航',
          '新增「版本信息」页面（含更新日志列表）',
          '进入主页即时检测更新（去除3秒延迟）',
          '本地数据持久化存储（更新不丢失）',
        ],
      },
      {
        'version': 'v1.0.1',
        'date': '2025-06-24',
        'content': [
          '修复地图空白：十字准心移至Stack覆盖层',
          '航点标记优化：仅第一个航点显示标记',
          '子页面隐藏底部Tab栏：10个子页面路由外置',
          '新增在线更新功能（GitHub Release检测）',
          '精美卡片式更新弹窗（版本对比+进度条）',
        ],
      },
      {
        'version': 'v1.0.0',
        'date': '2025-06-23',
        'content': [
          '初始版本发布',
          '首页：天气信息、设备连接、快捷操作、任务统计',
          '预设管理：搜索、筛选、CRUD完整功能、AI标签',
          '小课堂：9大分类、6门内置课程、课程详情',
          '我的：账户、设备扫描、设置、帮助、关于等子页面',
          '飞行任务流程：地图选点→AI调优→任务确认→实时监控',
          '深色模式支持',
        ],
      },
    ];

    return histories.map((h) => _buildVersionItem(h)).toList();
  }

  Widget _buildVersionItem(Map<String, dynamic> item) {
    final isExpanded = ValueNotifier<bool>(false);
    return ValueListenableBuilder<bool>(
      valueListenable: isExpanded,
      builder: (context, expanded, _) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.surfaceVariant),
          ),
          child: Column(
            children: [
              InkWell(
                onTap: () => isExpanded.value = !isExpanded.value,
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(item['version'], style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(item['date'], style: const TextStyle(color: AppColors.textHint, fontSize: 13))),
                      Icon(expanded ? Icons.expand_less : Icons.expand_more, color: AppColors.textHint, size: 20),
                    ],
                  ),
                ),
              ),
              if (expanded) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: (item['content'] as List).map((c) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• ', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                          Expanded(child: Text(c, style: const TextStyle(fontSize: 13, height: 1.5))),
                        ],
                      ),
                    )).toList(),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}