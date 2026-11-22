import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local_database.dart';
import '../../../services/gps_location_service.dart';
import '../models/cloud_models.dart';
import 'cloud_engine.dart';
import 'cloud_weather_service.dart';

/// 定位结果（失败时给出可展示的原因）
class CloudLocateResult {
  final bool ok;
  final String? message;

  const CloudLocateResult._(this.ok, this.message);

  const CloudLocateResult.success([String? message]) : this._(true, message);

  const CloudLocateResult.failure(String message) : this._(false, message);
}

/// 云种植状态管理（本地持久化 key: cloud_farm_v1）
class CloudFarmController extends ChangeNotifier {
  static const String storageKey = 'cloud_farm_v1';
  static const String guideSeenKey = 'cloud_farm_guide_seen_v1';

  late CloudState state;
  final LocalDatabase _db = LocalDatabase();
  final CloudWeatherService _weatherService = CloudWeatherService();

  CloudFarmController() {
    _load();
    if (!state.location.isSeed) {
      unawaited(refreshWeather());
    }
  }

  bool _loaded = false;
  bool get loaded => _loaded;

  bool _locating = false;
  bool get locating => _locating;

  bool _refreshingWeather = false;
  bool get refreshingWeather => _refreshingWeather;

  String? _lastLocateError;
  String? get lastLocateError => _lastLocateError;

  String? _weatherError;
  String? get weatherError => _weatherError;

  CloudLocation get location => state.location;

  CloudWeatherSnapshot? get weather => state.weather;

  bool get guideSeen => _db.getBool(guideSeenKey);

  void markGuideSeen() {
    if (!guideSeen) _db.setBool(guideSeenKey, true);
  }

  /// 重新获取 GPS 定位并反查地名，失败时返回可展示的原因
  Future<CloudLocateResult> locate() async {
    if (_locating) {
      return const CloudLocateResult.failure('定位进行中，请稍候');
    }
    _locating = true;
    _lastLocateError = null;
    notifyListeners();
    try {
      GpsLocation? gps;
      try {
        gps = await GpsLocationService.getCurrentLocation()
            .timeout(const Duration(seconds: 15));
      } on TimeoutException {
        return _failLocate('定位超时，请到空旷处重试或手动修改位置');
      } catch (e) {
        debugPrint('cloud farm locate failed: $e');
        return _failLocate('定位不可用，请检查定位权限与 GPS 是否开启');
      }
      if (gps == null || gps.lat == 0 || gps.lng == 0) {
        return _failLocate('未获取到定位，请确认已开启定位权限与 GPS');
      }
      String? geo;
      try {
        geo = await GpsLocationService.reverseGeocode(gps.lat, gps.lng)
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        geo = null;
      }
      final name = (geo != null && geo.trim().isNotEmpty)
          ? geo.trim()
          : '已定位（${gps.lat.toStringAsFixed(4)}, ${gps.lng.toStringAsFixed(4)}）';
      state.location = CloudLocation(
        lat: gps.lat,
        lng: gps.lng,
        name: name,
        accuracy: gps.accuracy > 0 ? gps.accuracy : null,
        source: 'gps',
        updatedAt: DateTime.now(),
      );
      _save();
      unawaited(refreshWeather());
      return CloudLocateResult.success('已定位：$name');
    } finally {
      _locating = false;
      notifyListeners();
    }
  }

  CloudLocateResult _failLocate(String message) {
    _lastLocateError = message;
    return CloudLocateResult.failure(message);
  }

  /// 手动修改位置（经纬度 + 可选名称）
  void setManualLocation({
    required double lat,
    required double lng,
    String? name,
  }) {
    final custom = (name ?? '').trim();
    state.location = CloudLocation(
      lat: lat,
      lng: lng,
      name: custom.isEmpty
          ? '手动位置（${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}）'
          : custom,
      accuracy: null,
      source: 'manual',
      updatedAt: DateTime.now(),
    );
    _lastLocateError = null;
    _save();
    notifyListeners();
    unawaited(refreshWeather());
  }

