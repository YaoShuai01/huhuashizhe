import 'package:flutter/widgets.dart';

import 'data/forum_repository.dart';

/// 论坛数据源注入入口。
///
/// 在页面树外层包裹 [ForumScope] 即可把论坛数据与交互替换为外部实现
/// （后端接口、本地数据库、测试假数据等）：
///
/// ```dart
/// ForumScope(
///   repository: MyRemoteForumRepository(),
///   child: const ForumPage(),
/// )
/// ```
///
/// 页面也支持通过构造参数直接注入，优先级：构造参数 > ForumScope > 默认实现。
class ForumScope extends InheritedWidget {
  const ForumScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final ForumRepository repository;

  static ForumRepository of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ForumScope>()?.repository ??
      defaultForumRepository;

  @override
  bool updateShouldNotify(ForumScope oldWidget) =>
      repository != oldWidget.repository;
}
