import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huhuashizhe/services/weather_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WeatherService - 城市代码查找', () {
    late WeatherService service;

    setUp(() {
      service = WeatherService();
    });

    test('北京海淀区 -> 区级代码', () async {
      final code = await service.findCityCode('北京市', '海淀区');
      expect(code, '101010200');
      debugPrint('[PASS] 北京海淀区 -> $code');
    });

    test('武汉 -> 市级代码', () async {
      final code = await service.findCityCode('武汉市', null);
      expect(code, '101200101');
      debugPrint('[PASS] 武汉 -> $code');
    });

    test('上海浦东 -> 市级代码', () async {
      final code = await service.findCityCode('上海市', '浦东新区');
      expect(code, isNotNull);
      debugPrint('[PASS] 上海浦东 -> $code');
    });

    test('不存在的城市 -> null', () async {
      final code = await service.findCityCode('不存在的城市', null);
      expect(code, isNull);
      debugPrint('[PASS] 不存在城市 -> null');
    });

    test('广州 -> 市级代码', () async {
      final code = await service.findCityCode('广州市', null);
      expect(code, '101280101');
      debugPrint('[PASS] 广州 -> $code');
    });

    test('深圳 -> 市级代码', () async {
      final code = await service.findCityCode('深圳市', null);
      expect(code, '101280601');
      debugPrint('[PASS] 深圳 -> $code');
    });
  });
}