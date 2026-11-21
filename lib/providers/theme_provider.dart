import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_database.dart';

/// 主题模式状态。
///
/// 两个开关映射成三态：
/// - 跟随系统 ON  → [ThemeMode.system]（深色模式开关置灰，由系统决定）
/// - 跟随系统 OFF → 深色模式开关决定 [ThemeMode.dark] / [ThemeMode.light]
///
/// 存储键在 [LocalDatabase] 里以 JSON 文件形式持久化：
/// - `follow_system`：缺省视为 true，保证老用户升级后行为不变（跟随系统）
/// - `dark_mode`：老版本就有的键，继续复用，不丢已有设置
class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const String followSystemKey = 'follow_system';
  static const String darkModeKey = 'dark_mode';

  final _db = LocalDatabase();

  @override
  ThemeMode build() {
    // get() 返回 null 表示键不存在（首次启动 / 老版本升级）
    final followRaw = _db.get(followSystemKey);
    final followSystem = followRaw == null
        ? true // 默认跟随系统，保持升级前后一致
        : _db.getBool(followSystemKey);

    if (followSystem) return ThemeMode.system;
    return _db.getBool(darkModeKey) ? ThemeMode.dark : ThemeMode.light;
  }

  /// 是否处于「跟随系统」状态。供设置页控制深色模式开关是否可点。
  bool get followSystem => _db.get(followSystemKey) == null
      ? true
      : _db.getBool(followSystemKey);

  /// 深色模式开关的当前值。跟随系统时返回系统当前是否为深色，
  /// 让开关显示与实际画面一致。
  bool isDarkActive(BuildContext context) {
    if (followSystem) {
      return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    }
    return _db.getBool(darkModeKey);
  }

  void setFollowSystem(bool value) {
    _db.setBool(followSystemKey, value);
    state = value
        ? ThemeMode.system
        : (_db.getBool(darkModeKey) ? ThemeMode.dark : ThemeMode.light);
  }

  void setDarkMode(bool value) {
    _db.setBool(darkModeKey, value);
    // 单独拨动深色模式时自动退出「跟随系统」，
    // 否则开关点了却没反应（正是本次要修的 bug）。
    _db.setBool(followSystemKey, false);
    state = value ? ThemeMode.dark : ThemeMode.light;
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);
