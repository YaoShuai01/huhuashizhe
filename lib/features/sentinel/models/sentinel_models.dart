/// 田哨（云端田哨 · 哨兵值守）数据模型。
///
/// 呼应项目总名"云端田哨"中的"哨"：农户实地种植后在 App 登记，
/// 田块自动同步到云种植小游戏；哨兵引擎按天气实况与作物生育期规则
/// 持续值守——寒潮/大风/降雨/打药时机自动生成预警，并给出可执行的
/// 农事建议（该打什么药、怎么防寒），让"哨"从名词变成动词。
library;

/// 哨兵值守的作物类型（与端侧病虫害四分类模型覆盖的作物对齐）
enum SentinelCrop {
  rapeseed('油菜', 180),
  cabbage('白菜', 60),
  rice('水稻', 130);

  const SentinelCrop(this.label, this.totalDays);
  final String label;

  /// 从播种到收获的全生育期天数（演示口径，按长江中下游露地栽培）
  final int totalDays;

  static SentinelCrop fromLabel(String label) => SentinelCrop.values
      .firstWhere((c) => c.label == label, orElse: () => SentinelCrop.rapeseed);
}

/// 生育阶段（按生长进度百分比划分，全作物通用口径）
enum GrowthStage {
  seedling('苗期', 0.0),
  growing('旺盛生长期', 0.2),
  yieldForming('产量形成期', 0.6),
  mature('成熟收获期', 0.85);

  const GrowthStage(this.label, this.startProgress);
  final String label;

  /// 进入该阶段的生长进度阈值
  final double startProgress;

  static GrowthStage fromProgress(double p) {
    var stage = GrowthStage.seedling;
    for (final s in GrowthStage.values) {
      if (p >= s.startProgress) stage = s;
    }
    return stage;
  }
}

/// 实地种植登记（一块田一条记录，同时是云种植游戏的同步源）
class FieldPlanting {
  final String id;
  final SentinelCrop crop;
  final double areaMu;
  final String location;
  final DateTime plantedAt;

  /// 同步到云种植游戏后分配的田块编号（从 1 起）
  final int gamePlot;

  final String owner;

  const FieldPlanting({
    required this.id,
    required this.crop,
    required this.areaMu,
    required this.location,
    required this.plantedAt,
    required this.gamePlot,
    this.owner = '演示农户',
  });

  /// 截止 [now] 已种植天数
  int daysElapsedAt(DateTime now) =>
      now.difference(plantedAt).inDays.clamp(0, 1 << 31);

  /// 截止 [now] 的生长进度（0.0 ~ 1.0）
  double progressAt(DateTime now) =>
      (daysElapsedAt(now) / crop.totalDays).clamp(0.0, 1.0);

  /// 截止 [now] 的生育阶段
  GrowthStage stageAt(DateTime now) => GrowthStage.fromProgress(progressAt(now));

  Map<String, dynamic> toJson() => {
        'id': id,
        'crop': crop.name,
        'areaMu': areaMu,
        'location': location,
        'plantedAt': plantedAt.toIso8601String(),
        'gamePlot': gamePlot,
        'owner': owner,
      };

  factory FieldPlanting.fromJson(Map<String, dynamic> json) => FieldPlanting(
        id: json['id'] as String,
        crop: SentinelCrop.values.firstWhere(
          (c) => c.name == (json['crop'] as String?),
          orElse: () => SentinelCrop.rapeseed,
        ),
        areaMu: (json['areaMu'] as num?)?.toDouble() ?? 0,
        location: json['location'] as String? ?? '',
        plantedAt:
            DateTime.tryParse(json['plantedAt'] as String? ?? '') ??
                DateTime.now(),
        gamePlot: (json['gamePlot'] as num?)?.toInt() ?? 0,
        owner: json['owner'] as String? ?? '演示农户',
      );
}

/// 预警类型
enum SentinelAlertType {
  coldWave('寒潮预警', 'ac_unit'),
  highWind('大风预警', 'air'),
  heavyRain('降雨预警', 'rainy'),
  sprayReminder('打药提醒', 'science'),
  pestRisk('病虫害风险', 'pest_control');

