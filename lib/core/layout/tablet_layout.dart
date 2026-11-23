import 'package:flutter/material.dart';

/// 平板布局判定。
///
/// 三个条件全部满足才启用，缺一不可：
/// 1. 用户在「设置 → 显示」里打开「平板布局」开关（缺省关闭）；
/// 2. 画面宽 > 高（比例超过 1:1），竖屏手机永远不触发；
/// 3. 最短边 >= 600，排除手机横屏（典型 780×360 也满足宽>高）。
class LayoutScope extends InheritedWidget {
  const LayoutScope({
    super.key,
    required this.enabled,
    required super.child,
  });

  /// 用户在设置页选择的开关状态。
  final bool enabled;

  static LayoutScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LayoutScope>();

  /// 当前是否应该使用平板布局。
  ///
  /// 没有 [LayoutScope]（例如测试里直接 pump 单个页面）时按「关闭」处理，
  /// 保持与手机布局一致，不会让存量测试意外切到侧边导航。
  static bool useTablet(BuildContext context) {
    final enabled = maybeOf(context)?.enabled ?? false;
    if (!enabled) return false;
    final size = MediaQuery.sizeOf(context);
    return size.width > size.height && size.shortestSide >= 600;
  }

  @override
  bool updateShouldNotify(LayoutScope oldWidget) => enabled != oldWidget.enabled;
}

/// 网格代理：手机固定两列，平板按 [maxCrossAxisExtent] 自动分列。
SliverGridDelegate adaptiveGridDelegate(
  BuildContext context, {
  required double childAspectRatio,
  double maxCrossAxisExtent = 420,
  double spacing = 12,
}) {
  if (LayoutScope.useTablet(context)) {
    return SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: maxCrossAxisExtent,
      childAspectRatio: childAspectRatio,
      mainAxisSpacing: spacing,
      crossAxisSpacing: spacing,
    );
  }
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 2,
    childAspectRatio: childAspectRatio,
    mainAxisSpacing: spacing,
    crossAxisSpacing: spacing,
  );
}

/// 平板布局下把正文限宽居中，避免一行拉得过长；手机布局原样返回。
class AdaptiveContent extends StatelessWidget {
  const AdaptiveContent({
    super.key,
    required this.child,
    this.maxWidth = 1000,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    if (!LayoutScope.useTablet(context)) return content;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: content,
      ),
    );
  }
}
