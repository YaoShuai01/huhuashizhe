import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/update_service.dart';
import '../../../providers/update_provider.dart';
import '../../../widgets/update_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_version.dart' show appVersion;

// ========== 操作文档页 ==========
class ManualPage extends StatelessWidget {
  const ManualPage({super.key});

  @override
  Widget build(BuildContext context) {
    final manuals = [
      {'title': '快速入门指南', 'icon': Icons.rocket_launch, 'content': '1. 打开APP，确保蓝牙已开启\n2. 点击"设备连接"搜索并配对遥控器\n3. 在首页点击"创建飞行任务"\n4. 在地图上圈选作业区域\n5. 确认飞行参数后启动任务\n\n首次使用建议在空旷场地进行试飞，熟悉操作流程。'},
      {'title': '飞行参数设置说明', 'icon': Icons.settings, 'content': '飞行高度：建议1.5-3米，根据作物高度调整\n飞行速度：建议3-6米/秒，喷洒作业建议4米/秒\n行距：根据喷幅宽度设置，通常为喷幅的80%\n喷洒量：根据农药说明和作物类型设置\n\n以上参数可在AI助手中获取智能推荐。'},
      {'title': '安全操作规范', 'icon': Icons.security, 'content': '1. 作业前检查无人机电池、螺旋桨状态\n2. 远离高压线、人群、建筑物\n3. 风速超过5级禁止飞行\n4. 佩戴防护口罩和手套\n5. 作业区域设置警示标识\n6. 禁止在雨天或大雾天气作业\n7. 农药配制时远离水源\n8. 作业完成后及时清洗设备'},
      {'title': '农药使用指南', 'icon': Icons.science, 'content': '安全间隔期：\n- 水稻：不少于15天\n- 小麦：不少于20天\n- 蔬菜：不少于7-14天\n\n混用禁忌：\n- 酸性农药不能与碱性农药混用\n- 铜制剂与多数农药不能混用\n- 有机磷类与碱性农药不能混用\n\n药液配制：\n- 先加水再加药\n- 充分搅拌至完全溶解\n- 现配现用，不宜久置'},
      {'title': '设备维护保养', 'icon': Icons.build, 'content': '日常保养：\n- 每次作业后清洗喷洒系统\n- 检查螺旋桨有无裂纹变形\n- 清洁机身和传感器\n\n定期维护：\n- 每50小时检查电机轴承\n- 每100小时更换喷洒泵密封圈\n- 每季度校准GPS和流量计\n\n存储要求：\n- 电池存放在干燥阴凉处\n- 长期不用时电池保持50%电量\n- 机身存放在防尘防潮环境中'},
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('操作文档')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: manuals.length,
        itemBuilder: (context, index) {
          final m = manuals[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ExpansionTile(
              leading: Icon(m['icon'] as IconData, color: AppColors.primary),
              title: Text(m['title'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(m['content'] as String,
                    style: const TextStyle(fontSize: 14, height: 1.7, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ========== 功能介绍页 ==========
class FeatureIntroPage extends StatelessWidget {
  const FeatureIntroPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('功能介绍')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _featureCard('飞行任务', Icons.flight_takeoff, '创建植保作业任务，在地图上圈选作业区域，自动规划飞行路线，支持航点编辑和微调。'),
            _featureCard('AI助手', Icons.auto_awesome, '基于小米MiMo大模型的智能植保助手，提供病虫害诊断、用药推荐、飞行参数优化等专业建议。'),
            _featureCard('预设管理', Icons.bookmark, '保存常用作业参数为预设，一键调用。支持飞行高度、速度、喷洒量等参数的自定义配置。'),
            _featureCard('天气信息', Icons.cloud, '实时显示当前位置天气（数据来源：中国气象局），包括温度、风向、风速、湿度，支持风力预警。'),
            _featureCard('设备连接', Icons.bluetooth, '通过蓝牙连接无人机遥控器，实时查看设备状态、电量、信号强度等信息。'),
            _featureCard('小课堂', Icons.school, '内置植保知识库，涵盖水稻、小麦、玉米等多种作物的病虫害防治技术，持续更新中。'),
            _featureCard('作业记录', Icons.history, '查看历史作业详情，包括作业面积、飞行时长、用药量等统计信息。'),
            _featureCard('在线更新', Icons.system_update, '自动检测GitHub最新版本，支持在线下载和安装更新。'),
          ],
        ),
      ),
    );
  }

  Widget _featureCard(String title, IconData icon, String desc) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.primary, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(desc, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ========== 开源许可页 ==========
class OpenSourceLicensePage extends StatelessWidget {
  const OpenSourceLicensePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('开源许可')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _licenseItem('Flutter', 'BSD 3-Clause', 'Google'),
          _licenseItem('flutter_map', 'BSD 3-Clause', 'fleaflet'),
          _licenseItem('latlong2', 'MIT', 'johnpryan'),
          _licenseItem('go_router', 'BSD 3-Clause', 'Flutter'),
          _licenseItem('flutter_riverpod', 'MIT', 'Remi Rousselet'),
          _licenseItem('dio', 'MIT', 'cfug'),
          _licenseItem('path_provider', 'BSD 3-Clause', 'Flutter'),
          _licenseItem('proj4dart', 'MIT', 'maRci002'),
          _licenseItem('intl', 'BSD 3-Clause', 'Dart'),
          _licenseItem('小米MiMo大模型', '商用许可', '小米集团'),
          _licenseItem('中国天气网', '公共服务', '中国气象局'),
        ],
      ),
    );
  }

  Widget _licenseItem(String name, String license, String author) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(author, style: const TextStyle(fontSize: 13, color: AppColors.textHint)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primaryLight.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(license, style: const TextStyle(fontSize: 12, color: AppColors.primary)),
        ),
      ),
    );
  }
}