  const SentinelAlertType(this.label, this.iconName);
  final String label;
  final String iconName;
}

/// 预警级别
enum SentinelSeverity {
  info('提示'),
  warning('警告'),
  urgent('紧急');

  const SentinelSeverity(this.label);
  final String label;
}

/// 哨兵预警卡片
class SentinelAlert {
  final String id;

  /// 去重键（同一规则同一田块只提醒一次，例如 "cabbage.dampingOff-FT01"）
  final String ruleKey;
  final SentinelAlertType type;
  final SentinelSeverity severity;
  final String title;
  final String message;

  /// 可执行的农事建议（该打什么农药 / 怎么防寒）
  final String recommendation;

  /// 关联田块（可为空：全局性天气预警）
  final String? fieldId;
  final String? cropLabel;
  final DateTime createdAt;
  final bool handled;

  const SentinelAlert({
    required this.id,
    required this.ruleKey,
    required this.type,
    required this.severity,
    required this.title,
    required this.message,
    required this.recommendation,
    this.fieldId,
    this.cropLabel,
    required this.createdAt,
    this.handled = false,
  });

  SentinelAlert copyWith({bool? handled}) => SentinelAlert(
        id: id,
        ruleKey: ruleKey,
        type: type,
        severity: severity,
        title: title,
        message: message,
        recommendation: recommendation,
        fieldId: fieldId,
        cropLabel: cropLabel,
        createdAt: createdAt,
        handled: handled ?? this.handled,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'ruleKey': ruleKey,
        'type': type.name,
        'severity': severity.name,
        'title': title,
        'message': message,
        'recommendation': recommendation,
        'fieldId': fieldId,
        'cropLabel': cropLabel,
        'createdAt': createdAt.toIso8601String(),
        'handled': handled,
      };

  factory SentinelAlert.fromJson(Map<String, dynamic> json) => SentinelAlert(
        id: json['id'] as String,
        ruleKey: json['ruleKey'] as String? ?? json['id'] as String,
        type: SentinelAlertType.values.firstWhere(
          (t) => t.name == (json['type'] as String?),
          orElse: () => SentinelAlertType.sprayReminder,
        ),
        severity: SentinelSeverity.values.firstWhere(
          (s) => s.name == (json['severity'] as String?),
          orElse: () => SentinelSeverity.info,
        ),
        title: json['title'] as String? ?? '',
        message: json['message'] as String? ?? '',
        recommendation: json['recommendation'] as String? ?? '',
        fieldId: json['fieldId'] as String?,
        cropLabel: json['cropLabel'] as String?,
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
                DateTime.now(),
        handled: json['handled'] as bool? ?? false,
      );
}

/// 农事规则（作物 + 生育期天数窗口 → 风险与用药建议）。
///
/// 用药口径为农业技术推广通行方案，演示用；实际作业请遵当地植保部门指导。
class AgronomyRule {
  final String id;
  final SentinelCrop crop;
  final int dayFrom;
  final int dayTo;
  final String title;
  final String message;
  final String recommendation;
  final SentinelSeverity severity;

  const AgronomyRule({
    required this.id,
    required this.crop,
    required this.dayFrom,
    required this.dayTo,
    required this.title,
    required this.message,
    required this.recommendation,
    this.severity = SentinelSeverity.warning,
  });

  bool matches(int daysElapsed) =>
      daysElapsed >= dayFrom && daysElapsed <= dayTo;
}

