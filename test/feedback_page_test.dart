import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huhuashizhe/features/forum/data/forum_repository.dart';
import 'package:huhuashizhe/features/mine/pages/mine_sub_pages.dart';

void main() {
  testWidgets('我的反馈提交后写入论坛意见反馈并展示回复状态', (tester) async {
    final repository = InMemoryForumRepository(seed: false);

    await tester.pumpWidget(
      MaterialApp(home: FeedbackPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('我的反馈记录 0 条'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '导出功能希望支持 Excel');
    await tester.tap(find.text('提交反馈'));
    await tester.pumpAndSettle();

    final posts = repository.postsOf('意见反馈');
    expect(posts, hasLength(1));
    expect(posts.single.content, '导出功能希望支持 Excel');
    expect(find.text('我的反馈记录 1 条'), findsOneWidget);
    expect(find.text('待回复'), findsOneWidget);

    await repository.addComment(post: posts.single, content: '已收到，下个版本支持');
    await tester.pumpAndSettle();

    expect(find.text('已回复 1'), findsOneWidget);
  });

  testWidgets('空内容提交会提示并写入', (tester) async {
    final repository = InMemoryForumRepository(seed: false);

    await tester.pumpWidget(
      MaterialApp(home: FeedbackPage(repository: repository)),
    );
    await tester.tap(find.text('提交反馈'));
    await tester.pumpAndSettle();

    expect(find.text('请填写反馈内容'), findsOneWidget);
    expect(repository.postsOf('意见反馈'), isEmpty);
  });
}
