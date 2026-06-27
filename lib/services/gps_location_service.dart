import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

/// 原生GPS定位服务（通过MethodChannel直接调用Android LocationManager）
class GpsLocationService {
  static const _channel = MethodChannel('com.huhuashizhe/location');

  /// 全局缓存的最后一次GPS定位（WGS-84坐标），应用启动后首次获取即缓存
  static LatLng? _cachedLocation;
  static LatLng? get cachedLocation => _cachedLocation;

  /// 获取当前位置，返回 {lat: double, lng: double}，失败返回null
  static Future<Map<String, double>?> getCurrentLocation() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getLocation');
      if (result != null) {
        final lat = (result['lat'] as num).toDouble();
        final lng = (result['lng'] as num).toDouble();
        _cachedLocation = LatLng(lat, lng);
        return {'lat': lat, 'lng': lng};
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 逆地理编码：根据经纬度获取地名（使用Android原生Geocoder，国内可用）
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