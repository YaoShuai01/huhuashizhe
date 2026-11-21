import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:huhuashizhe/features/auth/pages/login_page.dart';
import 'package:huhuashizhe/features/auth/services/auth_service.dart';
import 'package:huhuashizhe/features/forum/data/forum_repository.dart'
    show InMemoryForumRepository;

void main() {
  setUp(() {
    AuthService.instance.resetForTest();
  });

  group('AuthService（本地演示账号）', () {
    test('注册成功并自动登录', () {
      final error = AuthService.instance.register(
        username: '张三',
        password: '123456',
        confirm: '123456',
        nickname: '三哥',
      );
      expect(error, isNull);
      final user = AuthService.instance.currentUser;
      expect(user, isNotNull);
      expect(user!.username, '张三');
      expect(user.nickname, '三哥');
      expect(AuthService.instance.isLoggedIn, isTrue);
    });

    test('注册校验：用户名过短/含空格/重复/密码过短/两次不一致', () {
      expect(
        AuthService.instance.register(
            username: 'a', password: '123456', confirm: '123456'),
        '用户名长度需在 2-20 个字符之间',
      );
      expect(
        AuthService.instance.register(
            username: 'a b', password: '123456', confirm: '123456'),
        '用户名不能包含空格',
      );
      expect(
        AuthService.instance.register(
            username: '张三', password: '12345', confirm: '12345'),
        '密码至少 6 位',
      );
      expect(
        AuthService.instance.register(
            username: '张三', password: '123456', confirm: '654321'),
        '两次输入的密码不一致',
      );
      expect(
        AuthService.instance.register(
            username: '张三', password: '123456', confirm: '123456'),
        isNull,
      );
      expect(
        AuthService.instance.register(
            username: '张三', password: 'abcdef', confirm: 'abcdef'),
        '该用户名已被注册',
      );
    });

    test('登录：密码错误提示，正确后成功；未知用户引导注册', () {
      AuthService.instance.register(
          username: '张三', password: '123456', confirm: '123456');
      AuthService.instance.logout();

      expect(
        AuthService.instance.login(username: '张三', password: '000000'),
        '密码错误，请重试',
      );
      expect(
        AuthService.instance.login(username: '李四', password: '123456'),
        '用户不存在，请先注册',
      );
      expect(
        AuthService.instance.login(username: '张三', password: '123456'),
        isNull,
      );
      expect(AuthService.instance.isLoggedIn, isTrue);
    });

    test('登出后再登录，会话切换正确', () {
      AuthService.instance.register(
          username: '张三', password: '123456', confirm: '123456');
      AuthService.instance.logout();
      expect(AuthService.instance.currentUser, isNull);
      AuthService.instance.login(username: '张三', password: '123456');
      expect(AuthService.instance.currentUser!.username, '张三');
    });

    test('密码哈希存储：重新登录验证哈希比对正确', () {
      AuthService.instance.register(
          username: '张三', password: 'secret123', confirm: 'secret123');
      AuthService.instance.logout();
      expect(
        AuthService.instance.login(username: '张三', password: 'secret123'),
        isNull,
      );
    });

    test('修改昵称：成功后 currentUser 昵称更新', () {
      AuthService.instance.register(
          username: '张三', password: '123456', confirm: '123456');
      expect(AuthService.instance.updateNickname('新昵称'), isNull);
      expect(AuthService.instance.currentUser!.nickname, '新昵称');
      expect(AuthService.instance.updateNickname(''), '昵称需为 1-20 个字符');
    });
  });

  group('数据归属', () {
    test('登录后论坛 currentUserName 取昵称，未登录回退"我"', () {
      expect(InMemoryForumRepository.currentUserName, '我');
      AuthService.instance.register(
          username: '张三', password: '123456', confirm: '123456', nickname: '三哥');
      expect(InMemoryForumRepository.currentUserName, '三哥');
      AuthService.instance.logout();
      expect(InMemoryForumRepository.currentUserName, '我');
    });
  });

  group('登录/注册页（widget）', () {
    Future<void> pumpPage(WidgetTester tester) async {
      final router = GoRouter(
        initialLocation: '/auth',
        routes: [
          GoRoute(
            path: '/auth',
            builder: (_, __) => const LoginPage(),
          ),
          GoRoute(
            path: '/home',
            builder: (_, __) => const Scaffold(body: Text('首页占位')),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('默认登录模式：校验拦截空表单，切换注册出现确认密码', (tester) async {
      await pumpPage(tester);
      expect(find.text('登录你的账号'), findsOneWidget);
      expect(find.text('确认密码'), findsNothing);

      // 空表单提交被 validator 拦截
      await tester.tap(find.text('登 录'));
      await tester.pumpAndSettle();
      expect(find.text('请输入至少 2 个字符的用户名'), findsOneWidget);

      // 切到注册模式
      await tester.tap(find.text('没有账号？注册一个'));
      await tester.pumpAndSettle();
      expect(find.text('注册新账号'), findsOneWidget);
      expect(find.text('确认密码'), findsOneWidget);
    });

    testWidgets('注册流程：填写后提交成功（会话生效）', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.text('没有账号？注册一个'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextFormField, '用户名'), '李四');
      await tester.enterText(
          find.widgetWithText(TextFormField, '密码'), '123456');
      await tester.enterText(
          find.widgetWithText(TextFormField, '确认密码'), '123456');
      await tester.tap(find.text('注 册'));
      await tester.pumpAndSettle();

      expect(AuthService.instance.isLoggedIn, isTrue);
      expect(AuthService.instance.currentUser!.username, '李四');
      // 注册成功自动跳转首页
      expect(find.text('首页占位'), findsOneWidget);
    });

    testWidgets('登录流程：错误密码提示、正确密码通过', (tester) async {
      AuthService.instance.register(
          username: '王五', password: '123456', confirm: '123456');
      AuthService.instance.logout();

      await pumpPage(tester);
      await tester.enterText(
          find.widgetWithText(TextFormField, '用户名'), '王五');
      await tester.enterText(
          find.widgetWithText(TextFormField, '密码'), '111111');
      await tester.tap(find.text('登 录'));
      await tester.pumpAndSettle();
      expect(find.text('密码错误，请重试'), findsOneWidget);
      expect(AuthService.instance.isLoggedIn, isFalse);

      await tester.enterText(
          find.widgetWithText(TextFormField, '密码'), '123456');
      await tester.tap(find.text('登 录'));
      await tester.pumpAndSettle();
      expect(AuthService.instance.isLoggedIn, isTrue);
    });
  });
}
