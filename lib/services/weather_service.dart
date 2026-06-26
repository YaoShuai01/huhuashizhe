import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class WeatherData {
  final double temperature;
  final double windSpeed;
  final double windDirection;
  final double humidity;
  final int weatherCode;
  final String weatherDescription;
  final int precipitationProbability;
  final String locationName;

  const WeatherData({
    required this.temperature,
    required this.windSpeed,
    required this.windDirection,
    required this.humidity,
    required this.weatherCode,
    required this.weatherDescription,
    required this.precipitationProbability,
    this.locationName = '',
  });

  factory WeatherData.empty() => const WeatherData(
        temperature: 0,
        windSpeed: 0,
        windDirection: 0,
        humidity: 0,
        weatherCode: 0,
        weatherDescription: '未知',
        precipitationProbability: 0,
      );

  bool get isWindWarning => windSpeed > 8.0;
  bool get isRainWarning => precipitationProbability > 60;

  String get weatherIcon {
    if (weatherCode <= 3) return '☀️';
    if (weatherCode <= 48) return '☁️';
    if (weatherCode <= 57) return '🌧️';
    if (weatherCode <= 67) return '🌨️';
    if (weatherCode <= 77) return '❄️';
    if (weatherCode <= 82) return '🌧️';
    return '⛈️';
  }
}

class WeatherService {
  static const _baseUrl = 'https://api.open-meteo.com/v1/forecast';
  static const _geoUrl = 'https://nominatim.openstreetmap.org/reverse';
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  /// 逆地理编码：根据经纬度获取地名（省·市·区·镇）
  Future<String?> reverseGeocode(double lat, double lng) async {
    try {
      final response = await _dio.get(_geoUrl, queryParameters: {
        'lat': lat,
        'lon': lng,
        'format': 'json',
        'zoom': 14,
        'accept-language': 'zh',
      });
      if (response.statusCode == 200) {
        final address = response.data['address'] as Map<String, dynamic>?;
        if (address != null) {
          final parts = <String>[];
          final province = address['province']?.toString() ?? '';
          final city = address['city']?.toString() ?? '';
          final district = address['district']?.toString() ?? '';
          final town = address['town']?.toString() ?? '';

          // 直辖市省份与城市名相同则跳过省份
          if (province.isNotEmpty && province != city) parts.add(province);
          if (city.isNotEmpty) parts.add(city);
          if (district.isNotEmpty && district != city) parts.add(district);
          if (town.isNotEmpty) parts.add(town);

          return parts.isNotEmpty ? parts.join(' · ') : null;
        }
      }
    } catch (e) {
      debugPrint('Reverse geocode error: $e');
    }
    return null;
  }

  Future<WeatherData?> fetchWeather(double lat, double lng) async {
    try {
      final response = await _dio.get(_baseUrl, queryParameters: {
        'latitude': lat,
        'longitude': lng,
        'current': [
          'temperature_2m',
          'relative_humidity_2m',
          'wind_speed_10m',
          'wind_direction_10m',
          'weather_code',
          'precipitation_probability',
        ],
        'timezone': 'Asia/Shanghai',
        'forecast_days': 1,
      });
      if (response.statusCode == 200) {
        final current = response.data['current'] as Map<String, dynamic>;
        final code = (current['weather_code'] as num).toInt();
        return WeatherData(
          temperature: (current['temperature_2m'] as num).toDouble(),
          windSpeed: (current['wind_speed_10m'] as num).toDouble(),
          windDirection: (current['wind_direction_10m'] as num).toDouble(),
          humidity: (current['relative_humidity_2m'] as num).toDouble(),
          weatherCode: code,
          weatherDescription: _desc(code),
          precipitationProbability:
              (current['precipitation_probability'] as num?)?.toInt() ?? 0,
        );
      }
    } catch (e) {
      debugPrint('Weather error: $e');
    }
    return null;
  }

  static String _desc(int code) {
    if (code == 0) return '晴';
    if (code <= 3) return '多云';
    if (code <= 48) return '雾/霾';
    if (code <= 57) return '小雨';
    if (code <= 67) return '雨/雪';
    if (code <= 77) return '雪';
    if (code <= 82) return '大雨';
    if (code <= 86) return '暴雪';
    return '雷暴';
  }
}