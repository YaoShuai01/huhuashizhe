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
    // 异步触发首次刷新，不阻塞UI渲染
    refresh();
    return null;
  }

  void _startAutoRefresh() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 15), (_) => refresh());
  }

  Future<void> refresh() async {
    final weatherService = ref.read(weatherServiceProvider);
    // 优先使用GPS定位，超时或失败时回退到上海默认坐标
    double lat = 31.23, lng = 121.47;
    try {
      final pos = await GpsLocationService.getCurrentLocation()
          .timeout(const Duration(seconds: 5));
      if (pos != null) {
        lat = pos['lat']!;
        lng = pos['lng']!;
      }
    } catch (_) {
      // GPS超时或失败，使用默认坐标
    }

    WeatherData? weather;
    try {
      weather = await weatherService.fetchWeather(lat, lng);
    } catch (_) {
      // 天气API请求失败
    }

    if (weather != null) {
      // 先立即显示天气（地名先用"当前位置"），避免逆地理编码阻塞
      final w = weather;
      state = AsyncData(WeatherData(
        temperature: w.temperature,
        windSpeed: w.windSpeed,
        windDirection: w.windDirection,
        humidity: w.humidity,
        weatherCode: w.weatherCode,
        weatherDescription: w.weatherDescription,
        precipitationProbability: w.precipitationProbability,
        locationName: '当前位置',
      ));

      // 使用Android原生Geocoder做逆地理编码（国内可用），完成后更新地名
      GpsLocationService.reverseGeocode(lat, lng).then((address) {
        if (address != null) {
          state = AsyncData(WeatherData(
            temperature: w.temperature,
            windSpeed: w.windSpeed,
            windDirection: w.windDirection,
            humidity: w.humidity,
            weatherCode: w.weatherCode,
            weatherDescription: w.weatherDescription,
            precipitationProbability: w.precipitationProbability,
            locationName: '当前位置  |  $address',
          ));
        }
      });
    } else {
      // 天气获取失败时显示错误提示
      state = const AsyncData(WeatherData(
        temperature: 0,
        windSpeed: 0,
        windDirection: 0,
        humidity: 0,
        weatherCode: 0,
        weatherDescription: '无法获取天气',
        precipitationProbability: 0,
        locationName: '当前位置',
      ));
    }
  }
}