  /// 刷新真实天气（中国天气网实况 + 预报）
  /// 失败时保留上一份快照并标记 offline，不生成任何假预报。
  Future<bool> refreshWeather() async {
    if (_refreshingWeather) return false;
    final loc = state.location;
    if (loc.isSeed) {
      _weatherError = '未定位，天气暂不可用';
      notifyListeners();
      return false;
    }

    _refreshingWeather = true;
    _weatherError = null;
    notifyListeners();
    try {
      final result = await _weatherService.fetch(
        lat: loc.lat,
        lng: loc.lng,
        locationName: loc.name,
      );
      final snapshot = result.snapshot;
      if (snapshot != null) {
        state.weather = snapshot;
        _weatherError = null;
        _save();
        return true;
      }
      _weatherError = result.error ?? '天气获取失败，请检查网络';
      final previous = state.weather;
      if (previous != null) {
        state.weather = previous.copyWith(offline: true);
        _save();
      }
      return false;
    } catch (e) {
      debugPrint('cloud weather refresh failed: $e');
      _weatherError = '天气获取失败，请检查网络';
      final previous = state.weather;
      if (previous != null) {
        state.weather = previous.copyWith(offline: true);
        _save();
      }
      return false;
    } finally {
      _refreshingWeather = false;
      notifyListeners();
    }
  }

