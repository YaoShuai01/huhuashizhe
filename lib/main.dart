import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/accessibility/elder_care_controller.dart';
import 'core/accessibility/elder_care_reader.dart';
import 'core/accessibility/elder_care_scope.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'data/local_database.dart';
import 'providers/device_provider.dart';
import 'providers/update_provider.dart';
import 'services/ai_suggestion_worker.dart';
import 'services/model_hotupdate_service.dart';
import 'services/schedule_service.dart';
import 'services/voice_service.dart';
import 'services/wifi_service.dart';
import 'widgets/update_dialog.dart';
import 'widgets/splash_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalDatabase().init(); // 初始化本地数据持久化
  unawaited(VoiceService.instance.init()); // 语音播报预热（系统TTS，不阻塞启动）
  AiSuggestionWorker().start(); // 生长检测AI建议：启动离线补全监听
  // 模型热更新：联网后静默检查/下载新模型（不阻塞启动，可重入安全）
  unawaited(ModelHotupdateService.instance.checkAndDownload());
  // 轮协静默同步：已登录用户联网后自动拉取最新轮协并重排本地提醒
  unawaited(ScheduleService.instance.syncSilently());
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
    return ElderCareScope(
      controller: elderCareController,
      child: _UpdateChecker(
        child: MaterialApp.router(
          title: '护花使者',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.system,
          routerConfig: appRouter,
          builder: (context, child) {
            // 老年关怀模式：全局放大小字号，并开启长按板块朗读
            final elderCare = ElderCareScope.of(context);
            final mediaQuery = MediaQuery.of(context);
            final systemFactor = mediaQuery.textScaler.scale(16) / 16;
            final factor = systemFactor *
                (elderCare.enabled ? ElderCareController.textScaleFactor : 1.0);
            final content = MediaQuery(
              data: mediaQuery.copyWith(
                textScaler:
                    TextScaler.linear(factor.clamp(0.8, elderCare.enabled ? 1.6 : 1.2)),
              ),
              child: child!,
            );
            return elderCare.enabled
                ? ElderCareReader(child: content)
                : content;
          },
        ),
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
  /// 上一次无人机 WiFi 连接状态；null 表示尚未收到初始状态
  bool? _lastDroneConnected;

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
      unawaited(ScheduleService.instance.syncSilently());
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

    // 无人机 WiFi 连接成功播报：只在“未连接 → 已连接”时触发，
    // 打开遥控页或 App 启动时已连接都不会误播。
    ref.listen<AsyncValue<WifiStatus>>(deviceStatusProvider, (prev, next) {
      final status = next.valueOrNull;
      if (status == null) return;
      final connected = status.isConnected;
      if (_lastDroneConnected == false && connected) {
        VoiceService.instance.speak(
          '飞机连接成功',
          priority: VoicePriority.status,
          dedup: const Duration(seconds: 10),
        );
      }
      _lastDroneConnected = connected;
    });
    return widget.child;
  }
}