import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huhuashizhe/data/local_database.dart';
import 'package:huhuashizhe/features/auth/data/auth_api.dart';
import 'package:huhuashizhe/features/auth/data/auth_session.dart';
import 'package:huhuashizhe/features/auth/pages/login_page.dart';

class _FakeAuthApi implements AuthApi {
  _FakeAuthApi({this.error});

  final String? error;
  int calls = 0;

  @override
  Future<AuthUser> login({
    required String nickname,
    required String password,
  }) async {
    calls++;
    if (error != null) throw AuthException(error!);
    return AuthUser(id: 7, nickname: nickname);
  }

  @override
  Future<AuthUser> register({
    required String nickname,
    required String password,
  }) =>
      login(nickname: nickname, password: password);
}

Widget _harness(AuthApi api) => MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => LoginPage(api: api)),
            ),
            child: const Text('去登录'),
          ),
        ),
      ),
    );

void main() {
  setUp(() => AuthSession.instance.signOut());

  test('登录态持久化到本地，重启后可恢复', () {
    final db = LocalDatabase();
    AuthSession(database: db)
        .signIn(const AuthUser(id: 9, nickname: '农友阿芳'));

    // 模拟重启：新的会话实例从本地恢复
    final restored = AuthSession(database: db)..restore();
    expect(restored.user.value?.id, 9);
    expect(restored.user.value?.nickname, '农友阿芳');

    restored.signOut();
    final signedOut = AuthSession(database: db)..restore();
    expect(signedOut.isLoggedIn, isFalse);
  });

  testWidgets('空表单提交时提示填写昵称和密码', (tester) async {
    final api = _FakeAuthApi();
    await tester.pumpWidget(_harness(api));
    await tester.tap(find.text('去登录'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, '登录'));
    await tester.pump();

    expect(find.text('请输入昵称'), findsOneWidget);
    expect(find.text('请输入密码'), findsOneWidget);
    expect(api.calls, 0);
  });

  testWidgets('登录成功后写入登录状态并返回', (tester) async {
    final api = _FakeAuthApi();
    await tester.pumpWidget(_harness(api));
    await tester.tap(find.text('去登录'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), '农友阿芳');
    await tester.enterText(find.byType(TextFormField).at(1), '123456');
    await tester.tap(find.widgetWithText(ElevatedButton, '登录'));
    await tester.pumpAndSettle();

    expect(api.calls, 1);
    expect(AuthSession.instance.user.value?.nickname, '农友阿芳');
    expect(find.text('去登录'), findsOneWidget);
  });

  testWidgets('登录失败时展示后端错误信息', (tester) async {
    final api = _FakeAuthApi(error: '昵称或密码错误');
    await tester.pumpWidget(_harness(api));
    await tester.tap(find.text('去登录'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), '农友阿芳');
    await tester.enterText(find.byType(TextFormField).at(1), '654321');
    await tester.tap(find.widgetWithText(ElevatedButton, '登录'));
    await tester.pumpAndSettle();

    expect(find.text('昵称或密码错误'), findsOneWidget);
    expect(AuthSession.instance.isLoggedIn, isFalse);
  });

  testWidgets('设置密码时校验两次密码一致', (tester) async {
    final api = _FakeAuthApi();
    await tester.pumpWidget(_harness(api));
    await tester.tap(find.text('去登录'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('首次使用？设置密码'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), '农友阿芳');
    await tester.enterText(find.byType(TextFormField).at(1), '123456');
    await tester.enterText(find.byType(TextFormField).at(2), '654321');
    await tester.tap(find.widgetWithText(ElevatedButton, '设置密码并登录'));
    await tester.pump();

    expect(find.text('两次输入的密码不一致'), findsOneWidget);
    expect(api.calls, 0);
  });
}