/// 农事规则库（与"小课堂"科普口径一致）
const List<AgronomyRule> kAgronomyRules = [
  AgronomyRule(
    id: 'cabbage.caterpillar',
    crop: SentinelCrop.cabbage,
    dayFrom: 5,
    dayTo: 15,
    title: '菜青虫高发期',
    message: '白菜进入苗期，菜青虫/小菜蛾啃食叶片风险上升，注意巡查心叶。',
    recommendation: '苏云金杆菌（Bt）800 倍液，傍晚喷施心叶及叶背；与端侧识别联'
        '动，发现"菜青虫危害"可立即复喷。',
    severity: SentinelSeverity.warning,
  ),
  AgronomyRule(
    id: 'cabbage.downyMildew',
    crop: SentinelCrop.cabbage,
    dayFrom: 20,
    dayTo: 30,
    title: '霜霉病预防窗口',
    message: '莲座期遇到连续阴雨或昼夜温差大，霜霉病极易爆发。',
    recommendation: '75% 百菌清可湿性粉剂 600 倍液，7 天一次连喷 2 次；发现'
        '"霜霉病"病叶及时摘除带出田外。',
  ),
  AgronomyRule(
    id: 'rapeseed.aphid',
    crop: SentinelCrop.rapeseed,
    dayFrom: 5,
    dayTo: 20,
    title: '苗期蚜虫防控',
    message: '油菜苗期蚜虫聚集吸汁，还传播病毒病，需及早压低虫口。',
    recommendation: '10% 吡虫啉可湿性粉剂 2000 倍液，重点喷心叶；蚜量达百株 '
        '500 头即达标防治。',
  ),
  AgronomyRule(
    id: 'rapeseed.sclerotinia',
    crop: SentinelCrop.rapeseed,
    dayFrom: 90,
    dayTo: 115,
    title: '花期菌核病防治',
    message: '油菜进入花期，菌核病是油菜产量第一杀手，花期遇雨必防。',
    recommendation: '40% 菌核净可湿性粉剂 1000 倍液，盛花初期与末期各喷一次，'
        '重点喷中下部茎叶。',
    severity: SentinelSeverity.urgent,
  ),
  AgronomyRule(
    id: 'rice.planthopper',
    crop: SentinelCrop.rice,
    dayFrom: 25,
    dayTo: 40,
    title: '分蘖期稻飞虱',
    message: '水稻分蘖期稻飞虱迁入聚集，要防"虱烧"塌圈。',
    recommendation: '25% 吡蚜酮悬浮剂 1500 倍液，粗水喷雾对准稻株中下部。',
  ),
  AgronomyRule(
    id: 'rice.blast',
    crop: SentinelCrop.rice,
    dayFrom: 75,
    dayTo: 90,
    title: '破口期稻瘟病',
    message: '破口前后是稻瘟病防治关键窗口，错过难补救。',
    recommendation: '75% 三环唑可湿性粉剂，破口期一次、齐穗期补一次。',
    severity: SentinelSeverity.urgent,
  ),
];

/// 农事规则引擎：对每块田按已种植天数匹配规则，生成打药提醒预警。
List<SentinelAlert> runAgronomyRules(
  List<FieldPlanting> plantings,
  DateTime now,
) {
  final alerts = <SentinelAlert>[];
  for (final p in plantings) {
    final days = p.daysElapsedAt(now);
    for (final rule in kAgronomyRules) {
      if (rule.crop != p.crop) continue;
      if (!rule.matches(days)) continue;
      alerts.add(SentinelAlert(
        id: '${rule.id}-${p.id}',
        ruleKey: '${rule.id}-${p.id}',
        type: SentinelAlertType.sprayReminder,
        severity: rule.severity,
        title: rule.title,
        message: '${rule.message}（${p.crop.label} · ${p.location}，已种植 $days 天）',
        recommendation: rule.recommendation,
        fieldId: p.id,
        cropLabel: p.crop.label,
        createdAt: now,
      ));
    }
  }
  return alerts;
}

