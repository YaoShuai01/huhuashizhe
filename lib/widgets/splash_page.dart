import 'package:flutter/material.dart';

/// 闪屏页：Logo居中 + 欢迎报考湖北职业技术学院
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/logo.jpg',
              width: 120,
              height: 120,
            ),
            const SizedBox(height: 24),
            const Text(
              '欢迎报考湖北职业技术学院',
              style: TextStyle(
                fontSize: 16,
                color: Color(0xFF333333),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}