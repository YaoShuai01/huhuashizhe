import 'package:flutter/material.dart';

/// 云种植演示数据模型
/// 说明：气候、土壤、作物与阶段参数均为演示数据，后续可替换为真实数据源。

class CloudClimate {
  final double annualTemp;
  final int rainfall;
  final int frostFree;
  final int accumTemp;
  final String soil;
  final String pattern;
  final String zone;
  final String desc;

  const CloudClimate({
    required this.annualTemp,
    required this.rainfall,
    required this.frostFree,
    required this.accumTemp,
    required this.soil,
    required this.pattern,
    required this.zone,
    required this.desc,
  });
}

class CloudRegion {
  final String province;
  final String city;
  final String district;
  final String town;
  final String name;
  final String short;
  final double lat;
  final double lng;
  final double accuracy;
  final CloudClimate climate;

  const CloudRegion({
    required this.province,
    required this.city,
    required this.district,
    required this.town,
    required this.name,
    required this.short,
    required this.lat,
    required this.lng,
    required this.accuracy,
    required this.climate,
  });
}

class CloudWeatherDay {
  final String label;
  final String icon;
  final int hi;
  final int lo;
  final int rain;
  final double wind;

  const CloudWeatherDay({
    required this.label,
    required this.icon,
    required this.hi,
    required this.lo,
    required this.rain,
    required this.wind,
  });
}

class CloudWeather {
  final int temp;
  final int low;
  final String desc;
  final int humidity;
  final double wind;
  final String windDir;
  final int rainProb;
  final double pressure;
  final double visibility;
  final double soilTemp;
  final double rainLast3mm;
  final String sunrise;
  final String sunset;
  final List<CloudWeatherDay> forecast;

  const CloudWeather({
    required this.temp,
    required this.low,
    required this.desc,
    required this.humidity,
    required this.wind,
    required this.windDir,
    required this.rainProb,
    required this.pressure,
    required this.visibility,
    required this.soilTemp,
    required this.rainLast3mm,
    required this.sunrise,
    required this.sunset,
    required this.forecast,
  });
}

class SoilInfo {
  final String key;
  final String name;
  final int base;
  final String desc;

  const SoilInfo(this.key, this.name, this.base, this.desc);
}

class IrrigationInfo {
  final String key;
  final String name;
  final int base;
  final String desc;

  const IrrigationInfo(this.key, this.name, this.base, this.desc);
}

class CropStage {
  final String name;
  final int s;
  final int e;
  final int sp;
  final int ep;
  final String tip;

  const CropStage({
    required this.name,
    required this.s,
    required this.e,
    required this.sp,
    required this.ep,
    required this.tip,
  });
}

class CropInfo {
  final String id;
  final String name;
  final String variety;
  final String season;
  final String sowWindow;
  final int cycle;
  final int density;
  final int yield;
  final String waterNeed;
  final int suitability;
  final String pattern;
  final String suitable;
  final String reason;
  final List<CropStage> stages;

  const CropInfo({
    required this.id,
    required this.name,
    required this.variety,
    required this.season,
    required this.sowWindow,
    required this.cycle,
    required this.density,
    required this.yield,
    required this.waterNeed,
    required this.suitability,
    required this.pattern,
    required this.suitable,
    required this.reason,
    required this.stages,
  });
}

class PlotLog {
  final DateTime t;
  final String type;
  final String title;
  final String desc;

  const PlotLog({
    required this.t,
    required this.type,
    required this.title,
    required this.desc,
  });

  Map<String, dynamic> toJson() => {
        't': t.toIso8601String(),
        'type': type,
        'title': title,
        'desc': desc,
      };

  factory PlotLog.fromJson(Map<String, dynamic> json) => PlotLog(
        t: DateTime.tryParse('${json['t']}') ?? DateTime.now(),
        type: '${json['type'] ?? 'note'}',
        title: '${json['title'] ?? ''}',
        desc: '${json['desc'] ?? ''}',
      );
}

class CloudPlot {
  final String id;
  String name;
  String? cropId;
  double area;
  DateTime? plantedAt;
  List<List<double>> polygon;
  String soil;
  String irrigation;
  String fertilizer;
  DateTime? lastWaterAt;
  DateTime? lastFertAt;
  DateTime? lastCalibratedAt;
  DateTime? lastPestAt;
  DateTime? lastSensedAt;
  String sync;
  String buildSource;
  List<PlotLog> logs;
  bool harvested;
  double pctOffset;

