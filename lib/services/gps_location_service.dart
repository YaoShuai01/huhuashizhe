import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

/// 定位结果
class GpsLocation {
  final double lat;
  final double lng;
  final double accuracy;
  final String provider;
  final int timestamp;
  final Map<String, int>? satellites;

  const GpsLocation({
    required this.lat,
    required this.lng,
    this.accuracy = 0,
    this.provider = '',
    this.timestamp = 0,
    this.satellites,
  });

  LatLng get latLng => LatLng(lat, lng);
}

/// 原生GPS+北斗双轨定位服务（通过MethodChannel直接调用Android LocationManager）
class GpsLocationService {
  static const _channel = MethodChannel('com.huhuashizhe/location');

  /// 全局缓存的最后一次定位
  static GpsLocation? _cachedLocation;
  static GpsLocation? get cachedLocation => _cachedLocation;

  /// 获取当前位置（带卫星信息），失败返回null
  static Future<GpsLocation?> getCurrentLocation() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getLocation');
      if (result != null) {
        final lat = (result['lat'] as num).toDouble();
        final lng = (result['lng'] as num).toDouble();
        final accuracy = (result['accuracy'] as num?)?.toDouble() ?? 0;
        final provider = result['provider'] as String? ?? '';
        final timestamp = (result['timestamp'] as num?)?.toInt() ?? 0;
        final satellitesRaw = result['satellites'] as Map<dynamic, dynamic>?;
        final satellites = satellitesRaw?.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));

        final loc = GpsLocation(
          lat: lat, lng: lng,
          accuracy: accuracy,
          provider: provider,
          timestamp: timestamp,
          satellites: satellites,
        );
        _cachedLocation = loc;
        return loc;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 获取当前位置（简化版，返回 {lat, lng}）
  static Future<Map<String, double>?> getCurrentPosition() async {
    final loc = await getCurrentLocation();
    if (loc != null) {
      return {'lat': loc.lat, 'lng': loc.lng};
    }
    return null;
  }

  /// 获取当前GNSS卫星信息（北斗/GPS/GLONASS/Galileo）
  static Future<Map<String, int>?> getSatelliteInfo() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getSatelliteInfo');
      if (result != null) {
        return result.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 逆地理编码：根据经纬度获取地名
  static Future<String?> reverseGeocode(double lat, double lng) async {
    try {
      final result = await _channel.invokeMethod<String>('reverseGeocode', {
        'lat': lat,
        'lng': lng,
      });
      return result;
    } catch (e) {
      return null;
    }
  }
}