import 'dart:convert';
import 'dart:io';

void main() async {
  print('=== 中国天气网 d1 sk_2d API 验证 ===\n');

  final cities = {
    '101010100': '北京',
    '101200101': '武汉',
    '101280101': '广州',
    '101280601': '深圳',
    '101210101': '杭州',
    '101020100': '上海',
    '101270101': '成都',
    '101190101': '南京',
  };

  int pass = 0;
  int fail = 0;

  for (final entry in cities.entries) {
    final code = entry.key;
    final name = entry.value;
    final url = 'http://d1.weather.com.cn/sk_2d/$code.html';

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('Referer', 'http://www.weather.com.cn/');
      final response = await request.close().timeout(const Duration(seconds: 8));
      final body = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode != 200) {
        print('[FAIL] $name ($code): HTTP ${response.statusCode}');
        fail++;
        continue;
      }

      // 解析 var dataSK={...} 格式
      String jsonStr = body;
      if (jsonStr.startsWith('var dataSK=')) {
        jsonStr = jsonStr.substring('var dataSK='.length);
      }
      jsonStr = jsonStr.trim();
      if (jsonStr.endsWith(';')) jsonStr = jsonStr.substring(0, jsonStr.length - 1);

      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final temp = json['temp'];
      final cityname = json['cityname'];
      final weather = json['weather'];
      final wd = json['WD'];
      final ws = json['WS'];
      final sd = json['SD'];

      print('[PASS] $name ($code): $cityname ${temp}°C $weather $wd $ws 湿度:$sd');
      pass++;
    } catch (e) {
      print('[FAIL] $name ($code): $e');
      fail++;
    }
  }

  print('\n=== 结果: $pass 通过, $fail 失败 ===');
  exit(fail > 0 ? 1 : 0);
}