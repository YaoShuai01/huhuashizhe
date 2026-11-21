import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/constants/server_config.dart';
import '../../../services/weather_service.dart';
import '../models/sentinel_models.dart';

/// 田哨服务（云端田哨 · 哨兵值守）。
///
/// 三条哨线：
/// 1. 云田同步——实地种植登记后分配云种植游戏田块，生长进度实时可算；
/// 2. 天气哨——复用 App 现有天气源，寒潮/大风/降雨超标即预警；
/// 3. 农事哨——按作物生育期规则引擎提醒打药，并联动端侧病虫害识别结果。
///
/// 演示优先：服务端接口不可达时回落内置演示数据（与预约模块同一策略）。
class SentinelService extends ChangeNotifier {
  SentinelService({Dio? dio, bool enableServerSync = true})
      : _dio = dio,
        _enableServerSync = enableServerSync;

  final Dio? _dio;
  final bool _enableServerSync;

  final List<FieldPlanting> _plantings = [];
  final List<SentinelAlert> _alerts = [];

  /// 已生成的农事规则键（含已处理），避免重复提醒
  final Set<String> _emittedRuleKeys = {};

  bool _loaded = false;

  /// 当前是否运行在演示数据模式
  bool usingDemoData = true;

  /// 只读田块列表
  List<FieldPlanting> get plantings => List.unmodifiable(_plantings);

