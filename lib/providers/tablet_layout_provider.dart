import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_database.dart';

/// 「平板布局」开关，缺省关闭。
///
/// 开关只代表用户意愿；真正是否启用平板布局还要看屏幕：
/// 宽 > 高且最短边 >= 600，见 `core/layout/tablet_layout.dart`。
class TabletLayoutNotifier extends Notifier<bool> {
  static const String key = 'tablet_layout_enabled';

  final _db = LocalDatabase();

  @override
  bool build() => _db.getBool(key);

  void setEnabled(bool value) {
    _db.setBool(key, value);
    state = value;
  }
}

final tabletLayoutEnabledProvider =
    NotifierProvider<TabletLayoutNotifier, bool>(TabletLayoutNotifier.new);
