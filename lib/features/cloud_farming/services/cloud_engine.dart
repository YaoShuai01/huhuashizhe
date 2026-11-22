import 'dart:math';

import 'package:flutter/material.dart';

import '../models/cloud_models.dart';

/// 云种植纯计算引擎：生长模型、墒情推断、农事提醒、面积/边界计算。

enum CloudUrgency { high, medium, low }

enum CloudTone { red, amber, green, blue }

class GrowthInfo {
  final int rawDay;
  final int day;
  final int cycle;
  final int idx;
  final CropStage stage;
  final List<CropStage> stages;
  final CropInfo crop;
  final double pct;
  final CropStage? next;
  final int daysLeft;
  final int daysToNext;
  final int stagePct;

  const GrowthInfo({
    required this.rawDay,
    required this.day,
    required this.cycle,
    required this.idx,
    required this.stage,
    required this.stages,
    required this.crop,
    required this.pct,
    required this.next,
    required this.daysLeft,
    required this.daysToNext,
    required this.stagePct,
  });
}

class MoistureFactor {
  final String label;
  final double value;
  final String note;

  const MoistureFactor(this.label, this.value, this.note);
}

class MoistureInfo {
  final int value;
  final List<MoistureFactor> factors;
  final double daysSince;
  final SoilInfo soil;
  final IrrigationInfo irrigation;
  final int rain48;

  const MoistureInfo({
    required this.value,
    required this.factors,
    required this.daysSince,
    required this.soil,
    required this.irrigation,
    required this.rain48,
  });
}

class WaterAdvice {
  final CloudTone tone;
  final String text;

  const WaterAdvice(this.tone, this.text);
}

class CloudAlert {
  final String id;
  final String plotId;
  final String type;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String reason;
  final String window;
  final String actionText;
  final CloudUrgency urgency;

  const CloudAlert({
    required this.id,
    required this.plotId,
    required this.type,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.reason,
    required this.window,
    required this.actionText,
    required this.urgency,
  });

  String get urgencyLabel {
    switch (urgency) {
      case CloudUrgency.high:
        return '优先';
      case CloudUrgency.low:
        return '待办';
      case CloudUrgency.medium:
        return '建议';
    }
  }
}

class PlantingPlan {
  final CropInfo crop;
  final CloudPlot? plot;
  final MoistureInfo moisture;
  final int score;
  final DateTime sow;
  final DateTime harvest;
  final bool late;
  final String risk;
  final String firstWater;
  final int density;

  const PlantingPlan({
    required this.crop,
    required this.plot,
    required this.moisture,
    required this.score,
    required this.sow,
    required this.harvest,
    required this.late,
    required this.risk,
    required this.firstWater,
    required this.density,
  });
}

class CloudEngine {
  CloudEngine._();

  static const double _dayMs = 86400000;

  static double daysBetween(DateTime? a, DateTime b) {
    if (a == null) return 999;
    final diff = b.difference(a).inMilliseconds / _dayMs;
    return max(0, diff);
  }

  static String fmtDate(DateTime d) => '${d.month}月${d.day}日';

  static String fmtFull(DateTime d) => '${d.year}年${d.month}月${d.day}日';

