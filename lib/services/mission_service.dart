import 'dart:math';
import 'package:latlong2/latlong.dart';

class MissionService {
  static double calculatePolygonArea(List<Map<String, double>> points) {
    if (points.length < 3) return 0;

    const double earthRadius = 6371000.0;
    double area = 0;

    for (int i = 0; i < points.length; i++) {
      int j = (i + 1) % points.length;
      double lat1 = points[i]['lat']! * pi / 180;
      double lat2 = points[j]['lat']! * pi / 180;
      double dLon = (points[j]['lng']! - points[i]['lng']!) * pi / 180;

      area += dLon * (2 + sin(lat1) + sin(lat2));
    }

    area = area.abs() * earthRadius * earthRadius / 2;
    return area / 666.67;
  }

  /// 接受LatLng列表的多边形面积计算（地图页面使用）
  static double calculatePolygonAreaLatLng(List<LatLng> points) {
    if (points.length < 3) return 0;

    const double earthRadius = 6371000.0;
    double area = 0;

    for (int i = 0; i < points.length; i++) {
      int j = (i + 1) % points.length;
      double lat1 = points[i].latitude * pi / 180;
      double lat2 = points[j].latitude * pi / 180;
      double dLon = (points[j].longitude - points[i].longitude) * pi / 180;

      area += dLon * (2 + sin(lat1) + sin(lat2));
    }

    area = area.abs() * earthRadius * earthRadius / 2;
    return area / 666.67;
  }

  static String estimateTime(double areaMu, double speedMS, double sprayWidthM) {
    final effectiveWidth = sprayWidthM * 0.8;
    final totalDistance = (areaMu * 666.67) / effectiveWidth;
    final timeSeconds = totalDistance / speedMS;
    final minutes = (timeSeconds / 60).ceil();
    if (minutes < 60) return '$minutes 分钟';
    return '${minutes ~/ 60} 小时 ${minutes % 60} 分钟';
  }

  static double estimateMedicine(double areaMu, double sprayVolumePerMu) {
    return areaMu * sprayVolumePerMu;
  }
}
