import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/weather_service.dart';

final weatherServiceProvider = Provider<WeatherService>((ref) => WeatherService());
final weatherProvider = AsyncNotifierProvider<WeatherNotifier, WeatherData?>(WeatherNotifier.new);

class WeatherNotifier extends AsyncNotifier<WeatherData?> {
  Timer? _timer;

  @override
  Future<WeatherData?> build() async {
    ref.onDispose(() => _timer?.cancel());
    _startAutoRefresh();
    return null;
  }

  void _startAutoRefresh() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 15), (_) => refresh());
  }

  Future<void> refresh() async {
    final weatherService = ref.read(weatherServiceProvider);
    // 使用默认位置（上海）获取天气，后续接入定位服务后替换
    final weather = await weatherService.fetchWeather(31.23, 121.47);
    if (weather != null) {
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
    }
  }
}