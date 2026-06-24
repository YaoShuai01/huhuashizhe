import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/update_service.dart';
import '../../../providers/update_provider.dart';
import '../../../widgets/update_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const String AppVersion = '1.0.1';

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
                  const Text('v$AppVersion', style: TextStyle(color: AppColors.textHint, fontSize: 14)),
                  const SizedBox(height: 4),
                  const Text('智能植保无人机操控平台',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                ],
              ),
            ),
            const SizedBox(height: 32),
            const Divider(),
            ListTile(
              title: const Text('版本更新'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final notifier = ref.read(updateProvider.notifier);
                await notifier.checkForUpdate();
                if (context.mounted) {
                  final state = ref.read(updateProvider);
                  if (state.status == UpdateStatus.updateAvailable) {
                    UpdateDialog.show(context);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('当前已是最新版本')),
                    );
                  }
                }
              },
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