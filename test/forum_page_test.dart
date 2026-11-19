import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huhuashizhe/features/forum/data/forum_models.dart';
import 'package:huhuashizhe/features/forum/data/forum_repository.dart';
import 'package:huhuashizhe/features/forum/forum_scope.dart';
import 'package:huhuashizhe/features/forum/pages/forum_favorites_page.dart';
import 'package:huhuashizhe/features/forum/pages/forum_messages_page.dart';
import 'package:huhuashizhe/features/forum/pages/forum_page.dart';
import 'package:huhuashizhe/features/forum/pages/forum_post_detail_page.dart';
import 'package:huhuashizhe/features/forum/pages/forum_section_page.dart';

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

  testWidgets('消息页分点赞与回复两个分支，可全部已读', (tester) async {
    final repository = InMemoryForumRepository();

    await tester.pumpWidget(
      wrap(
        ForumScope(
          repository: repository,
          child: const ForumMessagesPage(),
        ),
      ),
    );

    expect(find.text('点赞'), findsOneWidget);
    expect(find.text('回复'), findsOneWidget);
    expect(find.text('收藏'), findsOneWidget);

    // 默认展示点赞消息
    expect(find.text('农友 种田的老张 赞了你的帖子'), findsOneWidget);
    expect(find.text('意见反馈已回复'), findsNothing);
    expect(repository.hasUnreadMessages, isTrue);

    await tester.tap(find.text('回复'));
    await tester.pumpAndSettle();

    expect(find.text('意见反馈已回复'), findsOneWidget);
    expect(find.text('举报处理结果通知'), findsOneWidget);
    expect(find.text('农友 种田的老张 赞了你的帖子'), findsNothing);

    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();

    expect(find.text('农友 农机手阿伟 收藏了你的帖子'), findsOneWidget);
    expect(find.text('意见反馈已回复'), findsNothing);

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

  testWidgets('版块页带有返回按钮且支持下拉刷新', (tester) async {
    final repository = InMemoryForumRepository();
    var refreshed = 0;
    repository.addListener(() => refreshed++);

    await tester.pumpWidget(
      wrap(
        ForumSectionPage(
          section: '农友留言区',
          repository: repository,
        ),
      ),
    );

    expect(find.byTooltip('返回'), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsOneWidget);

    await tester.fling(
      find.byType(ListView),
      const Offset(0, 300),
      1000,
    );
    await tester.pumpAndSettle();

    expect(refreshed, greaterThan(0));
  });

  test('refresh 会通知数据源监听者', () async {
    final repository = InMemoryForumRepository();
    var notified = 0;
    repository.addListener(() => notified++);

    await repository.refresh();

    expect(notified, 1);
  });

  testWidgets('帖子详情展示评论并可发表评论', (tester) async {
    final repository = InMemoryForumRepository();
    final post = repository.postsOf('农友留言区').first;
    final before = repository.commentsOf(post.id).length;

    await tester.pumpWidget(
      wrap(
        ForumPostDetailPage(post: post, repository: repository),
      ),
    );

    expect(find.text(post.title), findsOneWidget);
    expect(find.text('全部评论 $before'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '参数没问题，注意风向');
    await tester.pump();
    await tester.tap(find.byTooltip('发送评论'));
    await tester.pumpAndSettle();

    expect(find.text('参数没问题，注意风向'), findsOneWidget);
    expect(repository.commentsOf(post.id).length, before + 1);
    expect(find.text('全部评论 ${before + 1}'), findsOneWidget);
  });

  testWidgets('详情页收藏按钮切换状态并给出提示', (tester) async {
    final repository = InMemoryForumRepository();
    final post = repository.postsOf('农友留言区').first;

    await tester.pumpWidget(
      wrap(ForumPostDetailPage(post: post, repository: repository)),
    );

    expect(repository.isFavorite(post), isFalse);
    expect(find.text('收藏'), findsOneWidget);

    await tester.tap(find.text('收藏'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(repository.isFavorite(post), isTrue);
    expect(find.text('已收藏'), findsOneWidget);
    expect(find.text('已收藏，可在「我的 - 我的收藏」查看'), findsOneWidget);

    await tester.tap(find.text('已收藏'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(repository.isFavorite(post), isFalse);
    expect(find.text('已取消收藏'), findsOneWidget);

    // 等提示自动消失，避免遗留定时器
    await tester.pumpAndSettle();
  });

  testWidgets('收藏帖子后出现在我的收藏', (tester) async {
    final repository = InMemoryForumRepository();
    final post = repository.postsOf('农友留言区').first;

    await tester.pumpWidget(
      wrap(ForumFavoritesPage(repository: repository)),
    );

    expect(find.text('还没有收藏的帖子'), findsOneWidget);

    repository.toggleFavorite(post);
    await tester.pumpAndSettle();

    expect(repository.isFavorite(post), isTrue);
    expect(find.text(post.title), findsOneWidget);
    expect(find.text('还没有收藏的帖子'), findsNothing);
  });
}
