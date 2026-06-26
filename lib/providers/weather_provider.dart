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

    final weather = await weatherService.fetchWeather(lat, lng);
    if (weather != null) {
      // 先立即显示天气（地名先用"当前位置"），避免逆地理编码阻塞
      state = AsyncData(WeatherData(
        temperature: weather.temperature,
        windSpeed: weather.windSpeed,
        windDirection: weather.windDirection,
        humidity: weather.humidity,
        weatherCode: weather.weatherCode,
        weatherDescription: weather.weatherDescription,
        precipitationProbability: weather.precipitationProbability,
        locationName: '当前位置',
      ));

      // 逆地理编码在后台执行，完成后更新地名
      weatherService.reverseGeocode(lat, lng).then((address) {
        if (address != null) {
          state = AsyncData(WeatherData(
            temperature: weather.temperature,
            windSpeed: weather.windSpeed,
            windDirection: weather.windDirection,
            humidity: weather.humidity,
            weatherCode: weather.weatherCode,
            weatherDescription: weather.weatherDescription,
            precipitationProbability: weather.precipitationProbability,
            locationName: '当前位置  |  $address',
          ));
        }
      });
    }
  }
}