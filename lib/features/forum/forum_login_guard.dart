import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../auth/data/auth_session.dart';

/// 发帖前校验登录状态：未登录时提示并引导到登录页。
///
/// 返回 true 表示当前已登录，可以继续发帖。
Future<bool> ensureForumLoggedIn(BuildContext context) async {
  if (AuthSession.instance.isLoggedIn) return true;

  final goLogin = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('请先登录'),
      content: const Text('登录后才能发帖，帖子发布后对所有农友可见。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('去登录'),
        ),
      ],
    ),
  );

  if (goLogin != true || !context.mounted) return false;
  await context.push('/login');
  return AuthSession.instance.isLoggedIn;
}
