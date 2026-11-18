import 'package:flutter/services.dart';

/// 单颗 GNSS 卫星的实时状态
class GnssSatellite {
  /// 星座：gps / beidou / glonass / galileo / unknown
  final String system;
  final int svid;

  /// 方位角，0=正北，顺时针
  final double azimuth;

  /// 仰角，0~90 度
  final double elevation;

  /// 载噪比 dB-Hz
  final double snr;

  /// 是否参与定位解算
  final bool usedInFix;

  const GnssSatellite({
    required this.system,
    required this.svid,
    required this.azimuth,
    required this.elevation,
    required this.snr,
    required this.usedInFix,
  });

  factory GnssSatellite.fromMap(Map<dynamic, dynamic> map) {
    return GnssSatellite(
      system: map['system'] as String? ?? 'unknown',
      svid: (map['svid'] as num?)?.toInt() ?? 0,
      azimuth: (map['azimuth'] as num?)?.toDouble() ?? 0,
      elevation: (map['elevation'] as num?)?.toDouble() ?? 0,
      snr: (map['snr'] as num?)?.toDouble() ?? 0,
      usedInFix: map['used'] as bool? ?? false,
    );
  }
}

/// 一次 GNSS 卫星状态快照
class GnssSnapshot {
  final int total;
  final int used;
  final Map<String, int> counts;
  final List<GnssSatellite> satellites;
  final DateTime timestamp;

  const GnssSnapshot({
    required this.total,
    required this.used,
    required this.counts,
    required this.satellites,
    required this.timestamp,
  });

  factory GnssSnapshot.fromMap(Map<dynamic, dynamic> map) {
    final countsRaw = map['counts'] as Map? ?? const {};
    final counts = countsRaw.map(
      (key, value) => MapEntry(key.toString(), (value as num?)?.toInt() ?? 0),
    );
    final listRaw = map['satellites'] as List? ?? const [];
    final satellites = listRaw
        .whereType<Map>()
        .map((item) => GnssSatellite.fromMap(item))
        .toList(growable: false);

    return GnssSnapshot(
      total: (map['total'] as num?)?.toInt() ?? satellites.length,
      used: (map['used'] as num?)?.toInt() ??
          satellites.where((s) => s.usedInFix).length,
      counts: counts,
      satellites: satellites,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (map['timestamp'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  /// 指定星座的卫星列表
  List<GnssSatellite> satellitesOf(String system) =>
      satellites.where((s) => s.system == system).toList(growable: false);

  /// 指定星座搜到的数量
  int foundOf(String system) => satellitesOf(system).length;

  /// 指定星座参与定位的数量
  int usedOf(String system) =>
      satellitesOf(system).where((s) => s.usedInFix).length;
}

/// 原生 GNSS 卫星与罗盘方向事件服务
///
/// - [gnssStream]：逐星方位/仰角/信噪比 + 各星座数量
/// - [headingStream]：手机相对屏幕顶部的朝向（0=正北，顺时针）
class SatelliteService {
  SatelliteService._();

  static const _gnssChannel = EventChannel('com.huhuashizhe/gnss_events');
  static const _compassChannel = EventChannel('com.huhuashizhe/compass_events');

  static Stream<GnssSnapshot> get gnssStream => _gnssChannel
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map((event) => GnssSnapshot.fromMap(event as Map));

  static Stream<double> get headingStream => _compassChannel
      .receiveBroadcastStream()
      .where((event) => event is Map && event['heading'] is num)
      .map((event) => ((event as Map)['heading'] as num).toDouble());
}
