import 'package:flutter/services.dart';

/// 原生GPS定位服务（通过MethodChannel直接调用Android LocationManager）
class GpsLocationService {
  static const _channel = MethodChannel('com.huhuashizhe/location');

  /// 获取当前位置，返回 {lat: double, lng: double}，失败返回null
  static Future<Map<String, double>?> getCurrentLocation() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getLocation');
      if (result != null) {
        return {
          'lat': (result['lat'] as num).toDouble(),
          'lng': (result['lng'] as num).toDouble(),
        };
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}