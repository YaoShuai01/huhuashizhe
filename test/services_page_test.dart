import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:huhuashizhe/data/local_database.dart';
import 'package:huhuashizhe/features/classroom/pages/classroom_page.dart';
import 'package:huhuashizhe/features/services/pages/booking_page.dart';
import 'package:huhuashizhe/features/services/pages/booking_role_page.dart';
import 'package:huhuashizhe/features/services/pages/pilot_profile_page.dart';
import 'package:huhuashizhe/features/services/pages/pilot_workbench_page.dart';
import 'package:huhuashizhe/features/services/pages/services_page.dart';

void main() {
  setUp(() => LocalDatabase().remove('booking_role'));

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

    // 接单前弹出确认框，提示 12 小时后取消需支付 2% 费用
    expect(find.text('确认接单'), findsOneWidget);
    expect(find.textContaining('2% 的接单费用'), findsOneWidget);

    // 确定按钮 5 秒倒计时内不可点击
    expect(find.text('确定接单（5）'), findsOneWidget);
    final disabled = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(disabled.onPressed, isNull);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.tap(find.text('确定接单'));
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

    // 退出工作台后重新进入，已接订单不会丢失
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('飞手工作台'), findsNothing);

    await tester.tap(find.text('我是飞手'));
    await tester.pumpAndSettle();

    expect(find.text('飞手工作台'), findsOneWidget);
    expect(find.text('1 单'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('已接单'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    expect(find.text('油菜 · 60 亩'), findsOneWidget);
  });

  testWidgets('作物类型选择其他时可自定义填写', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BookingPage()));
    await tester.pumpAndSettle();

    expect(find.text('作物名称'), findsNothing);

    await tester.tap(find.text('其他'));
    await tester.pumpAndSettle();

    // 选择其他后出现作物名称输入框，可自定义填写
    expect(find.text('作物名称'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, '作物名称'),
      '甘蔗',
    );
    await tester.pump();
    expect(find.text('甘蔗'), findsOneWidget);

    // 切回预设作物后输入框隐藏
    await tester.scrollUntilVisible(
      find.text('油菜'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('油菜'));
    await tester.pumpAndSettle();
    expect(find.text('作物名称'), findsNothing);
  });

  testWidgets('飞手工作台可进入资料页并保存资料', (tester) async {
    final router = GoRouter(
      initialLocation: '/services/booking/pilot',
      routes: [
        GoRoute(
          path: '/services/booking/pilot',
          builder: (context, state) => const PilotWorkbenchPage(),
        ),
        GoRoute(
          path: '/services/booking/pilot/profile',
          builder: (context, state) => const PilotProfilePage(),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('飞手资料'));
    await tester.pumpAndSettle();

    expect(find.text('完善资料后可被更多农户找到'), findsOneWidget);

    // 必填项为空时保存会被拦截
    await tester.tap(find.text('保存资料'));
    await tester.pumpAndSettle();
    expect(find.text('请填写姓名'), findsOneWidget);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '张师傅');
    await tester.enterText(fields.at(1), '13800001111');
    await tester.enterText(fields.at(2), '监利市新沟镇');
    await tester.enterText(fields.at(4), '8');
    await tester.enterText(fields.at(5), '3');

    await tester.scrollUntilVisible(
      find.text('保存资料'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存资料'));
    await tester.pumpAndSettle();

    // 返回工作台并展示已完善状态
    expect(find.text('已完善：张师傅 · 监利市新沟镇'), findsOneWidget);
  });

  testWidgets('记住身份后直接进入对应页面，可从右上角转换', (tester) async {
    LocalDatabase().set('booking_role', 'farmer');

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

    await tester.tap(find.text('预约飞防'));
    await tester.pumpAndSettle();

    // 不再经过身份选择，直接进入上次选择的农户页
    expect(find.text('选择飞手'), findsOneWidget);
    expect(find.text('身份转换'), findsOneWidget);

    await tester.tap(find.text('身份转换'));
    await tester.pumpAndSettle();
    expect(find.text('转换身份'), findsOneWidget);

    await tester.tap(find.text('我是飞手'));
    await tester.pumpAndSettle();

    expect(find.text('飞手工作台'), findsOneWidget);
    expect(find.text('身份转换'), findsOneWidget);
  });
}
