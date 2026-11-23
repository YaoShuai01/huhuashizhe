// 护花使者 APP - 小课堂测试
// 覆盖：阅读数累加、课程收藏、【我的收藏 - 课程】标签页
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:huhuashizhe/core/theme/app_theme.dart';
import 'package:huhuashizhe/data/local_database.dart';
import 'package:huhuashizhe/features/classroom/data/classroom_courses.dart';
import 'package:huhuashizhe/features/classroom/data/classroom_store.dart';
import 'package:huhuashizhe/features/classroom/pages/classroom_page.dart';
import 'package:huhuashizhe/features/classroom/widgets/course_card.dart';
import 'package:huhuashizhe/features/classroom/widgets/course_detail_page.dart';
import 'package:huhuashizhe/features/forum/data/forum_repository.dart';
import 'package:huhuashizhe/features/forum/pages/forum_favorites_page.dart';

/// 清空小课堂的持久化数据，并让全局 store 重新加载
void resetClassroomStore() {
  LocalDatabase().remove(ClassroomStore.readCountsKey);
  LocalDatabase().remove(ClassroomStore.favoritesKey);
  ClassroomStore.instance.reload();
}

Widget _browseApp() {
  final router = GoRouter(
    initialLocation: '/classroom',
    routes: [
      GoRoute(
        path: '/classroom',
        builder: (context, state) => const ClassroomPage(),
      ),
      GoRoute(
        path: '/classroom/course',
        builder: (context, state) {
          final extra = state.extra is Map ? state.extra as Map : const <String, dynamic>{};
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
    ],
  );
  return ProviderScope(
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      routerConfig: router,
    ),
  );
}

void main() {
  setUp(resetClassroomStore);
  tearDown(resetClassroomStore);

  group('ClassroomStore', () {
    test('内置阅读基数稳定且在 60~199 之间', () {
      for (final course in classroomCourses) {
        final seed = ClassroomStore.seedReads(course.id);
        expect(seed, greaterThanOrEqualTo(60));
        expect(seed, lessThan(200));
        expect(ClassroomStore.seedReads(course.id), seed);
      }
    });

    test('incrementRead 每次加一并持久化', () {
      final store = ClassroomStore.instance;
      const id = 'rape-sclerotinia';
      final before = store.readCount(id);

      expect(store.incrementRead(id), before + 1);
      expect(store.incrementRead(id), before + 2);
      expect(LocalDatabase().get(ClassroomStore.readCountsKey), contains(id));

      // 新建实例从同一份存储读回
      final reloaded = ClassroomStore();
      expect(reloaded.readCount(id), before + 2);
    });

    test('toggleFavorite 可反复切换', () {
      final store = ClassroomStore.instance;
      const id = 'rape-aphid';
      expect(store.isFavorite(id), isFalse);

      expect(store.toggleFavorite(id), isTrue);
      expect(store.isFavorite(id), isTrue);
      expect(store.favoriteCourses.map((c) => c.id), contains(id));

      expect(store.toggleFavorite(id), isFalse);
      expect(store.isFavorite(id), isFalse);
      expect(store.favoriteCourses, isEmpty);
    });

    test('收藏按课程表顺序返回，忽略已不存在的 id', () {
      LocalDatabase().set(
        ClassroomStore.favoritesKey,
        '["tea-green-control","rape-sclerotinia","removed-course"]',
      );
      final store = ClassroomStore();
      expect(store.favoriteCourses.map((c) => c.id).toList(),
          ['rape-sclerotinia', 'tea-green-control']);
    });

    test('存储内容损坏时不抛异常', () {
      LocalDatabase().set(ClassroomStore.readCountsKey, '{bad json');
      LocalDatabase().set(ClassroomStore.favoritesKey, 'not-a-list');
      expect(() => ClassroomStore(), returnsNormally);
      expect(ClassroomStore.instance.favoriteCourses, isEmpty);
    });
  });

  group('ClassroomPage', () {
    testWidgets('进入课程详情后列表阅读数 +1', (tester) async {
      final store = ClassroomStore.instance;
      const id = 'rape-sclerotinia';
      final before = store.readCount(id);

      await tester.pumpWidget(_browseApp());
      await tester.pumpAndSettle();
      expect(find.text('$before 次阅读'), findsOneWidget);

      await tester.tap(find.text('油菜菌核病综合防治技术'));
      await tester.pumpAndSettle();
      expect(find.text('内容详情'), findsOneWidget);
      expect(find.text('${before + 1} 次阅读'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('${before + 1} 次阅读'), findsOneWidget);
      expect(store.readCount(id), before + 1);
    });

    testWidgets('点击收藏图标后变为已收藏', (tester) async {
      await tester.pumpWidget(_browseApp());
      await tester.pumpAndSettle();

      final firstCard = find.byType(CourseCard).first;
      expect(
        find.descendant(of: firstCard, matching: find.byIcon(Icons.bookmark_border)),
        findsOneWidget,
      );

      await tester.tap(
        find.descendant(of: firstCard, matching: find.byIcon(Icons.bookmark_border)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.descendant(of: firstCard, matching: find.byIcon(Icons.bookmark)),
        findsOneWidget,
      );
      expect(ClassroomStore.instance.isFavorite('rape-sclerotinia'), isTrue);
    });

    testWidgets('详情页收藏按钮同步状态', (tester) async {
      await tester.pumpWidget(_browseApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('油菜菌核病综合防治技术'));
      await tester.pumpAndSettle();

      final favoriteButton = find.byTooltip('收藏');
      expect(favoriteButton, findsOneWidget);
      await tester.tap(favoriteButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byTooltip('取消收藏'), findsOneWidget);
      expect(ClassroomStore.instance.isFavorite('rape-sclerotinia'), isTrue);
    });
  });

  group('我的收藏 - 课程', () {
    testWidgets('收藏的课程出现在课程标签页', (tester) async {
      ClassroomStore.instance.toggleFavorite('wheat-fusarium');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: ForumFavoritesPage(repository: InMemoryForumRepository()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('帖子'), findsOneWidget);
      await tester.tap(find.text('课程'));
      await tester.pumpAndSettle();

      expect(find.text('小麦赤霉病综合防治方案'), findsOneWidget);
      expect(find.text('油菜菌核病综合防治技术'), findsNothing);
    });

    testWidgets('没有收藏时显示空状态', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: ForumFavoritesPage(repository: InMemoryForumRepository()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('课程'));
      await tester.pumpAndSettle();

      expect(find.text('还没有收藏的课程'), findsOneWidget);
    });
  });
}