  void _load() {
    try {
      final raw = _db.get(storageKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final parsed = CloudState.fromJson(decoded);
          if (parsed.plots.isNotEmpty) {
            state = parsed;
            _loaded = true;
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('cloud farm load failed: $e');
    }
    state = CloudSeed.seedState();
    _loaded = true;
    _save();
  }

  void _save() {
    try {
      _db.set(storageKey, jsonEncode(state.toJson()));
    } catch (e) {
      debugPrint('cloud farm save failed: $e');
    }
  }

  void reset() {
    state = CloudSeed.seedState();
    _save();
    notifyListeners();
  }

  /// 下拉刷新：重新获取真实天气并按当前时间重算墒情与长势
  Future<void> refresh() async {
    await refreshWeather();
    notifyListeners();
  }

  // ---------- 查询 ----------
  List<CloudPlot> get plots => state.plots;

  CloudPlot? plotById(String? id) {
    if (id == null) return null;
    for (final p in state.plots) {
      if (p.id == id) return p;
    }
    return null;
  }

  GrowthInfo? growth(CloudPlot? plot) =>
      plot == null ? null : CloudEngine.growth(plot);

  MoistureInfo moisture(CloudPlot plot) =>
      CloudEngine.moisture(plot, weather: state.weather);

  WaterAdvice waterAdvice(CloudPlot plot) =>
      CloudEngine.waterAdvice(moisture(plot), state.settings.moistureThreshold);

  List<CloudAlert> get alerts => CloudEngine.alerts(state);

  List<CloudAlert> alertsFor(String plotId) =>
      alerts.where((a) => a.plotId == plotId).toList();

  double get totalArea => state.plots.fold(0, (s, p) => s + p.area);

  int get plantedCount => state.plots.where((p) => p.cropId != null).length;

  List<CloudPlot> get plantedPlots =>
      state.plots.where((p) => p.cropId != null).toList();

  // ---------- 田块 ----------
  CloudPlot addPlot({
    required String name,
    required List<List<double>> polygon,
    required double area,
    required String soil,
    required String irrigation,
  }) {
    final now = DateTime.now();
    final plot = CloudPlot(
      id: 'p${now.millisecondsSinceEpoch.toRadixString(36)}',
      name: name,
      cropId: null,
      area: (area * 10).round() / 10,
      plantedAt: null,
      polygon: polygon,
      soil: soil,
      irrigation: irrigation,
      fertilizer: '未施肥',
      lastWaterAt: now,
      lastFertAt: now,
      lastCalibratedAt: now,
      lastPestAt: null,
      lastSensedAt: now,
      buildSource: 'GPS 圈地',
      logs: [
        PlotLog(
          t: now,
          type: 'build',
          title: '完成田块圈地建模',
          desc: 'GPS 边界 ${area.toStringAsFixed(1)} 亩，等待选择作物',
        ),
      ],
    );
    state.plots.add(plot);
    _save();
    notifyListeners();
    return plot;
  }

  /// 应用种植方案
  void applyPlanting({
    required CloudPlot plot,
    required CropInfo crop,
    required String soil,
    required String irrigation,
    required String fertilizer,
    required DateTime sow,
    required String fertAge,
    required int score,
  }) {
    final now = DateTime.now();
    plot
      ..cropId = crop.id
      ..plantedAt = sow
      ..soil = soil
      ..irrigation = irrigation
      ..fertilizer = fertilizer
      ..lastWaterAt = now
      ..lastFertAt = CloudEngine.fertDate(fertAge, now)
      ..lastCalibratedAt = now
      ..harvested = false
      ..pctOffset = 0;
    plot.logs.insert(
      0,
      PlotLog(
        t: now,
        type: 'plant',
        title: '完成云种植建档',
        desc:
            '${crop.name} ${crop.variety}，${plot.area.toStringAsFixed(1)} 亩，${plot.buildSource}，AI 适宜度 $score 分',
      ),
    );
    _save();
    notifyListeners();
  }

  // ---------- 农事操作 ----------
  void waterPlot(CloudPlot plot, {String? desc}) {
    final now = DateTime.now();
    plot.lastWaterAt = now;
    plot.logs.insert(
      0,
      PlotLog(
        t: now,
        type: 'water',
        title: '执行灌溉',
        desc: desc ?? '${CloudSeed.irrigationOf(plot.irrigation).name} 15m³/亩，AI 提醒后执行',
      ),
    );
    _save();
    notifyListeners();
  }

  void fertilizerPlot(CloudPlot plot, {String? desc}) {
    final now = DateTime.now();
    plot.lastFertAt = now;
    plot.logs.insert(
      0,
      PlotLog(
        t: now,
        type: 'fert',
        title: '记录施肥',
        desc: desc ?? '${plot.fertilizer} · 按 AI 阶段建议执行',
      ),
    );
    _save();
    notifyListeners();
  }

  void markPest(CloudPlot plot) {
    final now = DateTime.now();
    plot.lastPestAt = now;
    plot.logs.insert(
      0,
      PlotLog(t: now, type: 'pest', title: '完成植保作业', desc: '抢晴喷药，记录已同步'),
    );
    _save();
    notifyListeners();
  }

  void harvest(CloudPlot plot) {
    final now = DateTime.now();
    plot.harvested = true;
    plot.logs.insert(
      0,
      PlotLog(
        t: now,
        type: 'harvest',
        title: '完成采收',
        desc: '云田进度 100%，${plot.area.toStringAsFixed(1)} 亩',
      ),
    );
    _save();
    notifyListeners();
  }

  void addNote(CloudPlot plot, String text) {
    final now = DateTime.now();
    plot.logs.insert(
      0,
      PlotLog(
        t: now,
        type: 'note',
        title: '现场记录',
        desc: text.trim().isEmpty ? '实体田块巡查记录' : text.trim(),
      ),
    );
    _save();
    notifyListeners();
  }

  /// 保存 / 移除田块实景照片（只记录本机路径，不上传）
  void setPlotPhoto(String plotId, String? path) {
    final plot = plotById(plotId);
    if (plot == null) return;
    final trimmed = path?.trim();
    plot.photoPath =
        (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    _save();
    notifyListeners();
  }

  void calibrate(CloudPlot plot, int value) {
    final now = DateTime.now();
    plot
      ..pctOffset = value.toDouble()
      ..lastCalibratedAt = now;
    plot.logs.insert(
      0,
      PlotLog(
        t: now,
        type: 'sync',
        title: '实体长势校准',
        desc: value == 0
            ? '拍照比对，云田与实体一致'
            : '拍照比对，修正长势偏差 ${value > 0 ? '+' : ''}$value%',
      ),
    );
    _save();
    notifyListeners();
  }

  void recordRemoteShot(CloudPlot plot) {
    final now = DateTime.now();
    plot.lastSensedAt = now;
    plot.logs.insert(
      0,
      PlotLog(
        t: now,
        type: 'note',
        title: '异地拍照记录',
        desc: '农户远程拍摄田块照片，AI 比对叶色与密度',
      ),
    );
    _save();
    notifyListeners();
  }

  void completePatrol(CloudPlot plot) {
    final now = DateTime.now();
    plot
      ..lastSensedAt = now
      ..lastCalibratedAt = now;
    plot.logs.insert(
      0,
      PlotLog(
        t: now,
        type: 'sync',
        title: '无人机巡田',
        desc: '5 点采样影像比对完成，云田长势与实体同步',
      ),
    );
    _save();
    notifyListeners();
  }

  /// 处理提醒（校准类由页面打开校准弹层）
  void handleAlert(CloudAlert alert) {
    final plot = plotById(alert.plotId);
    if (plot == null) return;
    switch (alert.type) {
      case 'water':
        waterPlot(plot, desc: '按提醒傍晚灌溉 15m³/亩');
        break;
      case 'fert':
        fertilizerPlot(plot, desc: '按 AI 阶段建议施肥');
        break;
      case 'pest':
        markPest(plot);
        break;
      case 'harvest':
        harvest(plot);
        break;
    }
  }

  void snooze(String alertId) {
    state.snoozed[alertId] = DateTime.now().add(const Duration(days: 1));
    _save();
    notifyListeners();
  }

  void saveSettings({int? threshold, int? calibrateDays, int? remindHour}) {
    if (threshold != null) state.settings.moistureThreshold = threshold;
    if (calibrateDays != null) state.settings.calibrateDays = calibrateDays;
    if (remindHour != null) state.settings.remindHour = remindHour;
    _save();
    notifyListeners();
  }

  // ---------- AI 助手 ----------
  List<CloudChatMessage> get chat => state.chat;

  void ensureAssistantGreeting() {
    if (state.chat.isNotEmpty) return;
    state.chat.add(CloudChatMessage(role: 'ai', text: greetingText(), t: DateTime.now()));
    _save();
  }

  String greetingText() {
    final planted = plantedPlots;
    final al = alerts;
    final humidity = state.weather?.humidity;
    return '你好，我是云种植 AI 助手。已接入 GPS 天气、田块边界、墒情模型与农事记录。\n'
        '在线田块 ${planted.length} 块 · 待办提醒 ${al.length} 项 · '
        '${humidity == null ? '真实天气暂未获取' : '空气湿度 $humidity%'}\n'
        '可以问我：今天要不要浇水、什么时候施肥、作物长到哪个阶段。\n'
        '所有回答基于当前数据实时计算。';
  }

  void sendChat(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    state.chat.add(CloudChatMessage(role: 'me', text: t, t: DateTime.now()));
    _save();
    notifyListeners();
    Future.delayed(const Duration(milliseconds: 650), () {
      state.chat.add(
        CloudChatMessage(role: 'ai', text: aiReply(t), t: DateTime.now()),
      );
      _save();
      notifyListeners();
    });
  }

  String aiReply(String q) {
    final text = q.toLowerCase();
    if (RegExp('浇水|灌溉|墒情|湿度|干旱').hasMatch(text)) return _replyWater();
    if (RegExp('施肥|追肥|肥料|硼').hasMatch(text)) return _replyFert();
    if (RegExp('天气|降雨|下雨|温度|风').hasMatch(text)) return _replyWeather();
    if (RegExp('长势|进度|阶段|成熟|收获|长得').hasMatch(text)) return _replyGrowth();
    if (RegExp('提醒|待办|要做|农事').hasMatch(text)) return _replyAlerts();
    if (RegExp('种什么|作物|推荐|几熟|轮作|品种').hasMatch(text)) return _replyCrops();
    if (RegExp('异地|远程|查看|巡田|无人机|摄像头').hasMatch(text)) return _replyRemote();
    final humidity = state.weather?.humidity;
    return '我可以结合当前数据回答农事问题。目前有 ${state.plots.length} 块田、${alerts.length} 项待办，'
        '${humidity == null ? '真实天气暂未获取' : '空气湿度 $humidity%'}。\n'
        '试试问我：今天要浇水吗？什么时候施肥？作物长到哪个阶段？';
  }

  String _replyWater() {
    final planted = plantedPlots;
    if (planted.isEmpty) return '目前还没有已种植的田块。可以先去「圈地建模」，再按向导选择作物。';
    final sorted = [...planted]
      ..sort((a, b) => moisture(a).value.compareTo(moisture(b).value));
    final low = sorted.first;
    final m = moisture(low);
    final adv = waterAdvice(low);
    final items = sorted
        .take(3)
        .map((p) => '${p.name}：${moisture(p).value}%')
        .join(' · ');
    return '按 GPS 天气、${m.soil.name}基础值、${m.daysSince.floor()} 天灌溉记录推算：\n'
        '$items\n'
        '${adv.text}\n'
        '${adv.tone == CloudTone.green ? '当前墒情适宜，无需灌溉' : '优先处理「${low.name}」，执行后记得记录灌溉'}';
  }

  String _replyFert() {
    final planted = plantedPlots;
    if (planted.isEmpty) return '还没有已种植的田块，生成云种植模型后才有阶段施肥建议。';
    CloudPlot? target;
    for (final p in planted) {
      final g = growth(p);
      if (g != null &&
          g.idx >= 3 &&
          g.idx <= 5 &&
          CloudEngine.daysBetween(p.lastFertAt, DateTime.now()) > 20) {
        target = p;
        break;
      }
    }
    target ??= planted.first;
    final g = growth(target)!;
    final plan = _fertPlan(g.idx);
    final days = CloudEngine.daysBetween(target.lastFertAt, DateTime.now()).floor();
    final rain48 = state.weather?.forecastRainAt(2);
    return '「${target.name}」处于${g.stage.name}期（第 ${g.day} 天），距上次施肥 $days 天。\n'
        '建议${plan.$1}：${plan.$2}。${plan.$3}。\n'
        '${rain48 == null ? '暂未获取到未来 48 小时预报，建议结合当地天气安排施肥。' : '未来 48h 降水概率 $rain48%，建议雨前 1 天或雨后抢晴施用。'}';
  }

  (String, String, String) _fertPlan(int idx) {
    if (idx == 3) return ('提苗肥', '尿素 5kg/亩', '幼苗 3—5 叶期促根壮苗');
    if (idx == 4) return ('薹肥', '尿素 8kg/亩 + 氯化钾 3kg/亩', '蕾薹期是需肥高峰');
    if (idx == 5) return ('叶面硼肥', '0.2% 硼砂 30kg/亩', '花期补硼防花而不实');
    return ('平衡追肥', '复合肥 10kg/亩', '维持长势，按叶色调整');
  }

  String _replyWeather() {
    final w = state.weather;
    if (w == null) {
      return '暂未获取到真实天气数据。请确认已定位并联网，然后在农场页下拉刷新。';
    }
    final f = w.forecast;
    final rain48 = w.forecastRainAt(2);
    final forecastText = f.length >= 2
        ? '${f[1].label}降水 ${f[1].rain}%${f.length >= 3 ? ' · ${f[2].label}降水 ${f[2].rain}%' : ''}'
        : '暂无逐日预报数据';
    final advice = rain48 == null
        ? '暂未获取到 48 小时预报，建议结合当地实况安排灌溉与施肥。'
        : (rain48 >= 60
            ? '48 小时内降雨概率较高，建议暂缓灌溉；追肥抢在雨前完成，雨后及时复测墒情。'
            : '近期降水偏少，可按阶段需水小水勤浇，优先傍晚作业。');
    return '${location.name.isEmpty ? '当前位置' : location.name} 当前 ${w.temp.round()}℃，${w.desc}，'
        '空气湿度 ${w.humidity}%，${w.windDir} ${w.wind}m/s。\n'
        '$forecastText\n'
        '$advice';
  }

  String _replyGrowth() {
    final planted = plantedPlots;
    if (planted.isEmpty) return '暂无在线作物。去「新种植」选择作物后，云田会从播种日开始逐日推进。';
    final items = planted
        .take(3)
        .map((p) => '${p.name}：${growth(p)!.pct.round()}%')
        .join(' · ');
    final sorted = [...planted]
      ..sort((a, b) => growth(b)!.pct.compareTo(growth(a)!.pct));
    final top = sorted.first;
    final g = growth(top)!;
    return '云田按实体播种日期同步推进，当前进度：\n$items\n'
        '「${top.name}」已进入${g.stage.name}期，第 ${g.day} 天，距${g.next?.name ?? '成熟'}约 ${g.daysToNext} 天。\n'
        '拍照或无人机巡田可校准云田与实体的长势偏差。';
  }

  String _replyAlerts() {
    final al = alerts;
    if (al.isEmpty) return '目前没有待办提醒，墒情与长势都在适宜区间。我会按天气变化持续监测。';
    final lines = al
        .take(3)
        .toList()
        .asMap()
        .entries
        .map((e) => '${e.key + 1}. ${e.value.title}（${e.value.window}）')
        .join('\n');
    return '当前共 ${al.length} 项农事提醒，优先处理：\n$lines\n打开「提醒」页可一键记录完成或稍后提醒。';
  }

  String _replyCrops() {
    final cl = CloudSeed.region.climate;
    final list = CloudSeed.cropIds
        .map((id) => CloudSeed.crops[id]!)
        .toList()
      ..sort((a, b) => b.suitability.compareTo(a.suitability));
    final top = list.take(3).toList();
    return 'GPS 定位到 ${CloudSeed.region.name}，${cl.zone}，${cl.pattern}。\n'
        '${top.asMap().entries.map((e) => '${e.key + 1}. ${e.value.name} · 适宜度 ${e.value.suitability} 分 · ${e.value.sowWindow}').join('\n')}\n'
        '其中${top.first.name}为本地主栽品种，${top.first.reason}\n'
        '在「新种植」中填写土壤问卷，可生成专属方案。';
  }

  String _replyRemote() {
    return '异地查看有三种入口：\n'
        '1. 田块地图 → 选择田块 → 「异地查看」\n'
        '2. 田块详情 → 右上角相机按钮\n'
        '3. 支持可见光 / 多光谱 / 热成像切换\n'
        '页面内可查看土壤墒情、土温、空气湿度、光照传感器数据，以及无人机巡田与历史巡检画面。';
  }
}

final cloudFarmProvider = ChangeNotifierProvider<CloudFarmController>((ref) {
  return CloudFarmController();
});
