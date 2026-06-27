import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

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

/// 中国天气网天气服务（数据来源：中国气象局，与手机系统天气一致）
class WeatherService {
  static const _skUrl = 'http://www.weather.com.cn/data/sk';
  static const _cityinfoUrl = 'http://www.weather.com.cn/data/cityinfo';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
  ));

  Map<String, String>? _cityCodes;

  /// 加载城市代码映射表
  Future<Map<String, String>> _loadCityCodes() async {
    if (_cityCodes != null) return _cityCodes!;
    final jsonStr = await rootBundle.loadString('assets/city_codes.json');
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    _cityCodes = map.map((k, v) => MapEntry(k, v.toString()));
    return _cityCodes!;
  }

  /// 根据城市名/区名查找weather.com.cn代码，精确到区县级
  Future<String?> findCityCode(String cityName, String? districtName) async {
    final codes = await _loadCityCodes();

    // 去掉"市"、"区"、"县"等后缀做匹配
    String clean(String s) => s
        .replaceAll('市', '')
        .replaceAll('区', '')
        .replaceAll('县', '')
        .replaceAll('自治州', '')
        .replaceAll('自治县', '')
        .replaceAll('地区', '')
        .trim();

    final cleanCity = clean(cityName);
    final cleanDistrict = districtName != null ? clean(districtName) : null;

    // 优先匹配区/县级
    if (cleanDistrict != null && cleanDistrict.isNotEmpty) {
      final districtCode = codes[cleanDistrict];
      if (districtCode != null) return districtCode;
    }

    // 回退匹配市级
    final cityCode = codes[cleanCity];
    if (cityCode != null) return cityCode;

    // 模糊匹配：检查是否包含关键词
    for (final entry in codes.entries) {
      if (cleanCity.contains(entry.key) || entry.key.contains(cleanCity)) {
        return entry.value;
      }
    }

    return null;
  }

  /// 获取实时天气（中国天气网sk接口）
  Future<WeatherData?> fetchWeather(String cityCode) async {
    try {
      final response = await _dio.get('$_skUrl/$cityCode.html');
      if (response.statusCode == 200) {
        final info = response.data['weatherinfo'] as Map<String, dynamic>?;
        if (info == null) return null;

        final temp = double.tryParse(info['temp']?.toString() ?? '') ?? 0.0;
        final sd = double.tryParse(info['SD']?.toString()?.replaceAll('%', '') ?? '') ?? 0.0;
        final wd = info['WD']?.toString() ?? '无风';
        final ws = info['WS']?.toString() ?? '0级';
        final wse = double.tryParse(info['WSE']?.toString() ?? '') ?? 0.0;
        final city = info['city']?.toString() ?? '';
        final rain = double.tryParse(info['rain']?.toString() ?? '') ?? 0.0;

        // 风速等级转m/s（中国天气网WS是风力等级，如"3级"）
        double windSpeed = wse; // WSE是风速数值
        if (windSpeed == 0) {
          windSpeed = _windLevelToSpeed(ws);
        }

        // 风向文字转角度
        final windDirection = _windDirToDegrees(wd);

        return WeatherData(
          temperature: temp,
          windSpeed: windSpeed,
          windDirection: windDirection,
          humidity: sd,
          weatherCode: rain > 0 ? 61 : 0, // 有降水标记为小雨代码
          weatherDescription: _descFromWindRain(wd, ws, rain),
          precipitationProbability: rain > 0 ? 80 : 0,
          locationName: city,
        );
      }
    } catch (e) {
      debugPrint('Weather fetch error: $e');
    }
    return null;
  }

  /// 风力等级转m/s
  static double _windLevelToSpeed(String level) {
    final match = RegExp(r'(\d+)').firstMatch(level);
    if (match == null) return 0;
    final lv = int.parse(match.group(1)!);
    // 风力等级→m/s 对照表
    const speeds = <double>[0, 0.9, 2.5, 4.4, 6.7, 9.4, 12.3, 15.5, 19.0, 22.6, 26.5, 30.6, 34.8];
    return lv < speeds.length ? speeds[lv] : speeds.last;
  }

  /// 风向文字转角度
  static double _windDirToDegrees(String dir) {
    if (dir.contains('北') && dir.contains('东')) return 45;
    if (dir.contains('东') && dir.contains('南')) return 135;
    if (dir.contains('南') && dir.contains('西')) return 225;
    if (dir.contains('西') && dir.contains('北')) return 315;
    if (dir.contains('北')) return 0;
    if (dir.contains('东')) return 90;
    if (dir.contains('南')) return 180;
    if (dir.contains('西')) return 270;
    return 0;
  }

  /// 根据风向风速和降水生成天气描述
  static String _descFromWindRain(String wd, String ws, double rain) {
    if (rain > 0) return '有雨';
    if (ws.contains('无') || ws == '0级' || ws == '1级') return '晴';
    return '$wd$ws';
  }
}