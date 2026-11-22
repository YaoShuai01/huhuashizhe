import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/update_service.dart';
import '../../../providers/update_provider.dart';
import '../../../widgets/update_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_version.dart' show appVersion;
import '../../forum/data/forum_models.dart';
import '../../forum/data/forum_repository.dart';
import '../../forum/forum_scope.dart';

// ========== 操作文档页 ==========
class ManualPage extends StatelessWidget {
  const ManualPage({super.key});

  @override
  Widget build(BuildContext context) {
    final manuals = [
      {'title': '快速入门指南', 'icon': Icons.rocket_launch, 'content': '1. 打开APP，确保 WiFi 已开启\n2. 点击"设备连接"扫描并连接 HuHuaShiZhe-Drone 热点\n3. 在首页点击"创建飞行任务"\n4. 在地图上圈选作业区域\n5. 确认飞行参数后启动任务\n\n首次使用建议在空旷场地进行试飞，熟悉操作流程。'},
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
                    style:  TextStyle(fontSize: 14, height: 1.7, color: context.palette.textSecondary),
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
            _featureCard(context, '飞行任务', Icons.flight_takeoff, '创建植保作业任务，在地图上圈选作业区域，自动规划飞行路线，支持航点编辑和微调。'),
            _featureCard(context, 'AI助手', Icons.auto_awesome, '基于千问AI大模型的智能植保助手，提供病虫害诊断、用药推荐、飞行参数优化等专业建议。'),
            _featureCard(context, '预设管理', Icons.bookmark, '保存常用作业参数为预设，一键调用。支持飞行高度、速度、喷洒量等参数的自定义配置。'),
            _featureCard(context, '天气信息', Icons.cloud, '实时显示当前位置天气（数据来源：中国气象局），包括温度、风向、风速、湿度，支持风力预警。'),
            _featureCard(context, '设备连接', Icons.wifi, '扫描周边 WiFi 并连接无人机热点，实时查看连接状态与信号强度。'),
            _featureCard(context, '小课堂', Icons.school, '内置植保知识库，涵盖水稻、小麦、玉米等多种作物的病虫害防治技术，持续更新中。'),
            _featureCard(context, '作业记录', Icons.history, '查看历史作业详情，包括作业面积、飞行时长、用药量等统计信息。'),
            _featureCard(context, '在线更新', Icons.system_update, '自动检测自有服务器最新版本，支持在线下载和安装更新。'),
          ],
        ),
      ),
    );
  }

  Widget _featureCard(BuildContext context, String title, IconData icon, String desc) {
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
                  Text(desc, style:  TextStyle(color: context.palette.textSecondary, fontSize: 14, height: 1.5)),
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
          _licenseItem(context, 'Flutter', 'BSD 3-Clause', 'Google'),
          _licenseItem(context, 'flutter_map', 'BSD 3-Clause', 'fleaflet'),
          _licenseItem(context, 'latlong2', 'MIT', 'johnpryan'),
          _licenseItem(context, 'go_router', 'BSD 3-Clause', 'Flutter'),
          _licenseItem(context, 'flutter_riverpod', 'MIT', 'Remi Rousselet'),
          _licenseItem(context, 'dio', 'MIT', 'cfug'),
          _licenseItem(context, 'path_provider', 'BSD 3-Clause', 'Flutter'),
          _licenseItem(context, 'proj4dart', 'MIT', 'maRci002'),
          _licenseItem(context, 'intl', 'BSD 3-Clause', 'Dart'),
          _licenseItem(context, '千问AI大模型', '商用许可', '千问AI平台'),
          _licenseItem(context, '中国天气网', '公共服务', '中国气象局'),
        ],
      ),
    );
  }

  Widget _licenseItem(BuildContext context, String name, String license, String author) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(author, style:  TextStyle(fontSize: 13, color: context.palette.textHint)),
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
          style:  TextStyle(fontSize: 15, height: 1.8, color: context.palette.textSecondary),
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
            Icon(Icons.notifications_none, size: 80, color: context.palette.textDisabled.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
             Text('暂无通知', style: TextStyle(fontSize: 18, color: context.palette.textHint)),
            const SizedBox(height: 8),
             Text('作业完成、天气预警等通知将显示在这里', style: TextStyle(fontSize: 14, color: context.palette.textDisabled)),
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
            Icon(Icons.history, size: 80, color: context.palette.textDisabled.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
             Text('暂无作业记录', style: TextStyle(fontSize: 18, color: context.palette.textHint)),
            const SizedBox(height: 8),
             Text('完成飞行任务后，作业记录将显示在这里', style: TextStyle(fontSize: 14, color: context.palette.textDisabled)),
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
             Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('数据说明', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    SizedBox(height: 8),
                    Text(
                      '当前版本所有数据存储在本地设备中。卸载APP将导致所有数据丢失，包括预设、作业记录、设备配对信息等。后续版本将支持云端备份功能。',
                      style: TextStyle(color: context.palette.textSecondary, fontSize: 14, height: 1.6),
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

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key, this.repository});

  /// 外部注入的论坛数据源，为空时取 ForumScope 或默认实现
  final ForumRepository? repository;

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  /// 与论坛「管理区 - 意见反馈」共用同一个版块
  static const String _section = '意见反馈';

  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  ForumRepository get _repository =>
      widget.repository ?? ForumScope.of(context);

  void _submit() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('请填写反馈内容')));
      return;
    }
    final summary = text.length > 20 ? '${text.substring(0, 20)}…' : text;
    _repository.publish(
      section: _section,
      title: '意见反馈：$summary',
      content: text,
    );
    _ctrl.clear();
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('已提交，可在论坛「管理区 - 意见反馈」查看'),
          action: SnackBarAction(
            label: '去查看',
            onPressed: () =>
                context.push('/forum/section', extra: _section),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final repository = _repository;
    return Scaffold(
      appBar: AppBar(title: Text('反馈')),
      body: AnimatedBuilder(
        animation: repository,
        builder: (context, _) {
          final records = repository.myPosts
              .where((post) => post.section == _section)
              .toList();
          return ListView(
            padding: EdgeInsets.all(16),
            children: [
              TextField(
                controller: _ctrl,
                maxLines: 6,
                decoration: InputDecoration(
                  hintText: '请描述您遇到的问题或建议...',
                  alignLabelWithHint: true,
                ),
              ),
              SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {},
                icon: Icon(Icons.attach_file),
                label: Text('上传截图（可选）'),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              SizedBox(height: 8),
              Text(
                '提交后会同步到论坛「管理区 - 意见反馈」，管理员回复后可在下方查看。',
                style: TextStyle(fontSize: 12, color: context.palette.textHint),
              ),
              SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submit,
                  child: Text('提交反馈'),
                ),
              ),
              SizedBox(height: 24),
              Text(
                '我的反馈记录 ${records.length} 条',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.palette.textPrimary,
                ),
              ),
              SizedBox(height: 8),
              if (records.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      '还没有提交过反馈',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.palette.textHint,
                      ),
                    ),
                  ),
                )
              else
                for (final post in records)
                  _recordTile(repository, post),
              SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }

  Widget _recordTile(ForumRepository repository, ForumPost post) {
    final replyCount = repository.commentsOf(post.id).length;
    final String status;
    if (post.pendingReview) {
      status = '待复审';
    } else if (replyCount > 0) {
      status = '已回复 $replyCount';
    } else {
      status = '待回复';
    }
    final replied = replyCount > 0;
    return Card(
      margin: EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/forum/post', extra: post),
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      post.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: context.palette.textPrimary,
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: (replied ? AppColors.primary : AppColors.accent)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: replied ? AppColors.primary : AppColors.accent,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 6),
              Text(
                forumTimeText(post.createdAt),
                style: TextStyle(
                  fontSize: 11,
                  color: context.palette.textHint,
                ),
              ),
            ],
          ),
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
                    child: Image.asset('assets/images/icom.png', fit: BoxFit.cover),
                  ),
                  const SizedBox(height: 16),
                  const Text('护花使者', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                   Text('v$appVersion', style: TextStyle(color: context.palette.textHint, fontSize: 14)),
                  const SizedBox(height: 4),
                   Text('智能植保无人机操控平台',
                      style: TextStyle(color: context.palette.textSecondary, fontSize: 14)),
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
             Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                '本应用地图数据来源于国内互联网地图服务，版权归相应服务提供方所有，仅用于非商业教学演示用途。',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.palette.textHint, fontSize: 12, height: 1.5),
              ),
            ),
            const SizedBox(height: 8),
             Text('Copyright 2025 护花使者团队',
                style: TextStyle(color: context.palette.textHint, fontSize: 12)),
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
      {'q': '如何连接无人机？', 'a': '给无人机上电后会建立 HuHuaShiZhe-Drone WiFi 热点。在APP中点击"设备连接"，选择该热点后按系统提示连接，返回APP即可看到已连接状态。'},
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
                          style:  TextStyle(color: context.palette.textSecondary, fontSize: 14, height: 1.6)),
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
                  '2. WiFi 信息：用于扫描并连接无人机热点\n'
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
                  '2. WiFi 与定位权限：用于扫描周边 WiFi 网络\n'
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
                style:  TextStyle(fontSize: 13, color: context.palette.textSecondary),
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
    final updateState = ref.watch(updateProvider);
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
            // 后台下载进度条（选择"后台更新"后显示在这里）
            if (updateState.status == UpdateStatus.downloading)
              _buildBackgroundDownloadCard(context, updateState),
            if (updateState.status == UpdateStatus.downloaded)
              _buildBackgroundDownloadCard(context, updateState),
            if (updateState.status == UpdateStatus.error &&
                updateState.background)
              _buildBackgroundDownloadCard(context, updateState),
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

  /// 后台更新下载状态卡片（进度 / 完成 / 失败）
  Widget _buildBackgroundDownloadCard(BuildContext context, UpdateState state) {
    final info = state.updateInfo;
    final downloading = state.status == UpdateStatus.downloading;
    final failed = state.status == UpdateStatus.error;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: failed
              ? AppColors.error.withValues(alpha: 0.4)
              : AppColors.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                failed
                    ? Icons.error_outline
                    : downloading
                        ? Icons.cloud_download_outlined
                        : Icons.check_circle_outline,
                size: 18,
                color: failed ? AppColors.error : AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  failed
                      ? '更新下载失败'
                      : downloading
                          ? '正在后台下载 v${info?.versionName ?? ''}...'
                          : 'v${info?.versionName ?? ''} 下载完成，正在安装...',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              if (downloading)
                Text(
                  '${(state.progress * 100).toInt()}%',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          if (downloading) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: state.progress,
                minHeight: 6,
                backgroundColor: context.palette.surfaceVariant,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
          ],
          if (failed) ...[
            const SizedBox(height: 8),
            Text(
              state.errorMessage,
              style:  TextStyle(fontSize: 12, color: context.palette.textHint),
            ),
          ],
        ],
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
        'version': 'v3.10.5',
        'date': '2026-11-22',
        'content': [
          '云种植气候卡：积温改为「≥10℃年积温」，单位统一为 ℃·d',
          '新增积温说明：全年日均气温≥10℃ 的累加值，非实时温度',
          '注明气候数据为所在气候区的多年平均值，便于正确理解',
        ],
      },
      {
        'version': 'v3.10.4',
        'date': '2026-11-22',
        'content': [
          '账号登录默认直连公网服务器（Tomcat /forum 反向代理），任意网络均可登录',
          '无需再与电脑处于同一 Wi-Fi；本地联调仍可用 --dart-define 覆盖地址',
          '公网接口已实测：帖子列表 200、登录号鉴权 401 正常',
        ],
      },
      {
        'version': 'v3.10.3',
        'date': '2026-11-22',
        'content': [
          '云田地图新增道路/地名注记层，与卫星图叠加显示',
          '新建田块支持按住边界顶点拖动微调，面积周长实时更新',
          '云田详情支持实景照片与生长阶段叠加查看',
          '补齐 WGS-84 → GCJ-02 坐标转换，定位与地图标记更准确',
        ],
      },
      {
        'version': 'v3.10.2',
        'date': '2026-11-22',
        'content': [
          '云种植界面按网页最终版对齐：天气卡、田块地图、向导指引、定位面板全面升级',
          '地图支持自动框选全部田块、缩放比例尺，选中田块高亮、其余虚线边界',
          '新增手动选择城市获取天气，定位面板与田块列表交互与网页版一致',
        ],
      },
      {
        'version': 'v3.10.1',
        'date': '2026-11-22',
        'content': [
          '账号登录改为「系统生成登录号」：注册后自动分配 8 位登录号，昵称仅用于展示',
          '注册成功弹窗醒目展示登录号，「我的」页与账号入口同步显示登录号',
          '登录页适配跨平台后端地址，连不上服务时提示具体地址',
          '后端增加 CORS 支持，补充已有库升级脚本（001_add_login_id.sql）',
        ],
      },
      {
        'version': 'v3.10.0',
        'date': '2026-11-22',
        'content': [
          '云种植接入真实定位：GPS 定位 + 逆地理地名，定位失败可手动修改',
          '云种植接入中国天气网实况与 4 日预报，墒情与灌溉建议改用真实天气',
          '种植向导升级为 4 步，云田详情新增生长时间轴，与网页版对齐',
          '云田详情支持拍照/相册添加实景图，照片保存在本机文档目录',
        ],
      },
      {
        'version': 'v3.9.0',
        'date': '2026-11-22',
        'content': [
          '新增账号登录：昵称 + 密码注册/登录，登录态保存在本机，重启自动恢复',
          '「我的」页新增账号入口，显示当前昵称，支持切换账号与退出登录',
          '新增 Node/SQLite 账号后端（server/），密码使用 scrypt 加盐哈希存储',
          '修复本地数据库在初始化前调用 remove() 可能导致的空指针异常',
        ],
      },
      {
        'version': 'v3.8.1',
        'date': '2026-11-22',
        'content': [
          '田哨农场：提前收获确认弹窗按钮改为同行并排并放大，窄屏不折行',
          '收获（成熟/提前/全部）新增金色奖励弹窗，金币大字与随机祝福语',
          '金币图标由 🪙 改为 💰，兼容老设备避免显示方框',
        ],
      },
      {
        'version': 'v3.8.0',
        'date': '2026-11-22',
        'content': [
          '新增云种植模块：田块创建、种植向导、云田详情、远程控制、预警与 AI 农事助手',
          '首页新增云种植入口卡，底部导航保持不变',
          '云种植数据保存在本机，支持地块、种植记录与待办管理',
        ],
      },
      {
        'version': 'v3.7.1',
        'date': '2026-11-21',
        'content': [
          '田哨农场手机端优化：窄屏适配、作物/操作按钮网格排版、触摸目标加大',
          '限制农场页面缩放，去掉点按高亮，修复水滴动画类名冲突',
          '首页宫格新增田哨农场直达入口',
        ],
      },
      {
        'version': 'v3.7.0',
        'date': '2026-11-21',
        'content': [
          '新增田哨预警：寒潮/病虫害提醒、田块登记与云端田哨同步',
          '新增田哨农场游戏，首页「田哨预警」可进入',
          '预警卡/田块卡支持一键预约飞防，自动预填作物、亩数、地点',
          '田哨页补齐深色模式配色',
          '修复论坛评论发送需要重复点击的问题，发送中显示加载状态',
        ],
      },
      {
        'version': 'v3.6.0',
        'date': '2026-11-21',
        'content': [
          '底部导航「服务」改为「社区」，论坛入口调整到社区页内',
          '飞防预约新增接单前确认、5 秒倒计时、12 小时后取消收费规则',
          '新增飞手资料页、接单状态保留与其他作物自定义',
          '服务模块页面补齐深色模式配色',
        ],
      },
      {
        'version': 'v3.5.0',
        'date': '2026-11-21',
        'content': [
          '新增「服务」页：小课堂、预约飞防、论坛入口集中展示',
          '新增无人机飞防预约：农户端按亩计价、飞手端接单工作台',
          '论坛点赞状态按用户记录：未点赞白空心、点赞后琥珀橙',
          '反馈与论坛「管理区 - 意见反馈」互通，可查看回复',
          '服务模块页面的深色模式适配将在后续版本继续完善',
        ],
      },
      {
        'version': 'v3.4.5',
        'date': '2026-11-21',
        'content': [
          '修复设置页「深色模式」开关不生效的问题',
          '新增「跟随系统」开关：开启时主题跟随系统，关闭后可手动切换深色/浅色',
          '深色模式下卡片、文字、对话框、闪屏全面适配，不再出现白卡片或黑字看不清',
          '遥控器与 GPS 测速页保持设计上的固定深色，不受主题切换影响',
        ],
      },
      {
        'version': 'v3.4.4',
        'date': '2026-11-20',
        'content': [
          '遥控器微调面板新增「旋转（航向）」微调，可修正缓慢自转，每步 0.5°/s，范围 ±10°/s',
          '飞控固件同步支持航向微调，参数永久保存，重启后仍生效',
          '微调面板改为前后/左右/旋转三列布局，横屏与小屏均完整显示',
          '设置页「清除无人机微调数据」同步清零旋转微调',
        ],
      },
      {
        'version': 'v3.4.3',
        'date': '2026-11-20',
        'content': [
          '修复遥控器「微调」面板在横屏/小屏下被裁切的问题，改为全高可滚动布局，加减按钮加大更好点按',
          '恢复老年关怀模式：全局字号放大，长按板块即可朗读全软件文字',
          '论坛新增 AI 内容初审（违规驳回/待人工复审）、评论表情包、消息铃铛未读角标',
          '修复论坛点赞数越点越少的问题',
          '应用更新只走自有服务器，不再检查或下载 GitHub Release',
        ],
      },
      {
        'version': 'v3.4.2',
        'date': '2026-11-20',
        'content': [
          '遥控器新增「微调」面板：支持前后、左右微调，微调数据永久保存在无人机',
          '遥控器新增陀螺仪校准按钮，静止时一键归零陀螺零偏',
          '设置页新增「清除无人机微调数据」，一键恢复出厂微调',
          '模型热更新改由自有阿里云服务器分发，下载更快更稳定',
          '修复飞控定时器驱动冲突导致的启动异常',
        ],
      },
      {
        'version': 'v3.3.1',
        'date': '2026-11-19',
        'content': [
          '更新检查与安装包下载切换到自有阿里云服务器，不再依赖 GitHub',
          '论坛发帖与评论支持系统语音输入，自动申请麦克风权限',
          '论坛新增帖子详情页：查看评论、收藏帖子与消息分类',
          '论坛新增返回按钮与下拉刷新，切换标签页时保持浏览位置',
        ],
      },
      {
        'version': 'v3.3.0',
        'date': '2026-11-19',
        'content': [
          '论坛发帖与评论支持系统语音输入，自动申请麦克风权限',
          '论坛新增帖子详情页：查看评论、收藏帖子与消息分类',
          '论坛新增返回按钮与下拉刷新，切换标签页时保持浏览位置',
        ],
      },
      {
        'version': 'v3.1.1',
        'date': '2026-11-19',
        'content': [
          'AI 助手服务由小米 MiMo 切换为千问AI平台，修复余额不足导致 AI 无法回复的问题',
          '默认模型调整为 qwen3.8-flash 并关闭思考模式，回复更快、调用成本更低',
          '关于页 AI 助手说明与第三方许可信息同步更新',
        ],
      },
      {
        'version': 'v3.1.0',
        'date': '2026-11-19',
        'content': [
          '新增白菜病虫害四分类识别模型：菜青虫、霜霉病、白菜螟、健康',
          '模型支持 448×448 输入并内置在 App 中，断网也能在模型测试页选择使用',
        ],
      },
      {
        'version': 'v3.0.0',
        'date': '2026-11-18',
        'content': [
          '全新论坛模块：分区浏览、发帖、评论回复与消息通知，底部导航新增“论坛”入口',
          '新增北斗/GPS 卫星地图与搜星罗盘：实时卫星方位、仰角、信噪比，支持卫星影像与精度圈',
          '新增离线语音播报：飞机连接、病虫害识别、作业告警与 AI 回复均可朗读，可在设置中开关',
          '全局深色科技风与横屏体验优化，修复搜星页返回后变竖屏的问题',
          '轮协成员在线状态：已验证成员显示“在线/离线”，从未使用过的成员显示“未验证”',
          '遥控器底部按钮新增语音反馈：解锁/上锁、急停、喷洒与力度切换均可播报',
          '新增“起飞”按钮，起飞后自动播报当前高度、气温、北斗卫星状态与遥测状态',
          '底部状态框缩短，中间新增飞行高度、气温、湿度与北斗卫星实时遥测条',
        ],
      },
      {
        'version': 'v2.11.2',
        'date': '2026-11-18',
        'content': [
          '搜星页保留深色科技风底色，不再跟随系统浅色模式变白',
          '修复从搜星页返回遥控器后被系统转成竖屏的问题，返回后保持横屏',
        ],
      },
      {
        'version': 'v2.11.1',
        'date': '2026-11-18',
        'content': [
          '修正连接播报：仅在手机真正连接无人机 WiFi 时播报“飞机连接成功”',
          '北斗/GPS 搜星页接入手机 GNSS 实时数据：逐星方位、仰角、信噪比与搜到/使用数量实时刷新',
          '卫星罗盘改为默认视图，并跟随手机朝向旋转，始终指北',
          '“北斗卫星 / GPS”切换后，罗盘卫星与左右数量同步切换',
          '搜星页新增返回按钮、搜星动画，并统一为 App 的森林绿/琥珀橙科技风格',
        ],
      },
      {
        'version': 'v2.11.0',
        'date': '2026-11-18',
        'content': [
          '新增北斗/GPS 卫星地图与罗盘页：卫星影像地图、当前位置与精度圈、方位刻度与卫星数显示',
          '快速遥控页左上角新增“北斗/GPS”入口，返回后自动恢复横屏',
          '新增本地离线语音播报：飞机连接、病虫害识别、作业告警与 AI 回复均可朗读',
          '设置页新增“语音播报 / 朗读AI回复”开关，断网时自动回退手机本地语音引擎',
        ],
      },
      {
        'version': 'v2.10.0',
        'date': '2026-11-18',
        'content': [
          '轮协成员新增在线状态：已验证成员显示“在线/离线”，从未使用过的成员显示“未验证”',
          '成员验证由服务端自动记录：输入姓名验证成功后立即生效，无需管理员手动标记',
          'App 前台每 2 分钟自动上报在线心跳，在线状态实时同步给所有成员',
        ],
      },
      {
        'version': 'v2.9.9',
        'date': '2026-11-17',
        'content': [
          '轮协日历中已过日期统一显示为浅灰色',
          '自己的历史协管记录灰度稍深一点，便于和其他已过日期区分',
          '成员列表新增“未验证”标识，管理员可点验证图标标记；标记后标识消失并随轮协表同步',
        ],
      },
      {
        'version': 'v2.9.8',
        'date': '2026-11-17',
        'content': [
          '轮协管理恢复“对调轮协”：点击日期后，在弹窗里选择要对调的日期',
          '当前日期之前的轮协记录全部只读，不能单日修改、顺延覆盖或删除成员',
        ],
      },
      {
        'version': 'v2.9.7',
        'date': '2026-11-17',
        'content': [
          '恢复“轮协管理”功能：数据管理页入口、轮协表、编辑、消息与本地提醒',
          '恢复轮协密钥门禁、成员身份、静默同步与协管变更通知',
          '补齐 flutter_local_notifications / timezone / flutter_secure_storage 依赖与原生通知权限',
        ],
      },
      {
        'version': 'v2.9.6',
        'date': '2026-11-17',
        'content': [
          '修复覆盖安装时系统提示“无法降级安装”的问题（构建号提升至 100）',
          '版本号统一为 2.9.6，后续构建号在此基础上递增',
        ],
      },
      {
        'version': 'v2.9.5',
        'date': '2026-11-17',
        'content': [
          '首页“连接设备”由蓝牙扫描改为 WiFi 扫描，自动识别并置顶无人机热点 HuHuaShiZhe-Drone',
          '连接状态与任务监控改为显示 WiFi 名称与信号强度，下拉即可刷新',
          '支持一键跳转系统 WiFi 设置，返回后自动检测并刷新连接状态',
          '适配 Android 13+ 附近 WiFi 权限，扫描结果实时刷新',
          '修复模型标签测试中番茄健康索引错误',
        ],
      },
      {
        'version': 'v2.8.0',
        'date': '2026-11-15',
        'content': [
          '遥控页重构：竖向油门力度滑杆（0~100% 精细控制），偏航独立为只左右、松手回中的摇杆',
          '去掉一键起飞/降落，改为“解锁 + 手动油门 + 急停”；油门拉到底只停电机、保持解锁',
          '飞控固件改为油门直通（0→1000us，100→2000us），取消自动起飞/自动上锁',
          '飞控默认速率调柔：最大倾角 25°、偏航 150°/s、横滚俯仰 250°/s，加法 Expo 与偏航力矩缩放，满舵不再停电机',
          '开启 Air Mode，低油门保持姿态控制权',
          '飞控新增手机网页姿态/电机测试页：电池供电时浏览器打开 192.168.4.1 可看实时姿态、单独测电机',
          '飞控内核切换为 esp-fc（Betaflight 风格）：MPU6050 SDA41/SCL42，500Hz 陀螺 / 250Hz PID，支持 Betaflight Configurator 调参',
        ],
      },
      {
        'version': 'v2.7.7',
        'date': '2026-11-11',
        'content': [
          '修复高清档大面积花屏：固件分段偏移量整数溢出，超65KB的数据重复发送了文件开头',
          '新增FEC前向纠错：每8个分段配1个校验段，丢1个分段也能自动还原整帧，有效帧率大幅提升',
          '画面翻转改由摄像头执行，拍照结果与图传画面方向保持一致（切换分辨率后也不再丢失）',
          '配合飞控热点升级至40MHz带宽（HT40），图传转发吞吐翻倍',
        ],
      },
      {
        'version': 'v2.7.6',
        'date': '2026-11-11',
        'content': [
          '图传性能大改：视觉板 PSRAM 由 40MHz 提升至 80MHz，JPEG 编码与帧缓冲带宽翻倍',
          '采集与发送拆分为双核流水线，不再串行等待，实际帧率显著提升',
          '摄像头 XCLK 提至 24MHz，WiFi 发送缓冲与 AMPDU 窗口加大',
          '画面新增水平翻转、垂直翻转按钮，左上角实时显示帧率与码率',
          '画面解码改为按显示尺寸降采样，降低手机 CPU 占用，提升可渲染帧率',
          '画质档位调整：流畅 XGA 25fps / 均衡 720p 15fps / 高清 1600x1200 8fps',
        ],
      },
      {
        'version': 'v2.7.5',
        'date': '2026-11-11',
        'content': [
          '图传画质大幅提升：默认由 XGA 提升至 720p，新增流畅/均衡/高清三档画质切换',
          '修复实际帧率远低于设定值：收包循环改为单次事件读空缓冲区，避免高码率下分段丢失导致整帧被弃',
          '高清档 1600x1200，用于病虫害识别细节观察；需要五百万像素细节请用右下角拍照按钮抓单帧',
        ],
      },
      {
        'version': 'v2.7.4',
        'date': '2026-11-11',
        'content': [
          '修复更新弹窗叠加：切后台/下拉控制中心再回来不再重复弹窗，点一次即可关闭',
          '更新下载支持断点续传：断网/中断后从已完成进度接着下，不再从头来；半包按版本管理自动清理',
          '图传诊断增强：连接后仍无画面时显示明确的验证指引',
        ],
      },
      {
        'version': 'v2.7.3',
        'date': '2026-11-11',
        'content': [
          '修复画面不出帧：探测改用无副作用的VINFO，锁定地址后仅启动一次推流，不再反复重配摄像头',
          '连接后状态栏显示视觉板IP，链路状态更直观',
        ],
      },
      {
        'version': 'v2.7.2',
        'date': '2026-11-11',
        'content': [
          '修复遥控页收不到画面：图传命令改为对飞控子网逐一单播探测，自动锁定视觉板地址（softAP不保证转发广播）',
          '画面区实时显示视觉板应答状态，链路通不通一目了然',
          '断流自动重连：画面中断9秒后自动重新搜索视觉板',
        ],
      },
      {
        'version': 'v2.7.1',
        'date': '2026-11-10',
        'content': [
          '图传画面直接嵌入遥控器中央画面区，无需再跳转独立页面，支持暂停/恢复与高清拍照',
          '修复看不到画面的问题：图传命令改为UDP广播，不再依赖视觉板固定IP',
          '「后台更新」按钮移至下载进度界面：更新慢时可随时切后台，快则不用点',
          '更新下载提速：多通道并行竞速，自动选用响应最快的服务器下载',
        ],
      },
      {
        'version': 'v2.7.0',
        'date': '2026-11-10',
        'content': [
          '新增无人机图传：遥控页左上角新增「图传」入口，实时显示视觉板画面（XGA）',
          '支持一键高清拍照，照片自动保存到手机相册',
          '画面帧率实时显示，UDP分段重组协议抗丢包',
        ],
      },
      {
        'version': 'v2.6.0',
        'date': '2026-11-09',
        'content': [
          '应用更新新增「后台更新」：下载期间可正常使用APP，进度显示在版本信息页，完成后仍自动弹窗安装',
          '新增模型热更新：新训练的模型静默发布后，APP联网即自动下载，模型下拉列表自动出现新模型，无需更新APP',
        ],
      },
      {
        'version': 'v2.5.2',
        'date': '2026-11-09',
        'content': [
          '更换农作物病虫害识别模型：改用训练 100 轮的新模型，识别准确率提升',
          '模型输入分辨率由 224 提升至 320，叶片细节识别更准',
          '同步重排 39 个病虫害类别标签顺序，与新模型输出严格对应',
        ],
      },
      {
        'version': 'v2.5.1',
        'date': '2026-11-09',
        'content': [
          '修复应用内更新一直提示下载失败：新增3个下载加速通道自动切换，直连被墙时自动走镜像',
          '下载失败时清理残留半包文件，避免安装损坏的安装包',
          '更新包下载只识别 .apk 资源，避免误选其他附件',
        ],
      },
      {
        'version': 'v2.5.0',
        'date': '2026-11-09',
        'content': [
          '新增多模型支持：模型测试页顶部下拉选择识别模型（当前内置农作物病虫害识别）',
          '推理引擎支持动态切换模型，切换自动重启引擎并记忆上次选择',
          '后续新模型（人物识别、人脸识别等）发布后在下拉列表即可选择使用',
        ],
      },
      {
        'version': 'v2.4.5',
        'date': '2026-11-07',
        'content': [
          '修复AI对话中出现*号等Markdown标记：病虫害AI建议/追问、首页AI助手全链路清理',
          '系统提示词要求模型输出纯文本，历史已入库的带*记录在显示时自动清理',
        ],
      },
      {
        'version': 'v2.4.4',
        'date': '2026-11-07',
        'content': [
          '病虫害详情页布局调整：预警描述→采集图片→AI处理建议（AI建议放最后完整展示）',
        ],
      },
      {
        'version': 'v2.4.3',
        'date': '2026-11-07',
        'content': [
          '紧急修复：v2.4.2推理引擎迁移引入的bug导致开启摄像头后完全不识别',
          '版本信息页更新日志补全v2.4.0~v2.4.2',
        ],
      },
      {
        'version': 'v2.4.2',
        'date': '2026-11-07',
        'content': [
          '修复首页天气卡下雨图标误显示为雪云图标，并补充阵雪天气码识别',
          '首页AI助手回复改为逐句流式输出，与病虫害AI追问体验一致',
          '摄像头性能优化：推理引擎迁移至后台常驻isolate，修复开启摄像头后周期性卡顿',
          '病虫害记录详情页AI处理建议卡片提前展示且不再截断，视觉层级增强',
        ],
      },
      {
        'version': 'v2.4.1',
        'date': '2026-11-07',
        'content': [
          '修复退出模型测试时识别数据不同步到病虫害记录的bug',
          '移除独立「生长检测」模块，记录统一放入病虫害记录模块',
          'AI助手恢复可用：切换为mimo-v2.6-flash模型（v2.5已下线）',
        ],
      },
      {
        'version': 'v2.4.0',
        'date': '2026-11-06',
        'content': [
          '首页新增「模型测试」板块：竖屏实时识别+画面标注',
          '命中问题类自动采集加密图像入库，预警列表与详情卡片浏览',
          '退出自动同步到数据管理页病虫害记录，支持AI处理建议与追问',
          '自研.ys加密图片存储，仅应用内可读，点下载才导出系统相册',
        ],
      },
      {
        'version': 'v2.3.5',
        'date': '2026-11-03',
        'content': [
          '关于页新增地图数据版权与用途声明，规范非商业教学演示使用边界',
        ],
      },
      {
        'version': 'v2.3.4',
        'date': '2026-09-24',
        'content': [
          '紧急修复：v2.3.3因构建时漏打包原生代码(MainActivity.kt)导致启动闪退，本次重新完整构建',
        ],
      },
      {
        'version': 'v2.3.3',
        'date': '2026-09-24',
        'content': [
          '紧急修复：v2.3.2安装包因构建路径问题缺失渲染资源，导致图标不显示、定位失效，改用纯英文真实路径重新构建',
        ],
      },
      {
        'version': 'v2.3.2',
        'date': '2026-09-24',
        'content': [
          '启用全新品牌Logo：应用内（闪屏页、我的页、关于页）统一更换为新Logo',
          '全平台应用启动图标统一更换（Android/iOS/Web/Windows/macOS）',
          '闪屏页文字更换为「护花使者团队」',
        ],
      },
      {
        'version': 'v2.3.1',
        'date': '2026-09-14',
        'content': [
          '修复喷洒力度列表在横屏下显示不完整的问题，6挡位可全部呈现，超出一屏可滑动选择',
          '焊接图纸系统总线连接图优化：补全端子连接点与跨线标识',
        ],
      },
      {
        'version': 'v2.3.0',
        'date': '2026-09-14',
        'content': [
          '新增喷洒力度控制：6挡可选（45%~100%），喷洒中可实时切换力度',
          '遥控器界面喷洒按钮旁新增「力度」按钮，上拉列表选择挡位',
          'ESP32固件支持水泵PWM挡位调速，1~6挡对应45%~100%占空比',
        ],
      },
      {
        'version': 'v2.2.1',
        'date': '2026-08-11',
        'content': [
          '修复APP版本号与GitHub Release不一致导致的重复更新提示',
        ],
      },
      {
        'version': 'v2.2.0',
        'date': '2026-08-07',
        'content': [
          '无人机遥控优化：矢量混控+飞行状态机+一键起降+摇杆修复',
        ],
      },
      {
        'version': 'v2.1.2',
        'date': '2026-08-07',
        'content': [
          '修复遥控器横屏布局：强制横屏+移除AppBar+优化摇杆尺寸+设置/退出图标悬浮左上角',
        ],
      },
      {
        'version': 'v2.1.1',
        'date': '2026-08-06',
        'content': [
          '遥控器横屏布局优化：居中摄像头+两侧摇杆+设置/退出图标',
        ],
      },
      {
        'version': 'v2.1.0',
        'date': '2026-08-06',
        'content': [
          '新增WiFi虚拟遥控器（UDP 50Hz）：虚拟摇杆+解锁/喷洒/一键起降+飞行状态显示',
        ],
      },
      {
        'version': 'v2.0.1',
        'date': '2026-08-05',
        'content': [
          '修复历史遗留问题，稳定数据管理与预设功能',
        ],
      },
      {
        'version': 'v2.0.0',
        'date': '2026-08-05',
        'content': [
          '重大更新：全新数据管理中心，底部导航重组，全项目深化油菜主题',
        ],
      },
      {
        'version': 'v1.5.5',
        'date': '2026-07-07',
        'content': [
          '数据管理卡片简化：去描述+垂直布局+防换行',
        ],
      },
      {
        'version': 'v1.5.4',
        'date': '2026-07-07',
        'content': [
          '数据管理卡片优化：改2列布局+增描述文字',
        ],
      },
      {
        'version': 'v1.5.3',
        'date': '2026-07-07',
        'content': [
          '三项UI修复：数据管理子页隐藏底部栏、药量小数位、AI回答去星号',
        ],
      },
      {
        'version': 'v1.5.2',
        'date': '2026-07-07',
        'content': [
          '修复数据管理和预设页面返回逻辑',
        ],
      },
      {
        'version': 'v1.5.1',
        'date': '2026-07-07',
        'content': [
          'UI重组：数据管理中心升为底部导航，全项目深化油菜主题',
        ],
      },
      {
        'version': 'v1.4.3',
        'date': '2026-07-06',
        'content': [
          '修复系统大字体下功能卡片溢出报错',
          '全局限制字体缩放最大1.2倍，兼顾可读性与布局稳定性',
        ],
      },
      {
        'version': 'v1.4.2',
        'date': '2026-07-06',
        'content': [
          '修复构建环境导致图标和布局丢失的问题',
          '重新全量构建APK确保所有资源完整打包',
        ],
      },
      {
        'version': 'v1.4.1',
        'date': '2026-06-28',
        'content': [
          '修复AI助手全部用户无法使用的问题（API模型已升级）',
          'AI模型从 mimo-v2-flash 升级至 mimo-v2.5',
          '兼容推理模型 reasoning_content 响应字段',
          '非流式和流式API均支持新模型格式',
          '移除无效的 extra_body thinking 参数',
        ],
      },
      {
        'version': 'v1.4.0',
        'date': '2026-06-27',
        'content': [
          '修复GPS定位不实时更新：移除Android层30秒缓存快速返回，总是等待实时GPS定位',
          'Dart层GPS缓存添加3分钟过期机制，过期后自动重新获取位置',
          '修复版本号倒退问题（v1.1.9→v1.4.1，延续v1.4.0序列）',
        ],
      },
      {
        'version': 'v1.4.0',
        'date': '2026-06-28',
        'content': [
          '新增北斗+GPS双轨高精定位系统，实时监测卫星状态',
          '修复定位缓存过期问题：缓存超30秒自动重新定位',
          '定位精度优化：GPS<30米或网络<50米即返回，8秒超时兜底',
          '新增GNSS卫星信息监控：区分北斗/GPS/GLONASS/Galileo',
          '定位结果返回精度、来源、时间戳和卫星数据',
          'GpsLocationService重构为GpsLocation对象，接口更清晰',
        ],
      },
      {
        'version': 'v1.3.2',
        'date': '2026-06-28',
        'content': [
          'AI助手打开后自动滚动到最新消息，无需手动翻页',
          '每条消息下新增复制按钮和重新回答按钮（AI回复）',
          'AI助手自动获取用户当前位置和天气信息，回答更精准',
          '修复聊天记录历史加载后显示在顶部的问题',
          '重新回答功能自动继承天气上下文信息',
        ],
      },
      {
        'version': 'v1.3.1',
        'date': '2026-06-28',
        'content': [
          '修复AI聊天记录重启APP后丢失的问题',
          'AI助手消息气泡支持长按复制全部内容',
          '消息内容文字支持选中拖拽复制（SelectableText）',
        ],
      },
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
            color: context.palette.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.palette.surfaceVariant),
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
                      Expanded(child: Text(item['date'], style:  TextStyle(color: context.palette.textHint, fontSize: 13))),
                      Icon(expanded ? Icons.expand_less : Icons.expand_more, color: context.palette.textHint, size: 20),
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
