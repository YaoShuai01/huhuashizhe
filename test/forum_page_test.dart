import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huhuashizhe/features/forum/data/forum_models.dart';
import 'package:huhuashizhe/features/forum/data/forum_repository.dart';
import 'package:huhuashizhe/features/forum/forum_scope.dart';
import 'package:huhuashizhe/features/forum/pages/forum_messages_page.dart';
import 'package:huhuashizhe/features/forum/pages/forum_page.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  testWidgets('论坛页展示三个分区与交流区版块', (tester) async {
    await tester.pumpWidget(wrap(const ForumPage()));

    expect(find.text('论坛'), findsOneWidget);
    expect(find.text('所有分区'), findsOneWidget);
    expect(find.text('交流区'), findsOneWidget);
    expect(find.text('问答区'), findsOneWidget);
    expect(find.text('管理区'), findsOneWidget);

    // 默认展示交流区版块
    expect(find.text('农友留言区'), findsOneWidget);
    expect(find.text('飞防作业交流'), findsOneWidget);
    expect(find.text('新手提问区'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('作业晒图'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('作业晒图'), findsOneWidget);
    expect(find.text('发帖'), findsOneWidget);

    // 已按要求去掉的内容
    expect(find.text('我的关注'), findsNothing);
    expect(find.text('原创区'), findsNothing);
    expect(find.text('纯爱区'), findsNothing);
    expect(find.text('添加关注'), findsNothing);
  });

  testWidgets('切换问答区后展示问答区版块', (tester) async {
    await tester.pumpWidget(wrap(const ForumPage()));

    await tester.tap(find.text('问答区'));
    await tester.pumpAndSettle();

    expect(find.text('病虫害问答'), findsOneWidget);
    expect(find.text('新手提问区'), findsOneWidget);
    expect(find.text('药效点评'), findsOneWidget);
    expect(find.text('农友留言区'), findsNothing);
  });

  testWidgets('切换管理区后展示管理区版块', (tester) async {
    await tester.pumpWidget(wrap(const ForumPage()));

    await tester.tap(find.text('管理区'));
    await tester.pumpAndSettle();

    expect(find.text('公告与通知'), findsOneWidget);
    expect(find.text('意见反馈'), findsOneWidget);
    expect(find.text('举报与版规'), findsOneWidget);
    expect(find.text('农友留言区'), findsNothing);
  });

  testWidgets('支持通过 ForumScope 注入外部数据源', (tester) async {
    final repository = InMemoryForumRepository(
      categories: const [
        ForumCategory(name: '注入区', icon: Icons.star_outline),
      ],
      sections: const [
        ForumSection(
          title: '注入版块',
          desc: '来自外部数据源',
          category: '注入区',
        ),
      ],
      posts: [],
      messages: [],
      seed: false,
    );

    await tester.pumpWidget(
      wrap(
        ForumScope(
          repository: repository,
          child: const ForumPage(),
        ),
      ),
    );

    expect(find.text('注入区'), findsOneWidget);
    expect(find.text('注入版块'), findsOneWidget);
    expect(find.text('交流区'), findsNothing);
  });

  testWidgets('消息页由数据源驱动，可全部已读', (tester) async {
    final repository = InMemoryForumRepository();

    await tester.pumpWidget(
      wrap(
        ForumScope(
          repository: repository,
          child: const ForumMessagesPage(),
        ),
      ),
    );

    expect(find.text('v2.9.6 版本已发布'), findsOneWidget);
    expect(repository.hasUnreadMessages, isTrue);

    await tester.tap(find.text('全部已读'));
    await tester.pumpAndSettle();

    expect(repository.hasUnreadMessages, isFalse);
  });

  test('发帖后进入对应版块与我的帖子', () {
    final repository = InMemoryForumRepository();
    final before = repository.countOf('新手提问区');

    final post = repository.publish(
      section: '新手提问区',
      title: '起飞前检查清单求补充',
      content: '除了电池和桨叶，还需要检查哪些项目？',
    );

    expect(repository.countOf('新手提问区'), before + 1);
    expect(repository.postsOf('新手提问区').first.id, post.id);
    expect(repository.myPosts.any((p) => p.id == post.id), isTrue);
  });
}
