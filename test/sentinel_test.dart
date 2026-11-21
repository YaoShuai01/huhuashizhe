import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:huhuashizhe/features/sentinel/models/sentinel_models.dart';
import 'package:huhuashizhe/features/sentinel/pages/sentinel_page.dart';
import 'package:huhuashizhe/features/sentinel/services/sentinel_service.dart';
import 'package:huhuashizhe/features/services/pages/booking_page.dart';
import 'package:huhuashizhe/providers/sentinel_provider.dart';
import 'package:huhuashizhe/providers/weather_provider.dart';
import 'package:huhuashizhe/services/weather_service.dart';

SentinelService _demoService() => SentinelService(enableServerSync: false);

WeatherData _weather({
  double temp = 22,
  double wind = 2.3,
  int rainProb = 10,
  String location = '孝感市',
}) {
  return WeatherData(
    temperature: temp,
    windSpeed: wind,
    windDirection: 120,
    humidity: 60,
    weatherCode: 0,
    weatherDescription: '晴',
    precipitationProbability: rainProb,
    locationName: location,
  );
}

class FakeWeatherNotifier extends WeatherNotifier {
  final WeatherData data;
  FakeWeatherNotifier(this.data);

  @override
  Future<WeatherData?> build() async => data;
}

FieldPlanting _planting({
  SentinelCrop crop = SentinelCrop.cabbage,
  required int ageDays,
  String id = 'FT-T',
  String location = '测试田',
  int gamePlot = 1,
}) {
  return FieldPlanting(
    id: id,
    crop: crop,
    areaMu: 5,
    location: location,
    plantedAt: DateTime.now().subtract(Duration(days: ageDays)),
    gamePlot: gamePlot,
  );
}

