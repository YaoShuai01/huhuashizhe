import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/weather_service.dart';
import '../services/gps_location_service.dart';

final weatherServiceProvider = Provider<WeatherService>((ref) => WeatherService());
final weatherProvider = AsyncNotifierProvider<WeatherNotifier, WeatherData?>(WeatherNotifier.new);

class WeatherNotifier extends AsyncNotifier<WeatherData?> {
  Timer? _timer;

  @override
  Future<WeatherData?> build() async {
    ref.onDispose(() => _timer?.cancel());
    _startAutoRefresh();
    refresh();
    return null;
  }

  void _startAutoRefresh() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 15), (_) => refresh());
  }

  Future<void> refresh() async {
    final weatherService = ref.read(weatherServiceProvider);

    // 获取GPS+北斗双轨定位
    double? lat, lng;
    try {
      final pos = await GpsLocationService.getCurrentLocation()
          .timeout(const Duration(seconds: 12));
      if (pos != null) {
        lat = pos.lat;
        lng = pos.lng;
      }
    } catch (_) {}

    if (lat == null || lng == null) {
      state = const AsyncData(WeatherData(
        temperature: 0, windSpeed: 0, windDirection: 0, humidity: 0,
        weatherCode: 0, weatherDescription: '无法获取天气',
        precipitationProbability: 0, locationName: '无法获取定位',
      ));
      return;
    }

    // 使用Android原生Geocoder逆地理编码，获取城市名+区名
    String? geocodeResult;
    try {
      geocodeResult = await GpsLocationService.reverseGeocode(lat, lng);
    } catch (_) {}

    // 解析地名：格式 "市 · 区 · 镇" 或 "市 · 区"
    String cityName = '';
    String? districtName;
    if (geocodeResult != null && geocodeResult.isNotEmpty) {
      final parts = geocodeResult.split(' · ');
      if (parts.isNotEmpty) cityName = parts[0];
      if (parts.length > 1) districtName = parts[1];
    }

    // 查找城市代码
    final cityCode = await weatherService.findCityCode(cityName, districtName);
    if (cityCode == null) {
      state = const AsyncData(WeatherData(
        temperature: 0, windSpeed: 0, windDirection: 0, humidity: 0,
        weatherCode: 0, weatherDescription: '未知城市',
        precipitationProbability: 0, locationName: '无法匹配城市',
      ));
      return;
    }

    // 获取天气数据
    WeatherData? weather;
    try {
      weather = await weatherService.fetchWeather(cityCode);
    } catch (_) {}

    if (weather != null) {
      final locationDisplay = geocodeResult ?? weather.locationName;
      state = AsyncData(WeatherData(
        temperature: weather.temperature,
        windSpeed: weather.windSpeed,
        windDirection: weather.windDirection,
        humidity: weather.humidity,
        weatherCode: weather.weatherCode,
        weatherDescription: weather.weatherDescription,
        precipitationProbability: weather.precipitationProbability,
        locationName: '当前位置  |  $locationDisplay',
      ));
    } else {
      state = const AsyncData(WeatherData(
        temperature: 0, windSpeed: 0, windDirection: 0, humidity: 0,
        weatherCode: 0, weatherDescription: '无法获取天气',
        precipitationProbability: 0, locationName: '当前位置',
      ));
    }
  }
}