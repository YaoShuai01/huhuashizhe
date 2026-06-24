import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: HuHuaShiZheApp(),
    ),
  );
}

class HuHuaShiZheApp extends StatelessWidget {
  const HuHuaShiZheApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '护花使者',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
    );
  }
}