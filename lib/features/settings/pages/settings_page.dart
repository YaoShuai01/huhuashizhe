import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/local_database.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _darkMode = false;
  bool _notifications = true;
  bool _autoWeather = true;

  final _db = LocalDatabase();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() {
    setState(() {
      _darkMode = _db.getBool('dark_mode');
      _notifications = _db.getBool('notifications');
      _autoWeather = _db.getBool('auto_weather');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          _sectionHeader('显示'),
          SwitchListTile(
            title: const Text('深色模式'),
            subtitle: const Text('切换深色/浅色主题'),
            value: _darkMode,
            activeColor: AppColors.primary,
            onChanged: (v) => setState(() { _darkMode = v; _db.setBool('dark_mode', v); }),
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