  static String fmtMd(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String weekday(DateTime d) {
    const names = ['一', '二', '三', '四', '五', '六', '日'];
    return '周${names[d.weekday - 1]}';
  }

  static String fmtAgo(DateTime? iso, [DateTime? now]) {
    final n = now ?? DateTime.now();
    final d = daysBetween(iso, n);
    if (iso == null) return '暂无';
    if (d < 1) {
      final h = max(1, n.difference(iso).inHours);
      return '$h 小时前';
    }
    return '${d.floor()} 天前';
  }

  /// 生长模型
  static GrowthInfo? growth(CloudPlot plot, [DateTime? now]) {
    final crop = CloudSeed.cropOf(plot.cropId);
    if (crop == null || plot.plantedAt == null) return null;
    final n = now ?? DateTime.now();
    final rawDay = (n.difference(plot.plantedAt!).inMilliseconds / _dayMs).floor();
    final day = rawDay.clamp(0, crop.cycle);
    var idx = 0;
    for (var i = 0; i < crop.stages.length; i++) {
      if (day >= crop.stages[i].s) idx = i;
    }
    final stage = crop.stages[idx];
    final span = max(1, stage.e - stage.s);
    final inner = ((day - stage.s) / span).clamp(0.0, 1.0);
    final pct = plot.harvested
        ? 100.0
        : (stage.sp + (stage.ep - stage.sp) * inner + plot.pctOffset)
            .clamp(0.0, 100.0);
    final next = idx + 1 < crop.stages.length ? crop.stages[idx + 1] : null;
    return GrowthInfo(
      rawDay: rawDay,
      day: day,
      cycle: crop.cycle,
      idx: idx,
      stage: stage,
      stages: crop.stages,
      crop: crop,
      pct: pct,
      next: next,
      daysLeft: max(0, crop.cycle - day),
      daysToNext: next == null ? 0 : max(0, (next.s - day).ceil()),
      stagePct: (inner * 100).round(),
    );
  }

  /// 墒情推断
  static MoistureInfo moisture(CloudPlot plot, [DateTime? now]) {
    final g = growth(plot, now);
    return moistureFor(
      soilKey: plot.soil,
      irrigationKey: plot.irrigation,
      lastWaterAt: plot.lastWaterAt,
      stageIdx: g?.idx ?? 0,
      now: now,
    );
  }

  static MoistureInfo moistureFor({
    required String soilKey,
    required String irrigationKey,
    required DateTime? lastWaterAt,
    required int stageIdx,
    DateTime? now,
  }) {
    final weather = CloudSeed.weather;
    final soil = CloudSeed.soilOf(soilKey);
    final irr = CloudSeed.irrigationOf(irrigationKey);
    final daysSince = daysBetween(lastWaterAt, now ?? DateTime.now());
    final air = (weather.humidity - 65) * 0.25;
    final temp = -(weather.temp - 24) * 0.9;
    final rain = weather.rainLast3mm * 0.8;
    final evap = -daysSince * 1.6;
    const etTable = [0.0, 0.5, 1.0, 1.5, 2.5, 3.2, 3.8, 4.6, 3.2];
    final etDemand = -etTable[stageIdx.clamp(0, etTable.length - 1)];
    final raw = soil.base + irr.base + air + temp + rain + evap + etDemand;
    final value = raw.clamp(18.0, 92.0).round();
    final factors = <MoistureFactor>[
      MoistureFactor('土壤基础', soil.base.toDouble(), soil.name),
      MoistureFactor('灌溉条件', irr.base.toDouble(), irr.name),
      MoistureFactor('近3日降水', rain, '${weather.rainLast3mm}mm'),
      MoistureFactor('蒸发消耗', evap + etDemand, '${daysSince.floor()} 天未浇水'),
    ];
    if ((air + temp).abs() >= 0.5) {
      factors.add(MoistureFactor(
        '空气/温度',
        air + temp,
        '${weather.humidity}% · ${weather.temp}℃',
      ));
    }
    return MoistureInfo(
      value: value,
      factors: factors,
      daysSince: daysSince,
      soil: soil,
      irrigation: irr,
      rain48: weather.forecast[2].rain,
    );
  }

  static WaterAdvice waterAdvice(MoistureInfo m, int threshold) {
    if (m.value < threshold - 5) {
      if (m.rain48 >= 60) {
        return WaterAdvice(
          CloudTone.amber,
          '墒情 ${m.value}%，但未来 48 小时降水概率 ${m.rain48}%，建议暂缓灌溉，雨后再复测。',
        );
      }
      return WaterAdvice(
        CloudTone.red,
        '墒情 ${m.value}%，低于 $threshold% 阈值，建议今日 17:00—19:00 灌溉 15—18m³/亩。',
      );
    }
    if (m.value < threshold) {
      return WaterAdvice(
        CloudTone.amber,
        '墒情 ${m.value}%，接近下限（$threshold%），建议观察 1—2 天，优先傍晚小水勤浇。',
      );
    }
    if (m.value > 85) {
      return WaterAdvice(
        CloudTone.blue,
        '墒情 ${m.value}% 偏高，注意清沟排水，防止渍害与根系缺氧。',
      );
    }
    return WaterAdvice(CloudTone.green, '墒情 ${m.value}%，处于适宜区间，无需灌溉。');
  }

  /// 农事提醒
  static List<CloudAlert> alerts(
    CloudState state, {
    DateTime? now,
  }) {
    final out = <CloudAlert>[];
    final threshold = state.settings.moistureThreshold;
    final n = now ?? DateTime.now();
    final weather = CloudSeed.weather;
    final rain48 = weather.forecast[2].rain;

    for (final plot in state.plots) {
      final g = growth(plot, n);
      if (g == null || plot.harvested) continue;
      final crop = g.crop;
      final m = moisture(plot, n);
      final snoozeUntil = state.snoozed['${plot.id}:water'];

      if (m.value < threshold && (snoozeUntil == null || !snoozeUntil.isAfter(n))) {
        final high = m.value < threshold - 5;
        out.add(CloudAlert(
          id: '${plot.id}:water',
          plotId: plot.id,
          type: 'water',
          icon: Icons.water_drop_outlined,
          color: high ? const Color(0xFFD84343) : const Color(0xFFF59100),
          title: high
              ? '${plot.name}墒情偏低，建议傍晚灌溉'
              : '${plot.name}墒情偏低，48h 内有降雨',
          subtitle: 'AI 墒情推断 · ${g.stage.name}期',
          reason:
              'AI 推断土壤湿度 ${m.value}%（阈值 $threshold%）。依据：${m.soil.name}基础 ${m.soil.base}%、${m.irrigation.name}、近 3 日降水 ${weather.rainLast3mm}mm、${m.daysSince.floor()} 天未浇水、${crop.name}${g.stage.name}期耗水。未来 48h 降水概率 $rain48%。',
          window: high ? '今日 17:00—19:00' : '雨后再评估',
          actionText: high ? '确认灌溉' : '记录灌溉',
          urgency: high ? CloudUrgency.high : CloudUrgency.medium,
        ));
      }

      final daysFert = daysBetween(plot.lastFertAt, n);
      if (g.idx >= 3 && g.idx <= 5 && daysFert > 20) {
        late String title;
        late String amount;
        late String desc;
        if (g.idx == 3) {
          title = '追施提苗肥';
          amount = '尿素 5kg/亩';
          desc = '幼苗 3—5 叶期，促根壮苗';
        } else if (g.idx == 4) {
          title = '追施薹肥';
          amount = '尿素 8kg/亩 + 氯化钾 3kg/亩';
          desc = '蕾薹期是需肥高峰';
        } else {
          title = '叶面补硼';
          amount = '0.2% 硼砂溶液 30kg/亩';
          desc = '花期补硼防花而不实';
        }
        out.add(CloudAlert(
          id: '${plot.id}:fert',
          plotId: plot.id,
          type: 'fert',
          icon: Icons.science_outlined,
          color: const Color(0xFFF59100),
          title: '${plot.name}$title',
          subtitle: '${crop.name} · ${g.stage.name}期',
          reason:
              '距上次施肥 ${daysFert.floor()} 天；$desc。AI 结合长势模拟与阶段需肥曲线，建议按 $amount 施用，避开降雨时段。',
          window: '未来 3 天晴好时段',
          actionText: '记录施肥',
          urgency: CloudUrgency.medium,
        ));
      }

      final daysPest = plot.lastPestAt == null ? 99.0 : daysBetween(plot.lastPestAt, n);
      final pestRisk = (plot.cropId == 'rapeseed' &&
              g.idx >= 4 &&
              weather.humidity >= 72) ||
          (plot.cropId == 'pakchoi' && g.idx >= 3);
      if (pestRisk && daysPest > 10) {
        final rapeseed = plot.cropId == 'rapeseed';
        out.add(CloudAlert(
          id: '${plot.id}:pest',
          plotId: plot.id,
          type: 'pest',
          icon: Icons.shield_outlined,
          color: const Color(0xFF1E78C8),
          title: rapeseed ? '${plot.name}花期菌核病风险偏高' : '${plot.name}注意菜青虫防治',
          subtitle: '植保提醒 · 结合湿度与阶段',
          reason:
              '${weather.humidity}% 空气湿度、${weather.temp}℃ 气温，${crop.name}处于${g.stage.name}期，${rapeseed ? '菌核病与蚜虫' : '菜青虫与蚜虫'}进入高发窗口。建议抢晴喷施，避开开花授粉高峰。',
          window: '近 2 天下午',
          actionText: '标记已防治',
          urgency: CloudUrgency.medium,
        ));
      }

      final daysCal = daysBetween(plot.lastCalibratedAt, n);
      if (daysCal > state.settings.calibrateDays) {
        out.add(CloudAlert(
          id: '${plot.id}:cal',
          plotId: plot.id,
          type: 'calibrate',
          icon: Icons.photo_camera_outlined,
          color: const Color(0xFF5D6B62),
          title: '${plot.name}长势待校准',
          subtitle: '云田与实体同步',
          reason:
              '距上次校准 ${daysCal.floor()} 天（周期 ${state.settings.calibrateDays} 天）。建议拍摄田块照片或执行无人机巡田，AI 将比对株高、叶色与密度，修正云田进度。',
          window: '今日内',
          actionText: '去校准',
          urgency: CloudUrgency.low,
        ));
      }

      if (g.pct >= 97) {
        out.add(CloudAlert(
          id: '${plot.id}:harvest',
          plotId: plot.id,
          type: 'harvest',
          icon: Icons.check_circle_outline,
          color: const Color(0xFF2E7D32),
          title: '${plot.name}已到成熟期，可安排采收',
          subtitle: '生长进度 ${g.pct.round()}%',
          reason:
              '${crop.name}已完成全生育期 ${g.cycle} 天的 ${g.pct.round()}%，${g.stage.tip}。',
          window: '未来 3—5 天',
          actionText: '记录采收',
          urgency: CloudUrgency.medium,
        ));
      }
    }

    out.sort((a, b) => a.urgency.index.compareTo(b.urgency.index));
    return out;
  }

  /// 面积（亩）
  static double areaMu(List<List<double>> points) {
    if (points.length < 3) return 0;
    final lat0 = points.fold<double>(0, (s, p) => s + p[0]) /
        points.length *
        pi /
        180;
    const r = 6378137.0;
    var sum = 0.0;
    for (var i = 0; i < points.length; i++) {
      final a = points[i];
      final b = points[(i + 1) % points.length];
      final x1 = a[1] * pi / 180 * r * cos(lat0);
      final y1 = a[0] * pi / 180 * r;
      final x2 = b[1] * pi / 180 * r * cos(lat0);
      final y2 = b[0] * pi / 180 * r;
      sum += x1 * y2 - x2 * y1;
    }
    return (sum / 2).abs() / 666.6667;
  }

  /// 周长（米）
  static int perimeterM(List<List<double>> points) {
    if (points.length < 2) return 0;
    final lat0 = points.first[0] * pi / 180;
    var sum = 0.0;
    for (var i = 0; i < points.length; i++) {
      final a = points[i];
      final b = points[(i + 1) % points.length];
      final dx = (b[1] - a[1]) * 111320 * cos(lat0);
      final dy = (b[0] - a[0]) * 111320;
      sum += sqrt(dx * dx + dy * dy);
    }
    return sum.round();
  }

  /// 边界包围盒尺寸（米）
  static Size sizeM(List<List<double>> points) {
    if (points.length < 2) return Size.zero;
    final lats = points.map((p) => p[0]);
    final lngs = points.map((p) => p[1]);
    final maxLat = lats.reduce(max);
    final minLat = lats.reduce(min);
    final maxLng = lngs.reduce(max);
    final minLng = lngs.reduce(min);
    final lat0 = (maxLat + minLat) / 2 * pi / 180;
    final h = (maxLat - minLat) * 111320;
    final w = (maxLng - minLng) * 111320 * cos(lat0);
    return Size(w.roundToDouble(), h.roundToDouble());
  }

  /// 圈地自动识别
  static List<List<double>> autoDetectPoints(int plotCount) {
    final cLat = 30.40710 + (plotCount % 2) * 0.00042;
    final cLng = 112.13890 + (plotCount % 2) * 0.00060;
    final dLat = 34 / 111320;
    final dLng = 46 / (111320 * cos(cLat * pi / 180));
    return [
      [cLat - dLat, cLng - dLng],
      [cLat - dLat, cLng + dLng],
      [cLat + dLat, cLng + dLng],
      [cLat + dLat, cLng - dLng],
    ];
  }

  static DateTime? fertDate(String age, DateTime now) {
    switch (age) {
      case '7d':
        return now.subtract(const Duration(days: 7));
      case '15d':
        return now.subtract(const Duration(days: 15));
      case '30d':
        return now.subtract(const Duration(days: 30));
      default:
        return now.subtract(const Duration(days: 365));
    }
  }

  /// 生成种植方案（AI 适宜度与墒情推断）
  static PlantingPlan inferPlan({
    required CropInfo crop,
    required CloudPlot? plot,
    required String soil,
    required String irrigation,
    required DateTime sow,
    required String fertAge,
  }) {
    final now = DateTime.now();
    final m = moistureFor(
      soilKey: soil,
      irrigationKey: irrigation,
      lastWaterAt: now,
      stageIdx: 0,
      now: now,
    );
    var score = crop.suitability.toDouble();
    if (soil == 'sandy') score -= 5;
    if (soil == 'clay' && crop.id == 'rapeseed') score -= 3;
    if (irrigation == 'none' && crop.waterNeed == '较高') score -= 6;
    var late = false;
    if (crop.id == 'rapeseed' && sow.month >= 11) {
      score -= 8;
      late = true;
    }
    if (crop.id == 'wheat' && sow.month >= 12) {
      score -= 6;
      late = true;
    }
    score = score.clamp(60.0, 98.0);
    final harvest = sow.add(Duration(days: crop.cycle));
    final soilInfo = CloudSeed.soilOf(soil);
    final irrInfo = CloudSeed.irrigationOf(irrigation);
    final risk = late
        ? '已过本地最佳播期（${crop.sowWindow}），${crop.name}晚播需提高密度 10%—15%，越冬前重点培育壮苗。'
        : '${crop.reason}${soilInfo.desc}；${irrInfo.name}条件下${m.value < 60 ? '播后需及时补墒' : '墒情可满足出苗'}。';
    return PlantingPlan(
      crop: crop,
      plot: plot,
      moisture: m,
      score: score.round(),
      sow: sow,
      harvest: harvest,
      late: late,
      risk: risk,
      firstWater: m.value < 60 ? '播后 3 天内补墒' : '播后 7 天复查墒情',
      density: (crop.density * (late ? 1.12 : 1)).round(),
    );
  }

  static Color toneColor(CloudTone tone) {
    switch (tone) {
      case CloudTone.red:
        return const Color(0xFFD84343);
      case CloudTone.amber:
        return const Color(0xFFB96B00);
      case CloudTone.blue:
        return const Color(0xFF1E78C8);
      case CloudTone.green:
        return const Color(0xFF2E7D32);
    }
  }
}
