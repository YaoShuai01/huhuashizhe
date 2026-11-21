import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huhuashizhe/features/speedometer/pages/gps_speedometer_page.dart';

void main() {
  testWidgets('卫星搜星页渲染主要元素', (tester) async {
    tester.view.physicalSize = const Size(977, 432);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: GpsSpeedometerPage()),
    );
    await tester.pump();

    // 顶栏：返回按钮 + 标题
    expect(find.text('北斗 / GPS 搜星'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);

    // 默认进入卫星罗盘视图
    expect(find.text('卫星罗盘'), findsOneWidget);
    expect(find.text('卫星地图'), findsOneWidget);
    expect(find.text('北'), findsOneWidget);
    expect(find.text('东'), findsOneWidget);
    expect(find.text('南'), findsOneWidget);
    expect(find.text('西'), findsOneWidget);

    // 定位与星座切换入口
    expect(find.byKey(const Key('locate_button')), findsOneWidget);
    expect(find.text('北斗卫星'), findsOneWidget);
    expect(find.text('GPS'), findsOneWidget);

    // 切换星座不崩溃
    await tester.tap(find.text('GPS'));
    await tester.pump();

    await tester.pumpWidget(const SizedBox());
  });
}