  CloudPlot({
    required this.id,
    required this.name,
    required this.cropId,
    required this.area,
    required this.plantedAt,
    required this.polygon,
    required this.soil,
    required this.irrigation,
    required this.fertilizer,
    required this.lastWaterAt,
    required this.lastFertAt,
    required this.lastCalibratedAt,
    required this.lastPestAt,
    required this.lastSensedAt,
    this.sync = 'auto',
    required this.buildSource,
    required this.logs,
    this.harvested = false,
    this.pctOffset = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'cropId': cropId,
        'area': area,
        'plantedAt': plantedAt?.toIso8601String(),
        'polygon': polygon,
        'soil': soil,
        'irrigation': irrigation,
        'fertilizer': fertilizer,
        'lastWaterAt': lastWaterAt?.toIso8601String(),
        'lastFertAt': lastFertAt?.toIso8601String(),
        'lastCalibratedAt': lastCalibratedAt?.toIso8601String(),
        'lastPestAt': lastPestAt?.toIso8601String(),
        'lastSensedAt': lastSensedAt?.toIso8601String(),
        'sync': sync,
        'buildSource': buildSource,
        'logs': logs.map((e) => e.toJson()).toList(),
        'harvested': harvested,
        'pctOffset': pctOffset,
      };

  factory CloudPlot.fromJson(Map<String, dynamic> json) {
    final rawPolygon = (json['polygon'] as List?) ?? const [];
    return CloudPlot(
      id: '${json['id']}',
      name: '${json['name'] ?? '田块'}',
      cropId: json['cropId'] as String?,
      area: (json['area'] as num?)?.toDouble() ?? 0,
      plantedAt: _date(json['plantedAt']),
      polygon: rawPolygon
          .map((e) => (e as List).map((v) => (v as num).toDouble()).toList())
          .toList(),
      soil: '${json['soil'] ?? 'loam'}',
      irrigation: '${json['irrigation'] ?? 'none'}',
      fertilizer: '${json['fertilizer'] ?? '未施肥'}',
      lastWaterAt: _date(json['lastWaterAt']),
      lastFertAt: _date(json['lastFertAt']),
      lastCalibratedAt: _date(json['lastCalibratedAt']),
      lastPestAt: _date(json['lastPestAt']),
      lastSensedAt: _date(json['lastSensedAt']),
      sync: '${json['sync'] ?? 'auto'}',
      buildSource: '${json['buildSource'] ?? 'GPS 圈地'}',
      logs: ((json['logs'] as List?) ?? const [])
          .map((e) => PlotLog.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      harvested: json['harvested'] == true,
      pctOffset: (json['pctOffset'] as num?)?.toDouble() ?? 0,
    );
  }

  static DateTime? _date(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse('$value');
  }
}

class CloudSettings {
  int moistureThreshold;
  int calibrateDays;
  int remindHour;
  bool autoSync;

  CloudSettings({
    this.moistureThreshold = 55,
    this.calibrateDays = 7,
    this.remindHour = 8,
    this.autoSync = true,
  });

  Map<String, dynamic> toJson() => {
        'moistureThreshold': moistureThreshold,
        'calibrateDays': calibrateDays,
        'remindHour': remindHour,
        'autoSync': autoSync,
      };

  factory CloudSettings.fromJson(Map<String, dynamic> json) => CloudSettings(
        moistureThreshold: (json['moistureThreshold'] as num?)?.toInt() ?? 55,
        calibrateDays: (json['calibrateDays'] as num?)?.toInt() ?? 7,
        remindHour: (json['remindHour'] as num?)?.toInt() ?? 8,
        autoSync: json['autoSync'] != false,
      );
}

class CloudChatMessage {
  final String role; // me / ai
  final String text;
  final DateTime t;

  const CloudChatMessage({required this.role, required this.text, required this.t});

  bool get isMe => role == 'me';

  Map<String, dynamic> toJson() => {
        'role': role,
        'text': text,
        't': t.toIso8601String(),
      };

  factory CloudChatMessage.fromJson(Map<String, dynamic> json) => CloudChatMessage(
        role: '${json['role'] ?? 'ai'}',
        text: '${json['text'] ?? ''}',
        t: DateTime.tryParse('${json['t']}') ?? DateTime.now(),
      );
}

class CloudState {
  int version;
  List<CloudPlot> plots;
  CloudSettings settings;
  Map<String, DateTime> snoozed;
  List<CloudChatMessage> chat;

  CloudState({
    this.version = 1,
    required this.plots,
    required this.settings,
    Map<String, DateTime>? snoozed,
    List<CloudChatMessage>? chat,
  })  : snoozed = snoozed ?? {},
        chat = chat ?? [];

  Map<String, dynamic> toJson() => {
        'version': version,
        'plots': plots.map((e) => e.toJson()).toList(),
        'settings': settings.toJson(),
        'snoozed': snoozed.map((k, v) => MapEntry(k, v.toIso8601String())),
        'chat': chat.map((e) => e.toJson()).toList(),
      };

  factory CloudState.fromJson(Map<String, dynamic> json) {
    final rawPlots = (json['plots'] as List?) ?? const [];
    final rawSnoozed = (json['snoozed'] as Map?) ?? const {};
    return CloudState(
      version: (json['version'] as num?)?.toInt() ?? 1,
      plots: rawPlots
          .map((e) => CloudPlot.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      settings: CloudSettings.fromJson(
          Map<String, dynamic>.from((json['settings'] as Map?) ?? const {})),
      snoozed: rawSnoozed.map((k, v) => MapEntry(
            '$k',
            DateTime.tryParse('$v') ?? DateTime.now(),
          )),
      chat: ((json['chat'] as List?) ?? const [])
          .map((e) => CloudChatMessage.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}

/// 演示静态数据（区域 / 天气 / 土壤 / 灌溉 / 作物 / 初始田块）
class CloudSeed {
  CloudSeed._();

  static const CloudRegion region = CloudRegion(
    province: '湖北省',
    city: '荆州市',
    district: '荆州区',
    town: '太湖港农场',
    name: '湖北省荆州市荆州区·太湖港农场',
    short: '荆州·太湖港',
    lat: 30.4072,
    lng: 112.1359,
    accuracy: 1.2,
    climate: CloudClimate(
      annualTemp: 16.8,
      rainfall: 1100,
      frostFree: 258,
      accumTemp: 5150,
      soil: '潮土 / 水稻土',
      pattern: '稻油轮作 · 一年两熟',
      zone: '北亚热带季风气候',
      desc: '四季分明，雨热同季，冬季温和，适合冬油菜安全越冬与中稻种植。',
    ),
  );

  static const CloudWeather weather = CloudWeather(
    temp: 26,
    low: 17,
    desc: '多云转晴',
    humidity: 72,
    wind: 2.6,
    windDir: '东南风',
    rainProb: 15,
    pressure: 1012,
    visibility: 12,
    soilTemp: 21.4,
    rainLast3mm: 6.5,
    sunrise: '06:42',
    sunset: '17:26',
    forecast: [
      CloudWeatherDay(label: '今天', icon: 'partly', hi: 26, lo: 17, rain: 15, wind: 2.6),
      CloudWeatherDay(label: '明天', icon: 'sun', hi: 27, lo: 18, rain: 5, wind: 2.1),
      CloudWeatherDay(label: '后天', icon: 'rain', hi: 22, lo: 16, rain: 65, wind: 3.4),
      CloudWeatherDay(label: '周五', icon: 'rain', hi: 20, lo: 15, rain: 80, wind: 4.0),
      CloudWeatherDay(label: '周六', icon: 'cloud', hi: 23, lo: 16, rain: 30, wind: 2.8),
      CloudWeatherDay(label: '周日', icon: 'partly', hi: 25, lo: 17, rain: 10, wind: 2.2),
      CloudWeatherDay(label: '周一', icon: 'sun', hi: 27, lo: 18, rain: 5, wind: 1.9),
    ],
  );

  static const Map<String, SoilInfo> soils = {
    'loam': SoilInfo('loam', '壤土', 62, '保水保肥均衡，适合油菜、蔬菜'),
    'clay': SoilInfo('clay', '黏土', 70, '保水强、透气差，注意防渍害'),
    'sandy': SoilInfo('sandy', '砂土', 46, '渗水快、保肥弱，需少量多次灌溉'),
    'paddy': SoilInfo('paddy', '水稻土', 74, '耕层深厚，稻油轮作区常见'),
  };

  static const Map<String, IrrigationInfo> irrigations = {
    'none': IrrigationInfo('none', '无灌溉', 0, '依赖自然降水'),
    'drip': IrrigationInfo('drip', '滴灌', 7, '节水，适合旱地经济作物'),
    'sprinkler': IrrigationInfo('sprinkler', '喷灌', 9, '均匀度高，可兼作降温'),
    'flood': IrrigationInfo('flood', '漫灌', 13, '水量大，注意排水防渍'),
    'rain': IrrigationInfo('rain', '人工降雨', 11, '集中补水，需关注天气窗口'),
  };

  static const List<String> cropIds = [
    'rapeseed',
    'rice',
    'wheat',
    'corn',
    'soybean',
    'pakchoi',
  ];

  static final Map<String, CropInfo> crops = {
    'rapeseed': const CropInfo(
      id: 'rapeseed',
      name: '油菜',
      variety: '中双11号',
      season: '秋播冬油菜',
      sowWindow: '9月下旬 — 10月中旬',
      cycle: 205,
      density: 24000,
      yield: 185,
      waterNeed: '中等',
      suitability: 96,
      pattern: '稻油轮作 · 一年两熟',
      suitable: '本地主栽',
      reason: '冬季温和可安全越冬，花期与本地春雨错峰，水稻土保水保肥。',
      stages: [
        CropStage(name: '播种', s: 0, e: 3, sp: 0, ep: 3, tip: '播种后保持土壤湿润，3—5 天吸胀萌动'),
        CropStage(name: '发芽', s: 3, e: 8, sp: 3, ep: 10, tip: '胚根突破种皮，墒情保持 60% 左右'),
        CropStage(name: '出苗', s: 8, e: 15, sp: 10, ep: 18, tip: '子叶展开，注意防治跳甲与蚜虫'),
        CropStage(name: '幼苗', s: 15, e: 62, sp: 18, ep: 38, tip: '间苗定苗，亩留苗 2—3 万株'),
        CropStage(name: '蕾薹', s: 62, e: 98, sp: 38, ep: 55, tip: '追施薹肥，亩施尿素 5—8kg'),
        CropStage(name: '开花', s: 98, e: 128, sp: 55, ep: 72, tip: '叶面喷硼防花而不实，重点防菌核病'),
        CropStage(name: '结荚', s: 128, e: 165, sp: 72, ep: 88, tip: '保持土壤湿润，防倒伏与蚜虫'),
        CropStage(name: '成熟', s: 165, e: 205, sp: 88, ep: 100, tip: '角果 70%—80% 变黄时适期收获'),
      ],
    ),
    'rice': const CropInfo(
      id: 'rice',
      name: '水稻',
      variety: '丰两优香1号',
      season: '一季中稻',
      sowWindow: '5月上旬 — 5月下旬',
      cycle: 140,
      density: 18000,
      yield: 620,
      waterNeed: '较高',
      suitability: 91,
      pattern: '稻油轮作 · 一年两熟',
      suitable: '本地主栽',
      reason: '雨热同季，水稻土保水保肥，中稻收获后可接茬冬油菜。',
      stages: [
        CropStage(name: '播种', s: 0, e: 3, sp: 0, ep: 3, tip: '晒种消毒，浅水湿润育秧'),
        CropStage(name: '发芽', s: 3, e: 8, sp: 3, ep: 10, tip: '保持秧板湿润，防止高温烧芽'),
        CropStage(name: '出苗', s: 8, e: 16, sp: 10, ep: 18, tip: '一叶一心，膜内温度不超过 35℃'),
        CropStage(name: '幼苗', s: 16, e: 40, sp: 18, ep: 32, tip: '三叶期追施断奶肥，防绵腐病'),
        CropStage(name: '分蘖', s: 40, e: 70, sp: 32, ep: 48, tip: '浅水促蘖，够苗及时晒田'),
        CropStage(name: '拔节', s: 70, e: 88, sp: 48, ep: 58, tip: '施穗肥，保持浅水层'),
        CropStage(name: '抽穗', s: 88, e: 102, sp: 58, ep: 68, tip: '破口期重点防稻曲病、螟虫'),
        CropStage(name: '灌浆', s: 102, e: 125, sp: 68, ep: 84, tip: '干湿交替，防早衰'),
        CropStage(name: '成熟', s: 125, e: 140, sp: 84, ep: 100, tip: '九成熟时收获，减少落粒'),
      ],
    ),
    'wheat': const CropInfo(
      id: 'wheat',
      name: '小麦',
      variety: '鄂麦596',
      season: '冬小麦',
      sowWindow: '10月中旬 — 11月上旬',
      cycle: 205,
      density: 22000,
      yield: 380,
      waterNeed: '中等',
      suitability: 88,
      pattern: '麦稻轮作 · 一年两熟',
      suitable: '适宜',
      reason: '越冬期温度适宜，春后降水匹配拔节与灌浆需求。',
      stages: [
        CropStage(name: '播种', s: 0, e: 3, sp: 0, ep: 3, tip: '精细整地，播深 3—5cm'),
        CropStage(name: '发芽', s: 3, e: 9, sp: 3, ep: 10, tip: '足墒播种，确保一播全苗'),
        CropStage(name: '出苗', s: 9, e: 18, sp: 10, ep: 18, tip: '查苗补种，防地下害虫'),
        CropStage(name: '分蘖', s: 18, e: 60, sp: 18, ep: 34, tip: '冬前促分蘖，旺长田块镇压'),
        CropStage(name: '拔节', s: 60, e: 95, sp: 34, ep: 50, tip: '追施拔节肥，防倒伏'),
        CropStage(name: '抽穗', s: 95, e: 120, sp: 50, ep: 62, tip: '扬花期防赤霉病'),
        CropStage(name: '开花', s: 120, e: 132, sp: 62, ep: 70, tip: '关注降水，抢晴喷药'),
        CropStage(name: '灌浆', s: 132, e: 175, sp: 70, ep: 88, tip: '叶面喷肥防早衰'),
        CropStage(name: '成熟', s: 175, e: 205, sp: 88, ep: 100, tip: '蜡熟末期及时收获'),
      ],
    ),
    'corn': const CropInfo(
      id: 'corn',
      name: '玉米',
      variety: '宜单629',
      season: '夏玉米',
      sowWindow: '6月上旬 — 6月下旬',
      cycle: 115,
      density: 3800,
      yield: 560,
      waterNeed: '较高',
      suitability: 79,
      pattern: '玉稻轮作 · 一年两熟',
      suitable: '可种',
      reason: '抽雄吐丝期与本地伏旱重叠，需配套灌溉，产量风险中等。',
      stages: [
        CropStage(name: '播种', s: 0, e: 3, sp: 0, ep: 3, tip: '抢墒播种，施足基肥'),
        CropStage(name: '发芽', s: 3, e: 8, sp: 3, ep: 10, tip: '土壤含水量保持 65% 左右'),
        CropStage(name: '出苗', s: 8, e: 15, sp: 10, ep: 18, tip: '三叶期间苗，防地老虎'),
        CropStage(name: '幼苗', s: 15, e: 35, sp: 18, ep: 32, tip: '蹲苗控旺，中耕除草'),
        CropStage(name: '拔节', s: 35, e: 60, sp: 32, ep: 46, tip: '大喇叭口期追施穗肥'),
        CropStage(name: '抽雄', s: 60, e: 72, sp: 46, ep: 58, tip: '需水临界期，干旱及时灌溉'),
        CropStage(name: '吐丝', s: 72, e: 82, sp: 58, ep: 68, tip: '人工辅助授粉，防花期高温'),
        CropStage(name: '灌浆', s: 82, e: 100, sp: 68, ep: 86, tip: '保绿叶防早衰，防玉米螟'),
        CropStage(name: '成熟', s: 100, e: 115, sp: 86, ep: 100, tip: '苞叶变黄后适期晚收'),
      ],
    ),
    'soybean': const CropInfo(
      id: 'soybean',
      name: '大豆',
      variety: '中豆41',
      season: '夏大豆',
      sowWindow: '6月上旬 — 6月中旬',
      cycle: 125,
      density: 15000,
      yield: 210,
      waterNeed: '中等',
      suitability: 82,
      pattern: '豆稻轮作 · 一年两熟',
      suitable: '适宜',
      reason: '生育期与本地光温匹配，注意花荚期排涝。',
      stages: [
        CropStage(name: '播种', s: 0, e: 3, sp: 0, ep: 3, tip: '接种根瘤菌，合理密植'),
        CropStage(name: '发芽', s: 3, e: 8, sp: 3, ep: 10, tip: '足墒播种，防烂种'),
        CropStage(name: '出苗', s: 8, e: 15, sp: 10, ep: 18, tip: '查苗补苗，防蚜虫'),
        CropStage(name: '幼苗', s: 15, e: 40, sp: 18, ep: 28, tip: '中耕培土，促根瘤形成'),
        CropStage(name: '分枝', s: 40, e: 60, sp: 28, ep: 40, tip: '控旺防倒，追施磷钾肥'),
        CropStage(name: '开花', s: 60, e: 75, sp: 40, ep: 54, tip: '花荚期保持土壤湿润'),
        CropStage(name: '结荚', s: 75, e: 95, sp: 54, ep: 72, tip: '防豆荚螟，雨后及时排涝'),
        CropStage(name: '鼓粒', s: 95, e: 112, sp: 72, ep: 88, tip: '叶面喷施磷酸二氢钾'),
        CropStage(name: '成熟', s: 112, e: 125, sp: 88, ep: 100, tip: '叶片脱落、籽粒归圆后收获'),
      ],
    ),
    'pakchoi': const CropInfo(
      id: 'pakchoi',
      name: '小白菜',
      variety: '上海青',
      season: '秋冬叶菜',
      sowWindow: '9月 — 11月，多茬播种',
      cycle: 58,
      density: 35000,
      yield: 1800,
      waterNeed: '较高',
      suitability: 86,
      pattern: '一年多熟 · 年 3—4 茬',
      suitable: '适宜',
      reason: '生育期短、复种指数高，本地秋冬温光适宜，注意菜青虫防治。',
      stages: [
        CropStage(name: '播种', s: 0, e: 2, sp: 0, ep: 3, tip: '浅播覆细土，保持畦面湿润'),
        CropStage(name: '发芽', s: 2, e: 5, sp: 3, ep: 10, tip: '早晚小水勤浇，防高温烧芽'),
        CropStage(name: '出苗', s: 5, e: 9, sp: 10, ep: 18, tip: '间苗去弱留壮'),
        CropStage(name: '幼苗', s: 9, e: 24, sp: 18, ep: 36, tip: '追施稀薄氮肥，防菜青虫'),
        CropStage(name: '莲座', s: 24, e: 42, sp: 36, ep: 72, tip: '保持土壤湿润，均衡追肥'),
        CropStage(name: '成熟', s: 42, e: 58, sp: 72, ep: 100, tip: '叶球紧实时分批采收'),
      ],
    ),
  };

  static CropInfo? cropOf(String? id) => id == null ? null : crops[id];

  static SoilInfo soilOf(String key) => soils[key] ?? soils['loam']!;

  static IrrigationInfo irrigationOf(String key) =>
      irrigations[key] ?? irrigations['none']!;

  /// 初始演示状态（4 个田块）
  static CloudState seedState() {
    final now = DateTime.now();
    DateTime ago(int days) => now.subtract(Duration(days: days));
    DateTime hoursAgo(int hours) => now.subtract(Duration(hours: hours));

    return CloudState(
      plots: [
        CloudPlot(
          id: 'p1',
          name: '东坡油菜田',
          cropId: 'rapeseed',
          area: 12.9,
          plantedAt: ago(42),
          polygon: [
            [30.4080348, 112.1361896],
            [30.4080348, 112.1372104],
            [30.4088252, 112.1372104],
            [30.4088252, 112.1361896],
          ],
          soil: 'loam',
          irrigation: 'drip',
          fertilizer: '复合肥（15-15-15）',
          lastWaterAt: ago(13),
          lastFertAt: ago(26),
          lastCalibratedAt: ago(3),
          lastPestAt: null,
          lastSensedAt: hoursAgo(2),
          buildSource: 'GPS 边界 + RTK',
          logs: [
            PlotLog(t: ago(42), type: 'plant', title: '完成云种植建档', desc: '中双11号，12.9 亩，GPS 边界已按 1:1 建模'),
            PlotLog(t: ago(26), type: 'fert', title: '追施提苗肥', desc: '尿素 5kg/亩，人工撒施'),
            PlotLog(t: ago(13), type: 'water', title: '滴灌 15m³/亩', desc: 'AI 提醒后执行，墒情回升至 68%'),
            PlotLog(t: ago(3), type: 'sync', title: '实体长势校准', desc: '拍照比对，云田进度与实体偏差 -2%'),
          ],
        ),
        CloudPlot(
          id: 'p2',
          name: '河湾试验田',
          cropId: 'rapeseed',
          area: 14.5,
          plantedAt: ago(78),
          polygon: [
            [30.4064668, 112.1341632],
            [30.4064668, 112.1352568],
            [30.4072932, 112.1352568],
            [30.4072932, 112.1341632],
          ],
          soil: 'paddy',
          irrigation: 'sprinkler',
          fertilizer: '有机肥 + 复合肥',
          lastWaterAt: ago(5),
          lastFertAt: ago(12),
          lastCalibratedAt: ago(9),
          lastPestAt: null,
          lastSensedAt: hoursAgo(5),
          buildSource: 'GPS 边界 + 影像分割',
          logs: [
            PlotLog(t: ago(78), type: 'plant', title: '完成云种植建档', desc: '中双11号，14.5 亩，稻油轮作地块'),
            PlotLog(t: ago(46), type: 'fert', title: '追施薹肥', desc: '尿素 8kg/亩 + 氯化钾 3kg/亩'),
            PlotLog(t: ago(12), type: 'water', title: '喷灌 12m³/亩', desc: '结合降温作业'),
            PlotLog(t: ago(9), type: 'sync', title: '实体长势校准', desc: '无人机巡检照片比对，偏差 +1%'),
          ],
        ),
        CloudPlot(
          id: 'p3',
          name: '西塘小菜园',
          cropId: 'pakchoi',
          area: 7.8,
          plantedAt: ago(20),
          polygon: [
            [30.4054466, 112.1326450],
            [30.4054466, 112.1333950],
            [30.4060934, 112.1333950],
            [30.4060934, 112.1326450],
          ],
          soil: 'loam',
          irrigation: 'flood',
          fertilizer: '腐熟农家肥',
          lastWaterAt: ago(2),
          lastFertAt: ago(10),
          lastCalibratedAt: ago(2),
          lastPestAt: null,
          lastSensedAt: hoursAgo(1),
          buildSource: 'GPS 边界',
          logs: [
            PlotLog(t: ago(20), type: 'plant', title: '完成云种植建档', desc: '上海青，7.8 亩，一年多熟地块'),
            PlotLog(t: ago(10), type: 'fert', title: '追施稀薄氮肥', desc: '尿素 3kg/亩，随水冲施'),
            PlotLog(t: ago(2), type: 'water', title: '畦面漫灌', desc: '保持畦面湿润'),
          ],
        ),
        CloudPlot(
          id: 'p4',
          name: '南坡冬闲田',
          cropId: null,
          area: 10.2,
          plantedAt: null,
          polygon: [
            [30.4075950, 112.1376790],
            [30.4075950, 112.1387210],
            [30.4082050, 112.1387210],
            [30.4082050, 112.1376790],
          ],
          soil: 'loam',
          irrigation: 'sprinkler',
          fertilizer: '未施肥',
          lastWaterAt: ago(6),
          lastFertAt: ago(120),
          lastCalibratedAt: ago(1),
          lastPestAt: null,
          lastSensedAt: hoursAgo(3),
          buildSource: 'GPS 圈地',
          logs: [
            PlotLog(t: ago(1), type: 'build', title: '完成田块圈地建模', desc: 'GPS 边界 10.2 亩，等待选择作物'),
          ],
        ),
      ],
      settings: CloudSettings(),
    );
  }
}

/// 作物图标（替代原型 SVG）
IconData cropGlyph(String? cropId) {
  switch (cropId) {
    case 'rapeseed':
      return Icons.local_florist;
    case 'rice':
    case 'wheat':
      return Icons.grass;
    case 'corn':
      return Icons.energy_savings_leaf;
    case 'soybean':
      return Icons.spa;
    case 'pakchoi':
      return Icons.eco;
    default:
      return Icons.add;
  }
}

Color cropColor(String? cropId) {
  switch (cropId) {
    case 'rapeseed':
      return const Color(0xFFD99B00);
    case 'rice':
      return const Color(0xFF4A8B3B);
    case 'wheat':
      return const Color(0xFFB58A32);
    case 'corn':
      return const Color(0xFFC9822A);
    case 'soybean':
      return const Color(0xFF6A9A3F);
    case 'pakchoi':
      return const Color(0xFF3D8B46);
    default:
      return const Color(0xFF999999);
  }
}
