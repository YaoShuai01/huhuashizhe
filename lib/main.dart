import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'providers/update_provider.dart';
import 'widgets/update_dialog.dart';

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

class _UpdateCheckerState extends ConsumerState<_UpdateChecker> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          ref.read(updateProvider.notifier).checkForUpdate();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(updateProvider);
    ref.listen<UpdateState>(updateProvider, (prev, next) {
      if (next.status == UpdateStatus.updateAvailable && prev?.status != UpdateStatus.updateAvailable) {
        UpdateDialog.show(context);
      }
    });
    return widget.child;
  }
}