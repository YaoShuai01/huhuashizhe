import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huhuashizhe/core/accessibility/elder_care_controller.dart';
import 'package:huhuashizhe/core/accessibility/elder_care_scope.dart';
import 'package:huhuashizhe/core/accessibility/elder_care_tap_reader.dart';
import 'package:huhuashizhe/features/mine/pages/mine_page.dart';

void main() {
  testWidgets('轻触文字触发朗读回调', (tester) async {
    String? spoken;

    await tester.pumpWidget(
      MaterialApp(
        home: ElderCareTapReader(
          onRead: (text) => spoken = text,
          child: const Scaffold(
            body: Center(child: Text('飞防作业交流')),
          ),
        ),
      ),
    );

    await tester.tap(find.text('飞防作业交流'));
    await tester.pump();

    expect(spoken, '飞防作业交流');
  });

  testWidgets('轻触非文字区域不触发朗读', (tester) async {
    String? spoken;

    await tester.pumpWidget(
      MaterialApp(
        home: ElderCareTapReader(
          onRead: (text) => spoken = text,
          child: const Scaffold(body: SizedBox.expand()),
        ),
      ),
    );

    await tester.tapAt(const Offset(100, 100));
    await tester.pump();

    expect(spoken, isNull);
  });

  testWidgets('我的页可开关老年关怀模式', (tester) async {
    final controller = ElderCareController(enabled: false);

    await tester.pumpWidget(
      MaterialApp(
        home: ElderCareScope(
          controller: controller,
          child: const MinePage(),
        ),
      ),
    );

    expect(find.text('老年关怀模式'), findsOneWidget);
    expect(controller.enabled, isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(controller.enabled, isTrue);
    expect(find.text('老年关怀模式已开启：轻触文字即可朗读'), findsOneWidget);
  });
}
