import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/local_database.dart';
import '../../../providers/theme_provider.dart';
import '../../../services/drone_udp_service.dart';
import '../../../services/voice_service.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _notifications = true;
  bool _autoWeather = true;
  bool _voicePrompt = true;
  bool _aiVoiceReply = true;

  final _db = LocalDatabase();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() {
    setState(() {
      _notifications = _db.getBool('notifications');
      _autoWeather = _db.getBool('auto_weather');
      // 语音播报首次使用默认开启
      _voicePrompt = _db.get(VoiceService.settingKey) == null
          ? true
          : _db.getBool(VoiceService.settingKey);
      _aiVoiceReply = _db.get(VoiceService.aiReplySettingKey) == null
          ? true
          : _db.getBool(VoiceService.aiReplySettingKey);
    });
  }

  Future<void> _clearDroneTrim() async {
    final svc = DroneUdpService();
    final ok = await svc.clearTrim();
    svc.dispose();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '已清除无人机微调数据' : '清除失败：请先连接无人机 WiFi'),
        backgroundColor: ok ? null : AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          _sectionHeader('无人机'),
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Text('清除无人机微调数据'),
            subtitle: const Text('把飞控中保存的前后/左右/旋转微调归零（需连接无人机 WiFi）'),
            onTap: _clearDroneTrim,
          ),
          const Divider(indent: 16, endIndent: 16),
          _sectionHeader('显示'),
          SwitchListTile(
            title: const Text('跟随系统'),
            subtitle: const Text('主题始终跟随系统深/浅色设置'),
            value: ref.watch(themeModeProvider) == ThemeMode.system,
            activeColor: AppColors.primary,
            onChanged: (v) =>
                ref.read(themeModeProvider.notifier).setFollowSystem(v),
          ),
          SwitchListTile(
            title: const Text('深色模式'),
            subtitle: Text(
              ref.watch(themeModeProvider) == ThemeMode.system
                  ? '由系统控制，关闭「跟随系统」后可手动切换'
                  : '当前为手动模式，切换深色/浅色主题',
            ),
            // 跟随系统时开关置灰：显示系统当前状态，且不可点，
            // 保证「一直跟随系统」的语义不被绕过。
            value: ref.watch(themeModeProvider) == ThemeMode.dark ||
                (ref.watch(themeModeProvider) == ThemeMode.system &&
                    MediaQuery.platformBrightnessOf(context) ==
                        Brightness.dark),
            activeColor: AppColors.primary,
            onChanged: ref.watch(themeModeProvider) == ThemeMode.system
                ? null
                : (v) => ref.read(themeModeProvider.notifier).setDarkMode(v),
          ),
          const Divider(indent: 16, endIndent: 16),
          _sectionHeader('功能'),
          SwitchListTile(
            title: const Text('推送通知'),
            subtitle: const Text('作业完成、天气预警提醒'),
            value: _notifications,
            activeColor: AppColors.primary,
            onChanged: (v) => setState(() { _notifications = v; _db.setBool('notifications', v); }),
          ),
          SwitchListTile(
            title: const Text('自动获取天气'),
            subtitle: const Text('开启后自动获取当前位置天气'),
            value: _autoWeather,
            activeColor: AppColors.primary,
            onChanged: (v) => setState(() { _autoWeather = v; _db.setBool('auto_weather', v); }),
          ),
          SwitchListTile(
            title: const Text('语音播报'),
            subtitle: const Text('识别结果、作业告警与操作提示的语音播报'),
            value: _voicePrompt,
            activeColor: AppColors.primary,
            onChanged: (v) {
              setState(() => _voicePrompt = v);
              VoiceService.instance.setEnabled(v);
            },
          ),
          SwitchListTile(
            title: const Text('朗读AI回复'),
            subtitle: const Text('AI助手回复完成后自动朗读（超长内容提示查看屏幕）'),
            value: _aiVoiceReply,
            activeColor: AppColors.primary,
            onChanged: _voicePrompt
                ? (v) => setState(() {
                      _aiVoiceReply = v;
                      _db.setBool(VoiceService.aiReplySettingKey, v);
                    })
                : null,
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
    );
  }
}