// ========== 法律文书详情页 ==========
class LegalDetailPage extends StatelessWidget {
  final String title;
  final String content;

  const LegalDetailPage({super.key, required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Text(
          content,
          style: const TextStyle(fontSize: 15, height: 1.8, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

// ========== 通知中心页 ==========
class NotificationPage extends StatelessWidget {
  const NotificationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('通知中心')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none, size: 80, color: AppColors.textDisabled.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            const Text('暂无通知', style: TextStyle(fontSize: 18, color: AppColors.textHint)),
            const SizedBox(height: 8),
            const Text('作业完成、天气预警等通知将显示在这里', style: TextStyle(fontSize: 14, color: AppColors.textDisabled)),
          ],
        ),
      ),
    );
  }
}

// ========== 作业记录页 ==========
class MissionHistoryPage extends StatelessWidget {
  const MissionHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('作业记录')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 80, color: AppColors.textDisabled.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            const Text('暂无作业记录', style: TextStyle(fontSize: 18, color: AppColors.textHint)),
            const SizedBox(height: 8),
            const Text('完成飞行任务后，作业记录将显示在这里', style: TextStyle(fontSize: 14, color: AppColors.textDisabled)),
          ],
        ),
      ),
    );
  }
}

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
              onTap: () => context.push('/mine/feature-intro'),
            ),
            ListTile(
              title: const Text('开源许可'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/mine/license'),
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
      {'q': '离线可以使用吗？', 'a': '地图圈选、预设管理、作业记录等核心功能支持离线使用。天气数据和AI助手需要网络连接。'},
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
            onTap: () => context.push('/mine/legal-detail', extra: {
              'title': '用户协议',
              'content': '护花使者用户协议\n\n'
                  '欢迎使用护花使者智能植保无人机操控平台。\n\n'
                  '一、服务说明\n'
                  '护花使者是一款专业的植保无人机操控APP，提供飞行任务规划、预设管理、病虫害防治知识库、AI智能建议等功能。\n\n'
                  '二、用户责任\n'
                  '1. 用户应确保无人机操作符合当地法律法规\n'
                  '2. 飞行作业前应取得必要的许可和资质\n'
                  '3. 用户对飞行作业的安全负全部责任\n'
                  '4. 不得在禁飞区、人群密集区进行飞行作业\n\n'
                  '三、免责声明\n'
                  '1. AI助手建议仅供参考，实际用药请以当地农技部门指导为准\n'
                  '2. 天气数据来源于中国气象局，可能存在延迟\n'
                  '3. 因操作不当造成的损失，本软件不承担责任\n\n'
                  '四、知识产权\n'
                  '护花使者及其相关知识产权归开发团队所有。\n\n'
                  '五、协议变更\n'
                  '我们保留随时修改本协议的权利，修改后的协议将在APP内公布。',
            }),
          ),
          const Divider(indent: 16),
          ListTile(
            title: const Text('隐私政策'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/mine/legal-detail', extra: {
              'title': '隐私政策',
              'content': '护花使者隐私政策\n\n'
                  '我们非常重视您的隐私保护。\n\n'
                  '一、信息收集\n'
                  '1. 位置信息：用于获取当地天气和地图定位\n'
                  '2. 蓝牙信息：用于连接无人机遥控器\n'
                  '3. 设备信息：APP版本、设备型号等基础信息\n\n'
                  '二、信息使用\n'
                  '1. 位置信息仅用于天气显示和地图服务\n'
                  '2. 所有数据存储在本地设备，不上传至服务器\n'
                  '3. AI对话记录仅保存在本地，不进行云端同步\n\n'
                  '三、信息保护\n'
                  '1. 卸载APP将清除所有本地数据\n'
                  '2. 我们不会向第三方分享您的个人信息\n\n'
                  '四、权限说明\n'
                  '1. 位置权限：用于GPS定位和天气获取\n'
                  '2. 蓝牙权限：用于设备连接\n'
                  '3. 存储权限：用于APK更新下载和本地数据存储',
            }),
          ),
          const Divider(indent: 16),
          ListTile(
            title: const Text('免责声明'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/mine/legal-detail', extra: {
              'title': '免责声明',
              'content': '护花使者免责声明\n\n'
                  '一、AI助手\n'
                  'AI植保助手提供的病虫害诊断、用药推荐等建议仅供参考，不构成专业的农业技术指导。实际用药请以当地农业技术推广部门的指导为准，严格遵守农药使用规范。\n\n'
                  '二、天气数据\n'
                  '天气信息来源于中国气象局公开数据，可能存在一定延迟或误差。在极端天气条件下，请以当地气象部门发布的预警信息为准。\n\n'
                  '三、飞行安全\n'
                  '1. 用户应确保无人机操作符合《无人驾驶航空器飞行管理暂行条例》等法律法规\n'
                  '2. 飞行作业前应对设备进行全面检查\n'
                  '3. 恶劣天气条件下应停止飞行作业\n'
                  '4. 操作人员应具备相应的操作技能和安全意识\n\n'
                  '四、数据安全\n'
                  '用户数据存储在本地设备中，卸载APP将导致数据丢失。建议用户定期备份重要数据。\n\n'
                  '五、责任限制\n'
                  '因使用本软件产生的任何直接或间接损失，在法律允许的范围内，本软件不承担责任。',
            }),
          ),
        ],
      ),
    );
  }
}