  /// 只读预警列表（未处理在前，同级按时间倒序）
  List<SentinelAlert> get alerts {
    final list = List<SentinelAlert>.from(_alerts);
    list.sort((a, b) {
      if (a.handled != b.handled) return a.handled ? 1 : -1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return List.unmodifiable(list);
  }

  /// 未处理预警数量（首页角标用）
  int get unhandledAlertCount => _alerts.where((a) => !a.handled).length;

  /// 已同步到云种植游戏的田块数
  int get syncedPlotCount => _plantings.length;

  static const String _plantingsPath = '/schedule/sentinel/plantings';
  static const String _plantingPath = '/schedule/sentinel/planting';
  static const String _alertPath = '/schedule/sentinel/alert';

  Dio? get _client {
    try {
      return _dio ??
          Dio(BaseOptions(
            baseUrl: serverBaseUrl,
            connectTimeout: const Duration(seconds: 6),
            receiveTimeout: const Duration(seconds: 10),
            responseType: ResponseType.json,
            validateStatus: (status) => status != null,
          ));
    } catch (_) {
      return null;
    }
  }

  /// 首次进入田哨页时调用；服务端不可达时回落演示数据
  Future<void> loadData() async {
    if (_loaded) return;
    _loaded = true;
    _seedDemoData();
    notifyListeners();

    if (!_enableServerSync) return;
    final dio = _client;
    if (dio == null) return;
    try {
      final res = await dio.get<dynamic>(_plantingsPath);
      final data = res.data;
      if (res.statusCode == 200 && data is Map) {
        final list = data['plantings'];
        if (list is List && list.isNotEmpty) {
          _plantings
            ..clear()
            ..addAll(list
                .map((e) => FieldPlanting.fromJson(
                    Map<String, dynamic>.from(e as Map)))
                .toList());
          usingDemoData = false;
          refreshAgronomyAlerts();
          notifyListeners();
        }
      }
    } catch (_) {
      // 服务端未部署/无网：保持演示数据
    }
  }

  /// 登记实地种植，并同步到云种植游戏（分配田块编号）。
  ///
  /// 登记后立即跑一遍农事规则引擎，命中规则即生成打药提醒。
  FieldPlanting registerPlanting({
    required SentinelCrop crop,
    required double areaMu,
    required String location,
    DateTime? plantedAt,
    String owner = '演示农户',
  }) {
    final now = DateTime.now();
    final planting = FieldPlanting(
      id: 'FT${now.millisecondsSinceEpoch}',
      crop: crop,
      areaMu: areaMu,
      location: location,
      plantedAt: plantedAt ?? now,
      gamePlot: _plantings.length + 1,
      owner: owner,
    );
    _plantings.add(planting);
    refreshAgronomyAlerts();
    _postBestEffort(_plantingPath, planting.toJson());
    notifyListeners();
    return planting;
  }

  /// 天气哨：天气数据到达后调用，生成/去重气象预警。
  ///
  /// 仅在真正新增预警时通知监听者，避免与页面"build → 帧后评估"形成死循环。
  void evaluateWeather(WeatherData? weather) {
    if (weather == null) return;
    final generated = runWeatherRules(
      temperature: weather.temperature,
      windSpeed: weather.windSpeed,
      precipitationProbability: weather.precipitationProbability,
      now: DateTime.now(),
      hasPlantings: _plantings.isNotEmpty,
      locationName: weather.locationName,
    );
    var added = false;
    for (final a in generated) {
      if (_alerts.any((e) => e.ruleKey == a.ruleKey)) continue;
      _alerts.add(a);
      added = true;
    }
    if (added) notifyListeners();
  }

  /// 农事哨：对全部田块重跑规则引擎（新田块登记/服务端同步后调用）。
  void refreshAgronomyAlerts() {
    final now = DateTime.now();
    for (final a in runAgronomyRules(_plantings, now)) {
      if (_emittedRuleKeys.contains(a.ruleKey)) continue;
      _emittedRuleKeys.add(a.ruleKey);
      _alerts.add(a);
    }
    notifyListeners();
  }

  /// 哨兵的"眼睛"：端侧病虫害模型识别命中危害标签时，转成预警推送。
  ///
  /// [pestLabel] 取模型输出标签：菜青虫危害 / 霜霉病 / 螟危害（"健康"不告警）。
  bool reportPestFromModel({
    required String pestLabel,
    required String location,
    String? fieldId,
  }) {
    final alert = alertFromModelPestLabel(
      pestLabel: pestLabel,
      location: location,
      now: DateTime.now(),
      fieldId: fieldId,
    );
    if (alert == null) return false;
    _alerts.add(alert);
    _postBestEffort(_alertPath, alert.toJson());
    notifyListeners();
    return true;
  }

  /// 演示：一键模拟"寒潮来袭"（答辩演示剧本，不影响真实天气哨）。
  ///
  /// 每块田生成一条寒潮预警，防寒建议按作物区分。
  void triggerDemoColdWave() {
    final now = DateTime.now();
    for (final p in _plantings) {
      _alerts.add(SentinelAlert(
        id: 'demo.coldWave-${p.id}-$now',
        ruleKey: 'demo.coldWave-${p.id}-$now',
        type: SentinelAlertType.coldWave,
        severity: SentinelSeverity.urgent,
        title: '寒潮预警（演示）',
        message: '未来 24 小时最低气温将骤降至 -2°C'
            '，${p.crop.label}田（${p.location}）存在冻害风险。',
        recommendation: _coldWaveAdvice(p.crop),
        fieldId: p.id,
        cropLabel: p.crop.label,
        createdAt: now,
      ));
      _postBestEffort(_alertPath, _alerts.last.toJson());
    }
    notifyListeners();
  }

  /// 标记预警已处理（"知道了"）
  void handleAlert(String id) {
    final index = _alerts.indexWhere((a) => a.id == id);
    if (index == -1) return;
    _alerts[index] = _alerts[index].copyWith(handled: true);
    _postBestEffort(_alertPath, {
      'id': id,
      'action': 'handle',
    });
    notifyListeners();
  }

  String _coldWaveAdvice(SentinelCrop crop) {
    switch (crop) {
      case SentinelCrop.cabbage:
        return '覆盖防寒膜或无纺布，可采收的白菜抢在寒潮前采收；寒潮过后 3 天内'
            '不宜打药，待气温回升再补防霜霉病。';
      case SentinelCrop.rapeseed:
        return '培土壅蔸护根颈，喷施 0.2% 磷酸二氢钾 + 新高脂膜提升抗寒力；雪后'
            '及时清理田间积水。';
      case SentinelCrop.rice:
        return '秧田灌深水护苗（水层至秧苗 2/3），寒潮过后逐步排水，防秧苗生理'
            '性失水。';
    }
  }

  void _seedDemoData() {
    final now = DateTime.now();
    // 演示田块 1：白菜，种下 25 天 → 命中"霜霉病预防窗口"（打药提醒）
    _plantings.add(FieldPlanting(
      id: 'FT-DEMO-01',
      crop: SentinelCrop.cabbage,
      areaMu: 4,
      location: '朋兴乡丹阳村 1 号地',
      plantedAt: now.subtract(const Duration(days: 25)),
      gamePlot: 1,
    ));
    // 演示田块 2：油菜，种下 95 天 → 命中"花期菌核病防治"（紧急打药提醒）
    _plantings.add(FieldPlanting(
      id: 'FT-DEMO-02',
      crop: SentinelCrop.rapeseed,
      areaMu: 12,
      location: '朋兴乡挂口村 3 号地',
      plantedAt: now.subtract(const Duration(days: 95)),
      gamePlot: 2,
    ));
    refreshAgronomyAlerts();
  }

  Future<void> _postBestEffort(String path, Map<String, dynamic> body) async {
    if (!_enableServerSync) return;
    final dio = _client;
    if (dio == null) return;
    try {
      await dio.post<dynamic>(path, data: body);
    } catch (_) {
      // 服务端未部署/无网：演示模式继续
    }
  }
}
