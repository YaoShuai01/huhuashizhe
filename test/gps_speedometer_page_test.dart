import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huhuashizhe/features/speedometer/pages/gps_speedometer_page.dart';

void main() {
  testWidgets('卫星地图页渲染主要元素', (tester) async {
    tester.view.physicalSize = const Size(977, 432);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: GpsSpeedometerPage()),
    );
    await tester.pump();

    expect(find.text('卫星地图'), findsOneWidget);
    expect(find.text('卫星罗盘'), findsOneWidget);
    expect(find.byKey(const Key('locate_button')), findsOneWidget);
    expect(find.text('北斗卫星'), findsOneWidget);
    expect(find.text('GPS'), findsOneWidget);

    // 切到罗盘，确认东南西北罗盘仍在
    await tester.tap(find.text('卫星罗盘'));
    await tester.pump();
    expect(find.text('全部:28'), findsOneWidget);
    expect(find.text('使用:0'), findsOneWidget);
    expect(find.text('北'), findsOneWidget);
    expect(find.text('东'), findsOneWidget);
    expect(find.text('南'), findsOneWidget);
    expect(find.text('西'), findsOneWidget);

    // 定位源切换
    await tester.tap(find.text('GPS'));
    await tester.pump();

    await tester.pumpWidget(const SizedBox());
  });
}
