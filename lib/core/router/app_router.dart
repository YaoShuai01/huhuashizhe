import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import '../layout/tablet_layout.dart';
import '../../features/auth/pages/login_page.dart';
import '../../features/home/pages/home_page.dart';
import '../../features/presets/pages/presets_page.dart';
import '../../features/classroom/pages/classroom_page.dart';
import '../../features/services/pages/services_page.dart';
import '../../features/services/pages/booking_page.dart';
import '../../features/services/pages/booking_role_page.dart';
import '../../features/services/pages/pilot_profile_page.dart';
import '../../features/services/pages/pilot_workbench_page.dart';
import '../../features/mine/pages/mine_page.dart';
import '../../features/presets/widgets/preset_form_page.dart';
import '../../features/presets/widgets/preset_tuning_page.dart';
import '../../features/classroom/widgets/course_detail_page.dart';
import '../../features/mission/pages/map_select_page.dart';
import '../../features/mine/widgets/wifi_scan_page.dart';
import '../../features/mine/pages/mine_sub_pages.dart';
import '../../features/settings/pages/settings_page.dart';
import '../../features/ai_chat/pages/ai_chat_page.dart';
import '../../features/data_center/pages/data_center_page.dart';
import '../../features/data_center/pages/data_list_page.dart';
import '../../features/data_center/data_module_config.dart';
import '../../features/remote_control/pages/remote_control_page.dart';
import '../../features/model_test/pages/model_test_page.dart';
import '../../features/model_test/pages/growth_records_page.dart';
import '../../features/speedometer/pages/gps_speedometer_page.dart';
import '../../features/schedule/pages/schedule_gate_page.dart';
import '../../features/schedule/pages/schedule_page.dart';
import '../../features/schedule/pages/schedule_edit_page.dart';
import '../../features/schedule/pages/schedule_messages_page.dart';
import '../../features/forum/data/forum_models.dart';
import '../../features/forum/pages/forum_page.dart';
import '../../features/forum/pages/forum_section_page.dart';
import '../../features/forum/pages/forum_compose_page.dart';
import '../../features/forum/pages/forum_my_posts_page.dart';
import '../../features/forum/pages/forum_messages_page.dart';
import '../../features/forum/pages/forum_favorites_page.dart';
import '../../features/forum/pages/forum_post_detail_page.dart';
import '../../features/sentinel/pages/sentinel_page.dart';
import '../../features/sentinel/pages/farm_game_page.dart';
import '../../features/cloud_farming/pages/cloud_farm_page.dart';
import '../../features/cloud_farming/pages/cloud_plot_create_page.dart';
import '../../features/cloud_farming/pages/cloud_planting_wizard_page.dart';
import '../../features/cloud_farming/pages/cloud_plot_detail_page.dart';
import '../../features/cloud_farming/pages/cloud_remote_page.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

