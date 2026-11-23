import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huhuashizhe/core/layout/tablet_layout.dart';
import 'package:huhuashizhe/data/local_database.dart';
import 'package:huhuashizhe/features/settings/pages/settings_page.dart';
import 'package:huhuashizhe/providers/tablet_layout_provider.dart';

void main() {
  group('LayoutScope.useTablet 判定', () {
    Future<bool> evaluate(
      WidgetTester tester, {
      required bool enabled,
      required Size size,
      bool withScope = true,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      late bool result;
      final probe = Builder(builder: (context) {
        result = LayoutScope.useTablet(context);
        return const SizedBox();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: withScope
              ? LayoutScope(enabled: enabled, child: probe)
              : probe,
        ),
      );
      return result;
    }

    testWidgets('横屏大屏 + 开关开 → 平板布局', (tester) async {
      expect(
        await evaluate(tester, enabled: true, size: const Size(1280, 800)),
        isTrue,
      );
    });

    testWidgets('竖屏大屏 → 手机布局', (tester) async {
      expect(
        await evaluate(tester, enabled: true, size: const Size(800, 1280)),
        isFalse,
      );
    });

    testWidgets('开关关闭 → 手机布局', (tester) async {
      expect(
        await evaluate(tester, enabled: false, size: const Size(1280, 800)),
        isFalse,
      );
    });

    testWidgets('手机横屏（780x360）→ 手机布局', (tester) async {
      expect(
        await evaluate(tester, enabled: true, size: const Size(780, 360)),
        isFalse,
      );
    });

    testWidgets('没有 LayoutScope 时默认关闭', (tester) async {
      expect(
        await evaluate(
          tester,
          enabled: true,
          size: const Size(1280, 800),
          withScope: false,
        ),
        isFalse,
      );
    });
  });

  group('设置页平板布局开关', () {
    testWidgets('默认关闭，点击后写入本地并开启', (tester) async {
      final db = LocalDatabase();
      db.setBool(TabletLayoutNotifier.key, false);
      addTearDown(() => db.setBool(TabletLayoutNotifier.key, false));

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: SettingsPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('平板布局'), findsOneWidget);
      final tile = find.widgetWithText(SwitchListTile, '平板布局');
      expect(tester.widget<SwitchListTile>(tile).value, isFalse);

      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(db.getBool(TabletLayoutNotifier.key), isTrue);
      expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    });
  });
}