/// 天气哨兵：根据天气实况生成气象预警（复用 App 现有天气源字段）。
///
/// 寒潮判定演示口径：当前气温 ≤ 5°C 视为寒潮/霜冻风险（真实实现应接
/// 未来 24~48h 最低温预报，服务端定时值守后下发）。
List<SentinelAlert> runWeatherRules({
  required double? temperature,
  required double? windSpeed,
  required int? precipitationProbability,
  required DateTime now,
  required bool hasPlantings,
  String? locationName,
}) {
  final alerts = <SentinelAlert>[];
  if (!hasPlantings) return alerts;
  final where = (locationName == null || locationName.isEmpty ||
          locationName == '定位中...')
      ? ''
      : '（$locationName）';

  if (temperature != null && temperature <= 5) {
    alerts.add(SentinelAlert(
      id: 'weather.coldWave-$now',
      ruleKey: 'weather.coldWave',
      type: SentinelAlertType.coldWave,
      severity: SentinelSeverity.urgent,
      title: '寒潮来袭，注意防冻',
      message: '当前气温 ${temperature.toStringAsFixed(1)}°C 已低于 5°C 寒潮阈值'
          '$where，作物易发生冻害。',
      recommendation: '白菜：覆盖防寒膜或提前采收；油菜：培土壅蔸 + 喷施磷酸二氢'
          '钾提升抗寒力；水稻秧田：灌深水护苗。寒潮过后 3 天内不宜打药。',
      createdAt: now,
    ));
  }
  if (windSpeed != null && windSpeed > 5.4) {
    alerts.add(SentinelAlert(
      id: 'weather.highWind-$now',
      ruleKey: 'weather.highWind',
      type: SentinelAlertType.highWind,
      severity: SentinelSeverity.urgent,
      title: '大风预警，暂停喷洒',
      message: '当前风速 ${windSpeed.toStringAsFixed(1)} m/s 超过植保喷洒上限 '
          '5.4 m/s$where，药液漂移会伤邻田作物。',
      recommendation: '暂停无人机喷洒作业；已预约订单将转由机手现场复评。',
      createdAt: now,
    ));
  }
  if (precipitationProbability != null && precipitationProbability > 60) {
    alerts.add(SentinelAlert(
      id: 'weather.heavyRain-$now',
      ruleKey: 'weather.heavyRain',
      type: SentinelAlertType.heavyRain,
      severity: SentinelSeverity.warning,
      title: '降雨在途，药液易冲刷',
      message: '降雨概率 $precipitationProbability% 超过 60% 阈值$where，打药'
          '后药液易被雨水冲刷失效。',
      recommendation: '避开降雨窗口打药；雨后趁墒追肥，并检查田间排水沟。',
      createdAt: now,
    ));
  }
  return alerts;
}

/// 端侧病虫害四分类模型（v3.1.0）识别结果 → 哨兵预警的映射。
///
/// 识别命中"危害"类标签时调用，把端侧 AI 变成田哨的"眼睛"。
SentinelAlert? alertFromModelPestLabel({
  required String pestLabel,
  required String location,
  required DateTime now,
  String? fieldId,
}) {
  switch (pestLabel) {
    case '菜青虫危害':
      return SentinelAlert(
        id: 'pest.caterpillar-$now',
        ruleKey: 'pest.caterpillar-$fieldId',
        type: SentinelAlertType.pestRisk,
        severity: SentinelSeverity.warning,
        title: '端侧识别发现菜青虫危害',
        message: '模型在 $location 识别到菜青虫危害特征，建议尽快防治。',
        recommendation: '苏云金杆菌（Bt）800 倍液或 4.5% 氯氰菊酯乳油 1500 倍液'
            '，重点喷心叶与叶背。',
        fieldId: fieldId,
        cropLabel: '白菜',
        createdAt: now,
      );
    case '霜霉病':
      return SentinelAlert(
        id: 'pest.downyMildew-$now',
        ruleKey: 'pest.downyMildew-$fieldId',
        type: SentinelAlertType.pestRisk,
        severity: SentinelSeverity.urgent,
        title: '端侧识别发现霜霉病',
        message: '模型在 $location 识别到霜霉病病斑，传染性强需立即处置。',
        recommendation: '72% 霜脲·锰锌（克露）800 倍液 + 摘除病叶带出田外，5~7 '
            '天一次连喷 2 次。',
        fieldId: fieldId,
        cropLabel: '白菜',
        createdAt: now,
      );
    case '螟危害':
      return SentinelAlert(
        id: 'pest.borer-$now',
        ruleKey: 'pest.borer-$fieldId',
        type: SentinelAlertType.pestRisk,
        severity: SentinelSeverity.warning,
        title: '端侧识别发现螟虫危害',
        message: '模型在 $location 识别到螟虫蛀食特征，注意钻蛀心叶。',
        recommendation: '20% 氯虫苯甲酰胺悬浮剂 3000 倍液，卵孵化高峰期喷施。',
        fieldId: fieldId,
        cropLabel: '白菜',
        createdAt: now,
      );
    default:
      // "健康"或未知标签不生成预警
      return null;
  }
}