/// 显示状态提示弹窗（2秒后自动消失）
void _showStatusDialog(BuildContext context, IconData icon, String title, String message) {
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      Future.delayed(const Duration(seconds: 2), () {
        if (ctx.mounted) Navigator.of(ctx).pop();
      });
      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.primary, size: 28),
              ),
              const SizedBox(height: 12),
              Text(title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    },
  );
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
              _showStatusDialog(context, Icons.check_circle, '已是最新版本', '当前版本 v$appVersion，无需更新');
            } else if (state.status == UpdateStatus.noRelease) {
              _showStatusDialog(context, Icons.info_outline, '暂无更新', '暂未发布更新信息，请稍后再试');
            } else if (state.status == UpdateStatus.error) {
              _showStatusDialog(context, Icons.error_outline, '检查失败', state.errorMessage);
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
        'version': 'v1.3.0',
        'date': '2026-06-28',
        'content': [
          '首页"AI建议"更名为"AI助手"，统一全应用AI标识',
          'AI自动调参接入小米MiMo大模型，真正实现AI智能推荐飞行参数',
          '新增AiChatService.quickAnalysis通用分析方法，供各模块调用',
          'AI助手页面标题和欢迎语优化，统一品牌形象',
          'AI分析失败时自动回退到本地默认参数表，确保可用性',
        ],
      },
      {
        'version': 'v1.2.2',
        'date': '2026-06-28',
        'content': [
          '修复蓝牙设备列表名称溢出报错',
          '蓝牙未开启红色提示3秒后自动消失',
          '优化"已是最新版本"弹窗：改为美观对话框，2秒自动消失',
          '优化"暂无更新"和"检查失败"提示弹窗样式',
        ],
      },
      {
        'version': 'v1.2.1',
        'date': '2026-06-28',
        'content': [
          '修复蓝牙设备扫描：实现真实BLE+经典蓝牙双模扫描，替代原有模拟虚拟设备',
          '新增蓝牙权限动态申请（Android 12+ BLUETOOTH_SCAN/CONNECT）',
          '蓝牙扫描UI增强：信号强度可视化、设备类型标识、已配对状态显示',
          '扫描结果按信号强度排序，支持10秒超时自动停止',
        ],
      },
      {
        'version': 'v1.2.0',
        'date': '2026-06-27',
        'content': [
          '新增AI植保助手：接入小米MiMo大模型，支持病虫害诊断、用药推荐、飞行参数建议',
          'AI对话持久化存储，支持长期记忆的智能体',
          '补全所有预留板块：操作文档、功能介绍、开源许可、法律文书详情',
          '新增通知中心、作业记录页面',
          '修复所有空回调：首页快捷操作、关于页、法律页、退出登录等',
          '首页AI助手入口直达AI对话',
        ],
      },
      {
        'version': 'v1.1.13',
        'date': '2026-06-27',
        'content': [
          '修复天气API：切换到d1.weather.com.cn/sk_2d接口，支持全国所有城市',
          '修复Content-Type: text/html导致JSON解析失败',
          '天气数据包含：温度、天气描述、风向、风力、湿度、降水',
        ],
      },
      {
        'version': 'v1.1.12',
        'date': '2026-06-27',
        'content': [
          '修复安装器界面版本号显示为旧版问题（pubspec.yaml版本号不同步）',
          '修复天气卡片无法获取天气（Android 9+拦截HTTP明文流量）',
        ],
      },
      {
        'version': 'v1.1.11',
        'date': '2026-06-27',
        'content': [
          '天气数据源切换为中国天气网（中国气象局官方数据），与手机系统天气一致',
          '支持区/县级天气精度，自动匹配GPS定位城市',
          '完全免费、无限次数、无需API Key',
        ],
      },
      {
        'version': 'v1.1.10',
        'date': '2026-06-27',
        'content': [
          '优化GPS定位速度：有缓存位置时立即返回，无缓存时缩短等待时间',
          '下载完成后自动拉起系统安装器，无需手动点击安装',
          '启动白屏优化为闪屏页（Logo + 欢迎报考湖北职业技术学院）',
          '补全历史版本更新日志（v1.1.5 ~ v1.1.9）',
        ],
      },
      {
        'version': 'v1.1.9',
        'date': '2026-06-27',
        'content': [
          '新增GPS全局缓存，应用重启后复用上次定位位置',
          '使用加载动画替代上海硬编码初始位置，定位前显示加载状态',
        ],
      },
      {
        'version': 'v1.1.8',
        'date': '2026-06-27',
        'content': [
          '新增WGS-84/GCJ-02坐标转换，修复高德地图偏移问题',
          '完全删除上海硬编码坐标回退，无GPS时显示提示信息',
        ],
      },
      {
        'version': 'v1.1.7',
        'date': '2026-06-27',
        'content': [
          '优化GPS定位精度：优先等待高精度新定位，而非直接使用缓存位置',
          '定位成功前持续监听位置流，获取最高精度定位',
        ],
      },
      {
        'version': 'v1.1.6',
        'date': '2026-06-27',
        'content': [
          '修复天气卡片位置文本过长导致溢出问题',
          '优化地名显示样式，长文本自动截断处理',
        ],
      },
      {
        'version': 'v1.1.5',
        'date': '2026-06-27',
        'content': [
          '逆地理编码改用Android原生Geocoder，提升国内可用性',
          '新增天气API容错处理，请求失败不影响界面',
          '补全历史版本更新日志',
        ],
      },
      {
        'version': 'v1.1.4',
        'date': '2026-06-27',
        'content': [
          '修复天气卡片不显示问题（逆地理编码改为非阻塞后台执行，天气数据立即展示）',
          'GPS定位添加5秒超时保护，避免长时间阻塞',
          '应用启动时异步刷新天气，不阻塞UI渲染',
        ],
      },
      {
        'version': 'v1.1.3',
        'date': '2025-06-27',
        'content': [
          '新增天气卡片显示当前地名（逆地理编码，精确到镇/乡级）',
          '新增应用启动时自动刷新天气，无需手动下拉',
          '优化天气数据使用GPS定位坐标请求，替代硬编码的上海坐标',
          '天气卡片位置信息格式：当前位置  |  省 · 市 · 区 · 镇',
        ],
      },
      {
        'version': 'v1.1.2',
        'date': '2025-06-27',
        'content': [
          '修复创建飞行任务时地图初始化未完成导致的致命错误（通过_mapReady标记保护camera访问）',
        ],
      },
      {
        'version': 'v1.1.1',
        'date': '2025-06-27',
        'content': [
          '新增微调面板全宽重布局（方向键+步长控制，与航点编辑面板同宽）',
          '优化地图工具栏：仅保留十字靶标定位和图层切换按钮',
          '修复图层切换按钮触发时意外定位到用户位置的问题',
        ],
      },
      {
        'version': 'v1.0.12',
        'date': '2025-06-27',
        'content': [
          '新增GPS定位按钮（点击居中到用户当前位置）',
          '新增地图微调面板（方向键微调地图中心+步长调节）',
          '修复关于页版本号显示硬编码问题',
        ],
      },
      {
        'version': 'v1.0.11',
        'date': '2025-06-27',
        'content': [
          '修复图层切换耦合问题（解耦initialCenter与运行时定位）',
          '新增预设参数微调功能（从预设进入时支持参数调整）',
        ],
      },
      {
        'version': 'v1.0.10',
        'date': '2025-06-27',
        'content': [
          '修复卫星图切换无效问题',
          '修复初始显示标准地图而非卫星图的问题',
        ],
      },
      {
        'version': 'v1.0.9',
        'date': '2025-06-27',
        'content': [
          '修复APK安装器无法拉起系统安装界面（移除FLAG_ACTIVITY_NEW_TASK）',
          '修复地图工具栏按钮不可见（AppBar图标颜色与背景色相同导致）',
        ],
      },
      {
        'version': 'v1.0.8',
        'date': '2025-06-27',
        'content': [
          '修复APK安装失败（新增getDownloadDir方法，返回外部存储路径）',
          '修复「下次再说」关闭后弹窗绿色头部残留问题',
          '修复地图工具栏布局：按钮间距优化，新增地名开关',
          '修复应用更新后用户数据丢失（存储路径改为应用文档目录持久化）',
        ],
      },
      {
        'version': 'v1.0.7',
        'date': '2025-06-27',
        'content': [
          '修复APK安装失败（下载路径改为外部存储，系统安装器可正常访问）',
          '修复「下次再说」关闭后弹窗绿色头部残留问题',
          '修复地图工具栏布局：移除冗余定位图标，按钮间距优化，标题靠左',
          '修复应用更新后用户数据丢失（存储路径改为应用文档目录持久化）',
          '新增更新提醒弹窗（启动时自动检测GitHub新版本并弹出更新对话框）',
        ],
      },
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