import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huhuashizhe/core/accessibility/elder_care_controller.dart';
import 'package:huhuashizhe/core/accessibility/elder_care_reader.dart';
import 'package:huhuashizhe/core/accessibility/elder_care_scope.dart';
import 'package:huhuashizhe/features/mine/pages/mine_page.dart';

void main() {
  testWidgets('长按板块文字朗读整块内容', (tester) async {
    String? spoken;

    await tester.pumpWidget(
      MaterialApp(
        home: ElderCareReader(
          onRead: (text) => spoken = text,
          child: const Scaffold(
            body: Center(
              child: ElderCareBlock(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('农友留言区'),
                    Text('今天飞防作业分享'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('今天飞防作业分享')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pump();

    expect(spoken, '农友留言区\n今天飞防作业分享');
  });

  testWidgets('长按未标记板块时自动朗读所在板块', (tester) async {
    String? spoken;

    await tester.pumpWidget(
      MaterialApp(
        home: ElderCareReader(
          onRead: (text) => spoken = text,
          child: const Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('农友留言区'),
                  Text('今天飞防作业分享'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('今天飞防作业分享')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pump();

    expect(spoken, '农友留言区\n今天飞防作业分享');
  });

  testWidgets('readText 指定朗读文本时忽略其他区域', (tester) async {
    String? spoken;

    await tester.pumpWidget(
      MaterialApp(
        home: ElderCareReader(
          onRead: (text) => spoken = text,
          child: const Scaffold(
            body: Center(
              child: ElderCareBlock(
                readText: '张大哥。如何防治稻飞虱。可以用吡蚜酮。',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('张大哥'),
                    Text('3 分钟前'),
                    Text('如何防治稻飞虱'),
                    Text('12 赞'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('如何防治稻飞虱')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pump();

    expect(spoken, '张大哥。如何防治稻飞虱。可以用吡蚜酮。');
  });

  testWidgets('长按未标记板块的文字只朗读该段', (tester) async {
    String? spoken;

    await tester.pumpWidget(
      MaterialApp(
        home: ElderCareReader(
          onRead: (text) => spoken = text,
          child: const Scaffold(
            body: Center(child: Text('飞防作业交流')),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('飞防作业交流')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pump();

    expect(spoken, '飞防作业交流');
  });

  testWidgets('轻触文字不触发朗读', (tester) async {
    String? spoken;

    await tester.pumpWidget(
      MaterialApp(
        home: ElderCareReader(
          onRead: (text) => spoken = text,
          child: const Scaffold(
            body: Center(child: Text('飞防作业交流')),
          ),
        ),
      ),
    );

    await tester.tap(find.text('飞防作业交流'));
    await tester.pump();

    expect(spoken, isNull);
  });

  testWidgets('长按非文字区域不触发朗读', (tester) async {
    String? spoken;

    await tester.pumpWidget(
      MaterialApp(
        home: ElderCareReader(
          onRead: (text) => spoken = text,
          child: const Scaffold(body: SizedBox.expand()),
        ),
      ),
    );

    final gesture = await tester.startGesture(const Offset(100, 100));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pump();

    expect(spoken, isNull);
  });

  testWidgets('我的页可开关老年关怀模式', (tester) async {
    final controller = ElderCareController(enabled: false);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ElderCareScope(
            controller: controller,
            child: const MinePage(),
          ),
        ),
      ),
    );

    expect(find.text('老年关怀模式'), findsOneWidget);
    expect(controller.enabled, isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(controller.enabled, isTrue);
    expect(find.text('老年关怀模式已开启：长按板块文字即可朗读'), findsOneWidget);
  });
}
