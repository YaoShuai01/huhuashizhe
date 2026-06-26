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
    // 启动时立即获取天气
    await refresh();
    return state.valueOrNull;
  }

  void _startAutoRefresh() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 15), (_) => refresh());
  }

  Future<void> refresh() async {
    final weatherService = ref.read(weatherServiceProvider);
    // 优先使用GPS定位获取当前位置的天气，失败时回退到上海默认坐标
    double lat = 31.23, lng = 121.47;
    final pos = await GpsLocationService.getCurrentLocation();
    if (pos != null) {
      lat = pos['lat']!;
      lng = pos['lng']!;
    }
    final weather = await weatherService.fetchWeather(lat, lng);
    if (weather != null) {
      // 逆地理编码获取地名
      final address = await weatherService.reverseGeocode(lat, lng);
      final locationStr = address != null ? '当前位置  |  $address' : '当前位置';
      state = AsyncData(WeatherData(
        temperature: weather.temperature,
        windSpeed: weather.windSpeed,
        windDirection: weather.windDirection,
        humidity: weather.humidity,
        weatherCode: weather.weatherCode,
        weatherDescription: weather.weatherDescription,
        precipitationProbability: weather.precipitationProbability,
        locationName: locationStr,
      ));
    }
  }
}