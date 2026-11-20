import 'package:flutter/foundation.dart';

import '../../data/local_database.dart';

/// 老年关怀模式控制器：开启后全局放大字体，并支持长按板块文字朗读
class ElderCareController extends ChangeNotifier {
  ElderCareController({bool? enabled})
      : _enabled = enabled ?? LocalDatabase().getBool(settingKey);

  /// 本地持久化键
  static const String settingKey = 'elder_care_mode';

  /// 开启后的字体放大倍数
  static const double textScaleFactor = 1.18;

  bool _enabled;

  bool get enabled => _enabled;

  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    LocalDatabase().setBool(settingKey, value);
    notifyListeners();
  }

  void toggle() => setEnabled(!_enabled);
}

/// 全局默认实例，应用启动时读取本地设置
final ElderCareController elderCareController = ElderCareController();
