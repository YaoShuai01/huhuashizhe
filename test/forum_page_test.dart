import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:huhuashizhe/core/theme/app_theme.dart';
import 'package:huhuashizhe/features/forum/data/forum_models.dart';
import 'package:huhuashizhe/features/forum/data/forum_repository.dart';
import 'package:huhuashizhe/features/forum/forum_scope.dart';
import 'package:huhuashizhe/features/forum/pages/forum_compose_page.dart';
import 'package:huhuashizhe/features/forum/pages/forum_favorites_page.dart';
import 'package:huhuashizhe/features/forum/pages/forum_messages_page.dart';
import 'package:huhuashizhe/features/forum/pages/forum_page.dart';
import 'package:huhuashizhe/features/forum/pages/forum_post_detail_page.dart';
import 'package:huhuashizhe/features/forum/services/forum_moderation_service.dart';
import 'package:huhuashizhe/features/forum/services/forum_voice_input.dart';
import 'package:huhuashizhe/features/forum/widgets/forum_message_bell.dart';
import 'package:huhuashizhe/features/forum/widgets/forum_post_card.dart';
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

  testWidgets('论坛右上角铃铛显示未读数并随已读状态更新', (tester) async {
    final repository = InMemoryForumRepository();

    await tester.pumpWidget(wrap(ForumPage(repository: repository)));

    final unread = repository.messages.where((m) => m.unread).length;
    expect(unread, greaterThan(0));
    expect(
      tester.widget<ForumMessageBell>(find.byType(ForumMessageBell)).unreadCount,
      unread,
    );

    repository.markAllMessagesRead();
    await tester.pump();

    expect(
      tester.widget<ForumMessageBell>(find.byType(ForumMessageBell)).unreadCount,
      0,
    );
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

  test('发帖后进入对应版块与我的帖子', () async {
    final repository = InMemoryForumRepository();
    final before = repository.countOf('新手提问区');

    final post = await repository.publish(
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

  test('点赞与取消点赞来回切换，点赞数不会越点越少', () {
    final post = ForumPost(
      id: 'like_test',
      section: '农友留言区',
      title: '点赞测试',
      content: '点赞测试正文',
      author: '测试用户',
      createdAt: DateTime(2026, 1, 1),
      likes: 5,
    );
    final repository = InMemoryForumRepository(seed: false, posts: [post]);

    repository.toggleLike(post);
    expect(post.likes, 6);

    repository.toggleLike(post);
    expect(post.likes, 5);

    repository.toggleLike(post);
    expect(post.likes, 6);

    repository.toggleLike(post);
    expect(post.likes, 5);
  });

  testWidgets('点赞图标未点赞时为白色空心，点赞后为琥珀橙实心', (tester) async {
    final post = ForumPost(
      id: 'like_color',
      section: '农友留言区',
      title: '点赞颜色',
      content: '正文',
      author: '测试用户',
      createdAt: DateTime(2026, 1, 1),
      likes: 3,
    );
    final repository = InMemoryForumRepository(seed: false, posts: [post]);

    Widget buildCard() => MaterialApp(
          home: Scaffold(
            body: ForumPostCard(
              post: post,
              liked: repository.isLiked(post),
              onLike: () => repository.toggleLike(post),
            ),
          ),
        );

    await tester.pumpWidget(buildCard());
    expect(
      tester.widget<Icon>(find.byIcon(Icons.favorite_border)).color,
      AppColors.textOnPrimary,
    );

    repository.toggleLike(post);
    await tester.pumpWidget(buildCard());
    expect(
      tester.widget<Icon>(find.byIcon(Icons.favorite)).color,
      AppColors.accent,
    );
  });

  testWidgets('帖子详情展示评论并可发表评论', (tester) async {
    final repository = InMemoryForumRepository();
    final post = repository.postsOf('农友留言区').first;
    final before = repository.commentsOf(post.id).length;

    await tester.pumpWidget(
      wrap(
        ForumPostDetailPage(
          post: post,
          repository: repository,
          moderationService: _FakeModerationService(_passResult),
        ),
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

  testWidgets('发送评论时显示加载中，重复点击不会重复提交', (tester) async {
    final repository = InMemoryForumRepository();
    final post = repository.postsOf('农友留言区').first;
    final completer = Completer<ForumAuditResult>();
    final moderator = _DeferredModerationService(completer);
    final before = repository.commentsOf(post.id).length;

    await tester.pumpWidget(
      wrap(
        ForumPostDetailPage(
          post: post,
          repository: repository,
          moderationService: moderator,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '第一下就能发送');
    await tester.pump();

    await tester.tap(find.byTooltip('发送评论'));
    await tester.pump();

    // 审核中按钮变为加载状态，立即给出反馈
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(moderator.calls, 1);

    // 加载中再次点击不会重复提交
    await tester.tap(find.byTooltip('发送评论'), warnIfMissed: false);
    await tester.pump();
    expect(moderator.calls, 1);

    completer.complete(_passResult);
    await tester.pumpAndSettle();

    expect(repository.commentsOf(post.id).length, before + 1);
    expect(find.text('第一下就能发送'), findsOneWidget);
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

  testWidgets('语音输入把识别结果写入评论框', (tester) async {
    final repository = InMemoryForumRepository();
    final post = repository.postsOf('农友留言区').first;
    final voice = _FakeVoiceRecognizer();

    await tester.pumpWidget(
      wrap(
        ForumPostDetailPage(
          post: post,
          repository: repository,
          voiceRecognizer: voice,
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.mic_none));
    await tester.pump();

    expect(voice.started, isTrue);
    expect(find.byIcon(Icons.mic), findsOneWidget);

    voice.emit('这片地需要补喷一次');
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '这片地需要补喷一次');

    await tester.tap(find.byIcon(Icons.mic));
    await tester.pump();

    expect(find.byIcon(Icons.mic_none), findsOneWidget);
  });

  testWidgets('评论支持表情面板插入表情', (tester) async {
    final repository = InMemoryForumRepository();
    final post = repository.postsOf('农友留言区').first;
    final before = repository.commentsOf(post.id).length;

    await tester.pumpWidget(
      wrap(
        ForumPostDetailPage(
          post: post,
          repository: repository,
          moderationService: _FakeModerationService(_passResult),
        ),
      ),
    );

    // 打开表情面板并插入表情
    await tester.tap(find.byTooltip('表情'));
    await tester.pumpAndSettle();
    expect(find.text('😀'), findsOneWidget);

    await tester.tap(find.text('😀'));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '😀');

    // 表情可直接发送
    await tester.tap(find.byTooltip('发送评论'));
    await tester.pumpAndSettle();

    final comments = repository.commentsOf(post.id);
    expect(comments.length, before + 1);
    expect(comments.last.content, '😀');
  });

  test('解析 AI 审核返回的固定 JSON', () {
    final pass = parseModerationResponse(
      '{"audit_result":"通过","reason":"内容正常","violation_type":"无"}',
    );
    expect(pass.verdict, ForumAuditVerdict.pass);
    expect(pass.rejected, isFalse);
    expect(pass.needsManualReview, isFalse);

    final reject = parseModerationResponse(
      '{"audit_result":"驳回","reason":"含外部联系方式","violation_type":"导流营销"}',
    );
    expect(reject.verdict, ForumAuditVerdict.reject);
    expect(reject.violationType, '导流营销');

    final manual = parseModerationResponse(
      '结论如下：\n```json\n'
      '{"audit_result":"待人工复审","reason":"专业内容需人工确认",'
      '"violation_type":"其他违规"}\n```',
    );
    expect(manual.needsManualReview, isTrue);
    expect(manual.reason, '专业内容需人工确认');

    // 非 JSON / 空结果一律转人工复审，不直接放行
    expect(parseModerationResponse('我觉得还行').needsManualReview, isTrue);
    expect(parseModerationResponse('').needsManualReview, isTrue);
  });

  testWidgets('发帖被 AI 驳回时不入库并提示原因', (tester) async {
    final repository = InMemoryForumRepository();
    final moderator = _FakeModerationService(
      const ForumAuditResult(
        verdict: ForumAuditVerdict.reject,
        reason: '正文包含微信联系方式',
        violationType: '导流营销',
      ),
    );
    final section = repository.sectionTitles.first;
    final before = repository.countOf(section);

    final router = _composeRouter(repository, moderator);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.push('/compose');
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '加我微信领补贴');
    await tester.enterText(find.byType(TextField).last, '需要的私聊，微信同号');
    await tester.tap(find.text('发布'));
    await tester.pumpAndSettle();

    expect(moderator.calls, 1);
    expect(find.text('未通过审核'), findsOneWidget);
    expect(find.textContaining('导流营销'), findsOneWidget);
    expect(repository.countOf(section), before);

    await tester.tap(find.text('我知道了'));
    await tester.pumpAndSettle();
  });

  testWidgets('AI 无法判定时帖子标记待人工复审', (tester) async {
    final repository = InMemoryForumRepository();
    final moderator = _FakeModerationService(
      const ForumAuditResult(
        verdict: ForumAuditVerdict.manualReview,
        reason: '专业内容需人工确认',
        violationType: '其他违规',
      ),
    );
    final section = repository.sectionTitles.first;
    const title = '无人机药害补救经验分享';

    final router = _composeRouter(repository, moderator);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.push('/compose');
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, title);
    await tester.enterText(find.byType(TextField).last, '先说结论，再讲过程。');
    await tester.tap(find.text('发布'));
    await tester.pumpAndSettle();

    final post = repository.myPosts.firstWhere((p) => p.title == title);
    expect(post.section, section);
    expect(post.pendingReview, isTrue);
    expect(find.text('已提交，人工复审通过后展示'), findsOneWidget);

    repository.markAllMessagesRead();
    await tester.pumpAndSettle();
  });

  testWidgets('评论被 AI 驳回时不写入', (tester) async {
    final repository = InMemoryForumRepository();
    final post = repository.postsOf('农友留言区').first;
    final before = repository.commentsOf(post.id).length;
    final moderator = _FakeModerationService(
      const ForumAuditResult(
        verdict: ForumAuditVerdict.reject,
        reason: '含人身攻击',
        violationType: '其他违规',
      ),
    );

    await tester.pumpWidget(
      wrap(
        ForumPostDetailPage(
          post: post,
          repository: repository,
          moderationService: moderator,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '你就是个骗子');
    await tester.pump();
    await tester.tap(find.byTooltip('发送评论'));
    await tester.pumpAndSettle();

    expect(moderator.calls, 1);
    expect(find.text('评论未通过审核'), findsOneWidget);
    expect(repository.commentsOf(post.id).length, before);
  });
}

const ForumAuditResult _passResult = ForumAuditResult(
  verdict: ForumAuditVerdict.pass,
  reason: '内容正常',
);

GoRouter _composeRouter(
  InMemoryForumRepository repository,
  ForumModerationService moderator,
) {
  return GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: Text('首页')),
      ),
      GoRoute(
        path: '/compose',
        builder: (context, state) => ForumComposePage(
          repository: repository,
          moderationService: moderator,
        ),
      ),
    ],
  );
}

class _DeferredModerationService implements ForumModerationService {
  _DeferredModerationService(this.completer);

  final Completer<ForumAuditResult> completer;
  int calls = 0;

  @override
  Future<ForumAuditResult> review({
    required String title,
    String content = '',
    String extraText = '',
  }) {
    calls++;
    return completer.future;
  }
}

class _FakeModerationService implements ForumModerationService {
  _FakeModerationService(this.result);

  final ForumAuditResult result;
  int calls = 0;
  String? lastTitle;
  String? lastContent;

  @override
  Future<ForumAuditResult> review({
    required String title,
    String content = '',
    String extraText = '',
  }) async {
    calls++;
    lastTitle = title;
    lastContent = content;
    return result;
  }
}

class _FakeVoiceRecognizer implements ForumVoiceRecognizer {
  bool started = false;
  ValueChanged<String>? _onText;
  ForumVoiceStatusHandler? _onStatus;

  @override
  Future<bool> start({
    required ValueChanged<String> onText,
    required ForumVoiceStatusHandler onStatus,
  }) async {
    started = true;
    _onText = onText;
    _onStatus = onStatus;
    onStatus(ForumVoiceStatus.listening, null);
    return true;
  }

  @override
  Future<void> stop() async {
    _onStatus?.call(ForumVoiceStatus.idle, null);
    _onText = null;
  }

  void emit(String text) => _onText?.call(text);
}