/// 获取根导航器key（供更新弹窗等全局弹窗使用）
GlobalKey<NavigatorState> get rootNavigatorKey => _rootNavigatorKey;

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/home',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return AppShell(navigationShell: navigationShell);
      },
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              pageBuilder:
                  (context, state) => const NoTransitionPage(child: HomePage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/data-center',
              pageBuilder:
                  (context, state) =>
                      const NoTransitionPage(child: DataCenterPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/services',
              pageBuilder:
                  (context, state) =>
                      const NoTransitionPage(child: ServicesPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/mine',
              pageBuilder:
                  (context, state) => const NoTransitionPage(child: MinePage()),
            ),
          ],
        ),
      ],
    ),
    // 子页面路由（位于 ShellRoute 外部，不显示底部导航栏）
    GoRoute(
      path: '/presets',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const PresetsPage(),
    ),
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
      path: '/presets/tuning',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final preset = state.extra as Map<String, dynamic>;
        return PresetTuningPage(preset: preset);
      },
    ),
    GoRoute(
      path: '/services/classroom',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ClassroomPage(),
    ),
    GoRoute(
      path: '/services/booking',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const BookingRolePage(),
    ),
    GoRoute(
      path: '/services/booking/farmer',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final q = state.uri.queryParameters;
        return BookingPage(
          initialCrop: q['crop'],
          initialArea: q['area'],
          initialLocation: q['location'],
        );
      },
    ),
    GoRoute(
      path: '/services/booking/pilot',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const PilotWorkbenchPage(),
    ),
    GoRoute(
      path: '/services/booking/pilot/profile',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const PilotProfilePage(),
    ),
    GoRoute(
      path: '/classroom/course',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final extra =
            state.extra is Map ? state.extra as Map : const <String, dynamic>{};
        return CourseDetailPage(
          courseId: (extra['id'] ?? '').toString(),
          title: (extra['title'] ?? '').toString(),
          content: (extra['content'] ?? '').toString(),
          cropType: (extra['cropType'] ?? '').toString(),
          category: (extra['category'] ?? '').toString(),
          readCount: int.tryParse('${extra['readCount'] ?? 0}') ?? 0,
        );
      },
    ),
    GoRoute(
      path: '/mission/map',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final presetParams = state.extra as Map<String, dynamic>?;
        return MapSelectPage(presetParams: presetParams);
      },
    ),
    GoRoute(
      path: '/speedometer',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const GpsSpeedometerPage(),
    ),
    GoRoute(
      path: '/login',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const LoginPage(),
    ),
    GoRoute(
      path: '/forum',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ForumPage(),
    ),
    GoRoute(
      path: '/forum/section',
      parentNavigatorKey: _rootNavigatorKey,
      builder:
          (context, state) => ForumSectionPage(section: state.extra as String),
    ),
    GoRoute(
      path: '/forum/compose',
      parentNavigatorKey: _rootNavigatorKey,
      builder:
          (context, state) =>
              ForumComposePage(initialSection: state.extra as String?),
    ),
    GoRoute(
      path: '/forum/my-posts',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ForumMyPostsPage(),
    ),
    GoRoute(
      path: '/forum/messages',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ForumMessagesPage(),
    ),
    GoRoute(
      path: '/forum/post',
      parentNavigatorKey: _rootNavigatorKey,
      builder:
          (context, state) => ForumPostDetailPage(
            post: state.extra as ForumPost,
            // 消息提醒可带 ?reply=<评论id>，进入后滚到并高亮该楼
            focusReplyId: state.uri.queryParameters['reply'],
          ),
    ),
    GoRoute(
      path: '/forum/favorites',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ForumFavoritesPage(),
    ),
    GoRoute(
      path: '/mine/account',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const AccountPage(),
    ),
    GoRoute(
      path: '/mine/device',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const WifiScanPage(),
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
    GoRoute(
      path: '/mine/manual',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ManualPage(),
    ),
    GoRoute(
      path: '/mine/feature-intro',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const FeatureIntroPage(),
    ),
    GoRoute(
      path: '/mine/license',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const OpenSourceLicensePage(),
    ),
    GoRoute(
      path: '/mine/legal-detail',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final args = state.extra as Map<String, String>;
        return LegalDetailPage(
          title: args['title']!,
          content: args['content']!,
        );
      },
    ),
    GoRoute(
      path: '/notification',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const NotificationPage(),
    ),
    GoRoute(
      path: '/mission/history',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const MissionHistoryPage(),
    ),
    GoRoute(
      path: '/remote-control',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const RemoteControlPage(),
    ),
    GoRoute(
      path: '/ai-chat',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const AiChatPage(),
    ),
    GoRoute(
      path: '/model-test',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ModelTestPage(),
    ),
    GoRoute(
      path: '/growth-records',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const GrowthRecordsPage(),
    ),
    GoRoute(
      path: '/data-center/list',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final config = state.extra as DataModuleConfig;
        return DataListPage(config: config);
      },
    ),
    GoRoute(
      path: '/schedule',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ScheduleGatePage(),
    ),
    GoRoute(
      path: '/schedule/home',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const SchedulePage(),
    ),
    GoRoute(
      path: '/schedule/edit',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ScheduleEditPage(),
    ),
    GoRoute(
      path: '/schedule/messages',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ScheduleMessagesPage(),
    ),
    GoRoute(
      path: '/sentinel',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const SentinelPage(),
    ),
    GoRoute(
      path: '/sentinel/farm',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const FarmGamePage(),
    ),
    GoRoute(
      path: '/cloud-farm',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const CloudFarmPage(),
    ),
    GoRoute(
      path: '/cloud-farm/create',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const CloudPlotCreatePage(),
    ),
    GoRoute(
      path: '/cloud-farm/plant',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return CloudPlantingWizardPage(
          initialPlotId: extra?['plotId'] as String?,
        );
      },
    ),
    GoRoute(
      path: '/cloud-farm/plot/:id',
      parentNavigatorKey: _rootNavigatorKey,
      builder:
          (context, state) =>
              CloudPlotDetailPage(plotId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/cloud-farm/remote/:id',
      parentNavigatorKey: _rootNavigatorKey,
      builder:
          (context, state) =>
              CloudRemotePage(plotId: state.pathParameters['id']!),
    ),
  ],
);

class AppShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    // 平板布局：用户在设置页打开开关，且横屏、最短边 >= 600 时，
    // 底部导航换成左侧 NavigationRail，把横向空间留给内容。
    final useTablet = LayoutScope.useTablet(context);
    if (!useTablet) {
      return Scaffold(
        body: navigationShell,
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: navigationShell.currentIndex,
          onTap:
              (index) => navigationShell.goBranch(
                index,
                initialLocation: index == navigationShell.currentIndex,
              ),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: '首页',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard),
              label: '数据管理',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.miscellaneous_services_outlined),
              activeIcon: Icon(Icons.miscellaneous_services),
              label: '社区',
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

    void goBranch(int index) => navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: goBranch,
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: Text('首页'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: Text('数据管理'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.miscellaneous_services_outlined),
                selectedIcon: Icon(Icons.miscellaneous_services),
                label: Text('社区'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: Text('我的'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: navigationShell),
        ],
      ),
    );
  }
}
