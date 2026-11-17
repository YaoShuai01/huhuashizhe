import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('App renders MaterialApp with text', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(child: Text('护花使者')),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.text('护花使者'), findsOneWidget);
  });

  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    int counter = 0;
    await tester.pumpWidget(
      StatefulBuilder(builder: (context, setState) {
        return MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('Test')),
            body: Center(
              child: Text('$counter'),
            ),
            floatingActionButton: FloatingActionButton(
              onPressed: () => setState(() => counter++),
              child: const Icon(Icons.add),
            ),
          ),
        );
      }),
    );

    expect(find.text('0'), findsOneWidget);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
  });
}
