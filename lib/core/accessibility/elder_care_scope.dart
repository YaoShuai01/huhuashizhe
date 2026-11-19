import 'package:flutter/widgets.dart';

import 'elder_care_controller.dart';

/// 向整棵组件树提供老年关怀模式状态
class ElderCareScope extends InheritedNotifier<ElderCareController> {
  const ElderCareScope({
    super.key,
    required ElderCareController controller,
    required super.child,
  }) : super(notifier: controller);

  /// 订阅状态变化（开关切换后自动重建）
  static ElderCareController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ElderCareScope>()?.notifier ??
      elderCareController;

  /// 只读取，不建立依赖（适合点击回调中使用）
  static ElderCareController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ElderCareScope>()?.notifier ??
      elderCareController;
}
