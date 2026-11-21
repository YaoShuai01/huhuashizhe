import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:huhuashizhe/features/classroom/pages/classroom_page.dart';
import 'package:huhuashizhe/features/services/pages/booking_page.dart';
import 'package:huhuashizhe/features/services/pages/booking_role_page.dart';
import 'package:huhuashizhe/features/services/pages/pilot_workbench_page.dart';
import 'package:huhuashizhe/features/services/pages/services_page.dart';

void main() {
  testWidgets('服务页展示小课堂板块并可进入小课堂', (tester) async {
    final router = GoRouter(
      initialLocation: '/services',
      routes: [
        GoRoute(
          path: '/services',
          builder: (context, state) => const ServicesPage(),
        ),
        GoRoute(
          path: '/services/classroom',
          builder: (context, state) => const ClassroomPage(),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('社区'), findsOneWidget);
    expect(find.text('常用服务'), findsOneWidget);
    expect(find.text('小课堂'), findsOneWidget);

    await tester.tap(find.text('小课堂'));
    await tester.pumpAndSettle();

    // 进入小课堂页，标题仍为「小课堂」，并带返回按钮
    expect(find.text('小课堂'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
  });

  testWidgets('服务页展示论坛板块并可进入论坛', (tester) async {
    final router = GoRouter(
      initialLocation: '/services',
      routes: [
        GoRoute(
          path: '/services',
          builder: (context, state) => const ServicesPage(),
        ),
        GoRoute(
          path: '/forum',
          builder: (context, state) =>
              const Scaffold(body: Text('论坛主页')),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('论坛'), findsOneWidget);

    await tester.ensureVisible(find.text('论坛'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('论坛'));
    await tester.pumpAndSettle();

    expect(find.text('论坛主页'), findsOneWidget);
  });

  testWidgets('服务页进入预约先选身份，农户端校验表单', (tester) async {
    final router = GoRouter(
      initialLocation: '/services',
      routes: [
        GoRoute(
          path: '/services',
          builder: (context, state) => const ServicesPage(),
        ),
        GoRoute(
          path: '/services/booking',
          builder: (context, state) => const BookingRolePage(),
        ),
        GoRoute(
          path: '/services/booking/farmer',
          builder: (context, state) => const BookingPage(),
        ),
        GoRoute(
          path: '/services/booking/pilot',
          builder: (context, state) => const PilotWorkbenchPage(),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('预约飞防'), findsOneWidget);
    await tester.tap(find.text('预约飞防'));
    await tester.pumpAndSettle();

    // 先出现身份选择
    expect(find.text('我是农户'), findsOneWidget);
    expect(find.text('我是飞手'), findsOneWidget);

    await tester.tap(find.text('我是农户'));
    await tester.pumpAndSettle();

    // 农户端包含飞手选择、作业信息与提交按钮
    expect(find.text('选择飞手'), findsOneWidget);
    expect(find.text('作业信息'), findsOneWidget);
    expect(find.text('李师傅'), findsOneWidget);

    await tester.dragUntilVisible(
      find.text('提交预约'),
      find.byType(ListView).last,
      const Offset(0, -300),
    );
    await tester.tap(find.text('提交预约'));
    await tester.pumpAndSettle();

    // 未填写必填项时给出提示，不弹出预约成功
    expect(find.text('请填写联系人'), findsOneWidget);
    expect(find.text('预约已提交'), findsNothing);
  });

  testWidgets('填写面积与单价后自动计算预估费用', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BookingPage()));
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('作业面积（亩）'),
      find.byType(ListView),
      const Offset(0, -200),
    );

    // 默认单价 8 元/亩，50 亩 → 400 元
    await tester.enterText(
      find.widgetWithText(TextFormField, '作业面积（亩）'),
      '50',
    );
    await tester.pump();
    expect(find.text('￥400'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, '按亩单价（元/亩）'),
      '10',
    );
    await tester.pump();
    expect(find.text('￥500'), findsOneWidget);
  });

  testWidgets('飞手列表支持距离与评分的升序降序', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BookingPage()));
    await tester.pumpAndSettle();

    expect(find.text('共 3 位飞手'), findsOneWidget);

    // 默认按距离升序：最近的李师傅在最上
    expect(
      tester.getTopLeft(find.text('李师傅')).dy,
      lessThan(tester.getTopLeft(find.text('赵师傅')).dy),
    );

    // 点「距离」的降序图标：最远的赵师傅移到最上
    await tester.tap(find.byKey(const ValueKey('sort-距离-desc')));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('赵师傅')).dy,
      lessThan(tester.getTopLeft(find.text('李师傅')).dy),
    );

    // 点「评分」的升序图标：4.7 的赵师傅在最上
    await tester.tap(find.byKey(const ValueKey('sort-评分-asc')));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('赵师傅')).dy,
      lessThan(tester.getTopLeft(find.text('李师傅')).dy),
    );

    // 点「评分」的降序图标：4.9 的李师傅在最上
    await tester.tap(find.byKey(const ValueKey('sort-评分-desc')));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('李师傅')).dy,
      lessThan(tester.getTopLeft(find.text('赵师傅')).dy),
    );
  });

  testWidgets('飞手身份进入工作台可以接单', (tester) async {
    final router = GoRouter(
      initialLocation: '/services/booking',
      routes: [
        GoRoute(
          path: '/services/booking',
          builder: (context, state) => const BookingRolePage(),
        ),
        GoRoute(
          path: '/services/booking/farmer',
          builder: (context, state) => const BookingPage(),
        ),
        GoRoute(
          path: '/services/booking/pilot',
          builder: (context, state) => const PilotWorkbenchPage(),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('我是飞手'));
    await tester.pumpAndSettle();

    expect(find.text('飞手工作台'), findsOneWidget);
    expect(find.text('待接订单'), findsOneWidget);
    expect(find.text('油菜 · 60 亩'), findsOneWidget);

    await tester.tap(find.text('接单').first);
    await tester.pumpAndSettle();

    // 订单从待接列表移入我的接单
    expect(find.text('1 单'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('我的接单'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    expect(find.text('已接单'), findsOneWidget);
    expect(find.text('油菜 · 60 亩'), findsOneWidget);
  });
}
