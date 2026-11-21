import 'package:flutter/material.dart';

/// 论坛页面的自适应容器：
/// - 宽度上限 [maxWidth]，平板/横屏下居中，避免内容被拉得过宽
/// - 限制文字缩放上限，防止超大字号导致布局溢出
class ForumResponsiveBody extends StatelessWidget {
  const ForumResponsiveBody({
    super.key,
    required this.child,
    this.maxWidth = 640,
    this.padding = EdgeInsets.zero,
    this.maxTextScaleFactor = 1.6,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  final double maxTextScaleFactor;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        textScaler: media.textScaler.clamp(
          minScaleFactor: 1,
          maxScaleFactor: maxTextScaleFactor,
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
