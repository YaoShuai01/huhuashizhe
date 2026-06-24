import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import '../../features/home/pages/home_page.dart';
import '../../features/presets/pages/presets_page.dart';
import '../../features/classroom/pages/classroom_page.dart';
import '../../features/mine/pages/mine_page.dart';
import '../../features/presets/widgets/preset_form_page.dart';
import '../../features/classroom/widgets/course_detail_page.dart';
import '../../features/mission/pages/map_select_page.dart';
import '../../features/mine/widgets/device_scan_page.dart';
import '../../features/settings/pages/settings_page.dart';
import '../../features/mine/pages/mine_sub_pages.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/home',
  routes: [
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) {
        return AppShell(child: child);
      },
      routes: [
        GoRoute(
          path: '/home',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: HomePage(),
          ),
        ),
        GoRoute(
          path: '/presets',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: PresetsPage(),
          ),
        ),
        GoRoute(
          path: '/classroom',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ClassroomPage(),
          ),
        ),
        GoRoute(
          path: '/mine',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: MinePage(),
          ),
        ),
      ],
    ),
    // 子页面路由（位于 ShellRoute 外部，不显示底部导航栏）
    GoRoute(
      path: '/presets/form',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final existingPreset = state.extra as Map<String, dynamic>?;
        return existingPreset != null
            ? PresetFormPage(existingPreset: existingPreset)
            : const PresetFormPage();
      },
    ),
    GoRoute(
      path: '/classroom/course',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final extra = state.extra as Map<String, String>?;
        return CourseDetailPage(
          title: extra?['title'] ?? '',
          content: extra?['content'] ?? '',
          cropType: extra?['cropType'] ?? '',
          category: extra?['category'] ?? '',
        );
      },
    ),
    GoRoute(
      path: '/mission/map',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const MapSelectPage(),
    ),
    GoRoute(
      path: '/mine/account',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const AccountPage(),
    ),
    GoRoute(
      path: '/mine/device',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const DeviceScanPage(),
    ),
    GoRoute(
      path: '/mine/settings',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const SettingsPage(),
    ),
    GoRoute(
      path: '/mine/legal',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const LegalPage(),
    ),
    GoRoute(
      path: '/mine/help',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const HelpPage(),
    ),
    GoRoute(
      path: '/mine/feedback',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const FeedbackPage(),
    ),
    GoRoute(
      path: '/mine/about',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const AboutPage(),
    ),
    GoRoute(
      path: '/mine/version',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const VersionInfoPage(),
    ),
  ],
);

class AppShell extends StatelessWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    if (location.startsWith('/presets')) return 1;
    if (location.startsWith('/classroom')) return 2;
    if (location.startsWith('/mine')) return 3;
    return 0;
  }

  void _onTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/home');
        break;
      case 1:
        context.go('/presets');
        break;
      case 2:
        context.go('/classroom');
        break;
      case 3:
        context.go('/mine');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final index = _currentIndex(context);
    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        onTap: (i) => _onTap(context, i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: '首页',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bookmark_outline),
            activeIcon: Icon(Icons.bookmark),
            label: '预设',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.school_outlined),
            activeIcon: Icon(Icons.school),
            label: '小课堂',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}