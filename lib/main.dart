import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'data/local_database.dart';
import 'providers/update_provider.dart';
import 'widgets/update_dialog.dart';
import 'widgets/splash_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalDatabase().init(); // 初始化本地数据持久化
  runApp(
    const ProviderScope(
      child: HuHuaShiZheApp(),
    ),
  );
}

class HuHuaShiZheApp extends StatefulWidget {
  const HuHuaShiZheApp({super.key});

  @override
  State<HuHuaShiZheApp> createState() => _HuHuaShiZheAppState();
}

class _HuHuaShiZheAppState extends State<HuHuaShiZheApp> {
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    // 闪屏页显示1.5秒后切换到主应用
    Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _showSplash = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showSplash) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: SplashPage(),
      );
    }
    return _UpdateChecker(
      child: MaterialApp.router(
        title: '护花使者',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        routerConfig: appRouter,
      ),
    );
  }
}

class _UpdateChecker extends ConsumerStatefulWidget {
  final Widget child;
  const _UpdateChecker({required this.child});

  @override
  ConsumerState<_UpdateChecker> createState() => _UpdateCheckerState();
}

class _UpdateCheckerState extends ConsumerState<_UpdateChecker> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkUpdate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 应用从后台回到前台时自动刷新
    if (state == AppLifecycleState.resumed) {
      _checkUpdate();
    }
  }

  void _checkUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(updateProvider.notifier).checkForUpdate();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(updateProvider);
    ref.listen<UpdateState>(updateProvider, (prev, next) {
      // 检测到新版本时，使用根导航器的context弹出更新对话框
      if (next.status == UpdateStatus.updateAvailable && prev?.status != UpdateStatus.updateAvailable) {
        // 延迟一帧确保MaterialApp已完全构建
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (rootNavigatorKey.currentContext != null && mounted) {
            UpdateDialog.show(rootNavigatorKey.currentContext!);
          }
        });
      }
    });
    return widget.child;
  }
}