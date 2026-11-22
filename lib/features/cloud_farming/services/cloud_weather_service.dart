import 'package:flutter/foundation.dart';

import '../../../services/weather_service.dart';
import '../models/cloud_models.dart';

/// 云种植天气获取结果（失败时给出可展示原因，绝不返回推测数据）
class CloudWeatherResult {
  final CloudWeatherSnapshot? snapshot;
  final String? error;

  const CloudWeatherResult._(this.snapshot, this.error);

  const CloudWeatherResult.success(CloudWeatherSnapshot snapshot)
      : this._(snapshot, null);

  const CloudWeatherResult.failure(String message) : this._(null, message);

  bool get ok => snapshot != null;
}

/// 云种植天气链路：逆地理名称 → 城市代码 → 实况 + 四日预报
class CloudWeatherService {
  final WeatherService _weather;

  CloudWeatherService([WeatherService? weather])
      : _weather = weather ?? WeatherService();

  Future<CloudWeatherResult> fetch({
    required double lat,
    required double lng,
    required String locationName,
  }) async {
    final place = _parsePlace(locationName);
    if (place == null) {
      return const CloudWeatherResult.failure('无法匹配城市，天气暂不可用');
    }

    String? cityCode;
    try {
      cityCode = await _weather
          .findCityCode(place.$1, place.$2)
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[CloudWeather] 城市匹配失败: $e');
    }
    if (cityCode == null || cityCode.isEmpty) {
      return const CloudWeatherResult.failure('无法匹配城市，天气暂不可用');
    }

    WeatherData? current;
    List<ForecastDay>? forecast;
    try {
      final results = await Future.wait<Object?>([
        _weather.fetchWeather(cityCode),
        _weather.fetchForecast(cityCode),
      ]).timeout(const Duration(seconds: 10));
      current = results[0] as WeatherData?;
      forecast = results[1] as List<ForecastDay>?;
    } catch (e) {
      debugPrint('[CloudWeather] 实况/预报获取失败: $e');
    }

    if (current == null) {
      return const CloudWeatherResult.failure('天气服务暂不可用，请检查网络');
    }

    final days = <CloudForecastDay>[
      for (final d in (forecast ?? const <ForecastDay>[]).take(4))
        CloudForecastDay(
          label: d.label,
          date: d.date,
          desc: d.weather,
          high: d.high,
          low: d.low,
          rain: d.rainProb,
          icon: d.icon,
          wind: d.wind,
        ),
    ];

    final snapshot = CloudWeatherSnapshot(
      temp: current.temperature,
      low: days.isNotEmpty ? days.first.low : current.temperature.round(),
      desc: current.weatherDescription.isEmpty
          ? '未知'
          : current.weatherDescription,
      humidity: current.humidity.round(),
      wind: current.windSpeed,
      windDir: _windDirText(current.windDirection, current.windSpeed),
      rainProb: current.precipitationProbability,
      rainLast3mm: null,
      forecast: days,
      updatedAt: DateTime.now(),
      source: '中国天气网',
    );
    debugPrint('[CloudWeather] 获取成功: ${snapshot.temp}℃, '
        '${snapshot.desc}, 预报 ${days.length} 天');
    return CloudWeatherResult.success(snapshot);
  }

  /// 解析逆地理名称，格式为“市 · 区 · 镇”；无法拆出城市时返回 null
  (String, String?)? _parsePlace(String name) {
    final parts = name
        .split(RegExp(r'\s*[·•]\s*'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.length >= 2) return (parts[0], parts[1]);
    if (parts.length == 1) {
      final single = parts[0];
      final cityEnd = single.indexOf('市');
      if (cityEnd >= 0) {
        final city = single.substring(0, cityEnd + 1);
        final rest = single.substring(cityEnd + 1).trim();
        return (city, rest.isEmpty ? null : rest);
      }
      if (RegExp(r'[区县州]').hasMatch(single)) return (single, null);
    }
    return null;
  }

  String _windDirText(double degrees, double speed) {
    if (speed <= 0) return '无风';
    const dirs = ['北风', '东北风', '东风', '东南风', '南风', '西南风', '西风', '西北风'];
    final index = (((degrees + 22.5) % 360) ~/ 45).clamp(0, 7);
    return dirs[index];
  }
}
