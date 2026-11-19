import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 论坛子页面统一的返回按钮
///
/// 栈内可直接返回上一页；若页面被外部直接打开（无上一页）则回退到论坛主页。
class ForumBackButton extends StatelessWidget {
  const ForumBackButton({super.key, this.fallbackLocation = '/forum'});

  /// 无上一页时的回退路由
  final String fallbackLocation;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '返回',
      icon: const Icon(Icons.arrow_back_ios_new, size: 20),
      onPressed: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(fallbackLocation);
        }
      },
    );
  }
}