void main() {
  group('生长进度与生育阶段', () {
    test('白菜种下 25 天 → 进度约 42%，处于旺盛生长期', () {
      final p = _planting(ageDays: 25);
      expect(p.daysElapsedAt(DateTime.now()), 25);
      final progress = p.progressAt(DateTime.now());
      expect(progress, closeTo(25 / 60, 0.001));
      expect(p.stageAt(DateTime.now()), GrowthStage.growing);
    });

    test('超过全生育期后进度钳制到 100%，进入成熟收获期', () {
      final p = _planting(crop: SentinelCrop.rice, ageDays: 200);
      expect(p.progressAt(DateTime.now()), 1.0);
      expect(p.stageAt(DateTime.now()), GrowthStage.mature);
    });

    test('生长阶段按进度阈值推进', () {
      expect(GrowthStage.fromProgress(0.1), GrowthStage.seedling);
      expect(GrowthStage.fromProgress(0.5), GrowthStage.growing);
      expect(GrowthStage.fromProgress(0.7), GrowthStage.yieldForming);
      expect(GrowthStage.fromProgress(0.9), GrowthStage.mature);
    });

    test('toJson/fromJson 往返一致', () {
      final p = _planting(ageDays: 10, id: 'FT-X', location: '坡地');
      final restored = FieldPlanting.fromJson(p.toJson());
      expect(restored.id, 'FT-X');
      expect(restored.crop, SentinelCrop.cabbage);
      expect(restored.location, '坡地');
      expect(restored.gamePlot, 1);
      expect(restored.areaMu, 5);
    });
  });

  group('农事规则引擎（该打什么农药）', () {
    test('白菜 25 天命中霜霉病预防窗口，建议百菌清', () {
      final alerts = runAgronomyRules([_planting(ageDays: 25)], DateTime.now());
      expect(alerts.length, 1);
      expect(alerts.first.title, contains('霜霉病'));
      expect(alerts.first.recommendation, contains('百菌清'));
      expect(alerts.first.type, SentinelAlertType.sprayReminder);
    });

    test('油菜 95 天命中花期菌核病（紧急）', () {
      final alerts = runAgronomyRules(
          [_planting(crop: SentinelCrop.rapeseed, ageDays: 95)], DateTime.now());
      expect(alerts.first.title, contains('菌核病'));
      expect(alerts.first.severity, SentinelSeverity.urgent);
      expect(alerts.first.recommendation, contains('菌核净'));
    });

    test('油菜 50 天不命中任何规则（苗期蚜虫窗口是 5-20 天）', () {
      final alerts = runAgronomyRules(
          [_planting(crop: SentinelCrop.rapeseed, ageDays: 50)], DateTime.now());
      expect(alerts, isEmpty);
    });

    test('多种作物多规则并行，预警携带田块与作物信息', () {
      final alerts = runAgronomyRules([
        _planting(ageDays: 25, id: 'FT-A', location: '东田'),
        _planting(crop: SentinelCrop.rice, ageDays: 80, id: 'FT-B'),
      ], DateTime.now());
      expect(alerts.length, 2);
      expect(alerts.any((a) => a.title.contains('霜霉病')), isTrue);
      expect(alerts.any((a) => a.title.contains('稻瘟病')), isTrue);
      expect(
          alerts.firstWhere((a) => a.fieldId == 'FT-A').message, contains('东田'));
    });
  });

  group('天气哨（寒潮/大风/降雨）', () {
    test('气温 ≤5°C 触发寒潮预警（紧急），建议区分作物防寒', () {
      final alerts = runWeatherRules(
        temperature: 3,
        windSpeed: 2,
        precipitationProbability: 10,
        now: DateTime.now(),
        hasPlantings: true,
        locationName: '孝感市',
      );
      expect(alerts.length, 1);
      expect(alerts.first.type, SentinelAlertType.coldWave);
      expect(alerts.first.severity, SentinelSeverity.urgent);
      expect(alerts.first.recommendation, contains('防寒膜'));
    });

    test('风速 >5.4 m/s 触发大风预警', () {
      final alerts = runWeatherRules(
        temperature: 20,
        windSpeed: 6.5,
        precipitationProbability: 10,
        now: DateTime.now(),
        hasPlantings: true,
      );
      expect(alerts.first.type, SentinelAlertType.highWind);
      expect(alerts.first.message, contains('漂移'));
    });

    test('降雨概率 >60% 触发降雨预警', () {
      final alerts = runWeatherRules(
        temperature: 20,
        windSpeed: 2,
        precipitationProbability: 75,
        now: DateTime.now(),
        hasPlantings: true,
      );
      expect(alerts.first.type, SentinelAlertType.heavyRain);
    });

    test('天气正常不产生预警', () {
      final alerts = runWeatherRules(
        temperature: 22,
        windSpeed: 2.3,
        precipitationProbability: 10,
        now: DateTime.now(),
        hasPlantings: true,
      );
      expect(alerts, isEmpty);
    });

    test('没有登记田块时不告警（哨兵不空转）', () {
      final alerts = runWeatherRules(
        temperature: 3,
        windSpeed: 8,
        precipitationProbability: 90,
        now: DateTime.now(),
        hasPlantings: false,
      );
      expect(alerts, isEmpty);
    });
  });

  group('端侧病虫害识别联动（哨兵的眼睛）', () {
    test('菜青虫危害 → 生成病虫害预警 + 用药建议', () {
      final alert = alertFromModelPestLabel(
        pestLabel: '菜青虫危害',
        location: '朋兴乡丹阳村',
        now: DateTime.now(),
      );
      expect(alert, isNotNull);
      expect(alert!.type, SentinelAlertType.pestRisk);
      expect(alert.recommendation, contains('苏云金杆菌'));
    });

    test('霜霉病 → 紧急预警', () {
      final alert = alertFromModelPestLabel(
        pestLabel: '霜霉病',
        location: '测试田',
        now: DateTime.now(),
      );
      expect(alert!.severity, SentinelSeverity.urgent);
    });

    test('健康标签不告警', () {
      final alert = alertFromModelPestLabel(
        pestLabel: '健康',
        location: '测试田',
        now: DateTime.now(),
      );
      expect(alert, isNull);
    });
  });

  group('田哨服务（演示模式，无网络依赖）', () {
    test('loadData 灌入 2 块演示田并生成打药提醒', () async {
      final service = _demoService();
      await service.loadData();
      expect(service.plantings.length, 2);
      expect(service.usingDemoData, isTrue);
      // 白菜 25 天 → 霜霉病；油菜 95 天 → 菌核病
      expect(service.alerts.length, 2);
      expect(service.syncedPlotCount, 2);
    });

    test('登记种植 → 分配云游戏田块 → 命中规则即提醒', () async {
      final service = _demoService();
      await service.loadData();
      final p = service.registerPlanting(
        crop: SentinelCrop.cabbage,
        areaMu: 3,
        location: '测试新田',
        plantedAt: DateTime.now().subtract(const Duration(days: 25)),
      );
      expect(p.gamePlot, 3);
      expect(service.syncedPlotCount, 3);
      final alert = service.alerts
          .firstWhere((a) => a.fieldId == p.id, orElse: () => throw Exception('no alert'));
      expect(alert.title, contains('霜霉病'));
    });

    test('天气评估去重：同一规则同一天只提醒一次', () async {
      final service = _demoService();
      await service.loadData();
      service.evaluateWeather(_weather(temp: 2));
      service.evaluateWeather(_weather(temp: 2));
      final coldCount = service.alerts
          .where((a) => a.type == SentinelAlertType.coldWave)
          .length;
      expect(coldCount, 1);
    });

    test('演示寒潮：一键触发，每块田一条预警', () async {
      final service = _demoService();
      await service.loadData();
      service.triggerDemoColdWave();
      final coldAlerts = service.alerts
          .where((a) => a.title.contains('寒潮'))
          .toList();
      expect(coldAlerts.length, 2);
      expect(coldAlerts.first.severity, SentinelSeverity.urgent);
    });

    test('已知了的预警排在未处理后面，标记后计入已处理', () async {
      final service = _demoService();
      await service.loadData();
      expect(service.unhandledAlertCount, 2);
      final first = service.alerts.first;
      service.handleAlert(first.id);
      expect(service.unhandledAlertCount, 1);
      expect(service.alerts.last.handled, isTrue);
    });

    test('端侧识别结果接入服务', () async {
      final service = _demoService();
      await service.loadData();
      final ok = service.reportPestFromModel(
        pestLabel: '菜青虫危害',
        location: '朋兴乡丹阳村',
      );
      expect(ok, isTrue);
      expect(service.unhandledAlertCount, 3);
      expect(
        service.alerts.any((a) => a.type == SentinelAlertType.pestRisk),
        isTrue,
      );
      expect(
        service.reportPestFromModel(
            pestLabel: '健康', location: '朋兴乡'),
        isFalse,
      );
    });
  });

  group('田哨中心页（widget）', () {
    Widget wrap(Widget child, {WeatherData? weather}) {
      return ProviderScope(
        overrides: [
          sentinelServiceProvider.overrideWith((ref) => _demoService()),
          // 始终注入假天气：避免真实天气源在测试里发起网络请求
          weatherProvider
              .overrideWith(() => FakeWeatherNotifier(weather ?? _weather())),
        ],
        child: MaterialApp(home: child),
      );
    }

    testWidgets('展示云田同步卡、预警与田块进度', (tester) async {
      await tester.pumpWidget(wrap(const SentinelPage()));
      await tester.pumpAndSettle();

      expect(find.text('田哨预警'), findsWidgets);
      // 同步卡的"N 块实地田已同步至云种植游戏"（每块田卡片底部还有同源文案）
      expect(find.textContaining('块实地田已同步至云种植游戏'), findsOneWidget);
      expect(find.textContaining('霜霉病预防窗口'), findsOneWidget);
      expect(find.textContaining('花期菌核病'), findsOneWidget);
      expect(find.textContaining('朋兴乡丹阳村 1 号地'), findsOneWidget);
      expect(find.text('登记种植'), findsOneWidget);
    });

    testWidgets('天气寒冷 → 自动生成寒潮预警卡', (tester) async {
      await tester.pumpWidget(wrap(
        const SentinelPage(),
        weather: _weather(temp: 2),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('寒潮来袭'), findsOneWidget);
      expect(find.text('紧急'), findsWidgets);
    });

    testWidgets('点击"演示寒潮"→ 每块田生成寒潮预警；点"知道了"→ 标记已处理', (tester) async {
      await tester.pumpWidget(wrap(const SentinelPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.bolt));
      await tester.pumpAndSettle();
      expect(find.textContaining('寒潮预警（演示）'), findsNWidgets(2));

      await tester.tap(find.text('知道了').first);
      await tester.pumpAndSettle();
      // 已处理的卡按排序沉到列表尾部，ListView 懒加载需滚动到可见
      await tester.dragUntilVisible(
        find.text('已处理'),
        find.byType(ListView).first,
        const Offset(0, -200),
      );
      expect(find.text('已处理'), findsOneWidget);
    });

    testWidgets('登记种植：填表 → 提交 → 田块列表新增', (tester) async {
      await tester.pumpWidget(wrap(const SentinelPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('登记种植'));
      await tester.pumpAndSettle();
      expect(find.text('登记实地种植'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextFormField, '种植亩数'), '3');
      await tester.enterText(
          find.widgetWithText(TextFormField, '地块位置'), '测试新田');
      await tester.tap(find.text('登记并同步云种植'));
      // 弹层收起 + SnackBar 4 秒计时器走完，避免测试结束时残留 Timer
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // 新田块排在列表尾部，ListView 懒加载需滚动到可见
      await tester.dragUntilVisible(
        find.textContaining('测试新田'),
        find.byType(ListView).first,
        const Offset(0, -200),
      );
      expect(find.textContaining('测试新田'), findsWidgets);
    });

    testWidgets('登记种植：空表单校验拦截', (tester) async {
      await tester.pumpWidget(wrap(const SentinelPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('登记种植'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('登记并同步云种植'));
      await tester.pumpAndSettle();

      expect(find.text('请输入有效的亩数'), findsOneWidget);
      expect(find.text('请填写地块位置'), findsOneWidget);
    });

    testWidgets('打药提醒"预约飞防" → 跳到预约飞防表单', (tester) async {
      final router = GoRouter(
        initialLocation: '/sentinel',
        routes: [
          GoRoute(
            path: '/sentinel',
            builder: (_, __) => const SentinelPage(),
          ),
          GoRoute(
            path: '/services/booking/farmer',
            builder: (_, __) => const BookingPage(),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sentinelServiceProvider.overrideWith((ref) => _demoService()),
            weatherProvider
                .overrideWith(() => FakeWeatherNotifier(_weather())),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('预约飞防').first);
      await tester.pumpAndSettle();

      // 已进入预约飞防表单页
      expect(find.text('无人机植保预约'), findsOneWidget);
      expect(find.text('选择飞手'), findsOneWidget);
      // 提交按钮在表单底部（视口外），滚动到可见再断言
      await tester.dragUntilVisible(
        find.text('提交预约'),
        find.byType(ListView).last,
        const Offset(0, -300),
      );
      expect(find.text('提交预约'), findsOneWidget);
    });
  });
}
