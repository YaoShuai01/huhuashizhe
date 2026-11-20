import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// 闪屏页：Logo居中 + 护花使者团队
///
/// 背景与文字用主题语义色，深色模式下不再闪白底。
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/icom.png',
              width: 120,
              height: 120,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 24),
            Text(
              '护花使者团队',
              style: TextStyle(
                fontSize: 16,
                color: palette.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
