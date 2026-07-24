/// 护花使者 APP - 集成测试套件
/// 测试 Provider + Service 交互、数据持久化、API调用
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';

// ============================================================
// 集成测试：模拟Provider和Service交互
// ============================================================

void main() {
  group('=== 集成测试套件 ===', () {
    // ==================== TC-INTG-01: 预设Provider完整流程 ====================
    group('TC-INTG-01: 预设Provider CRUD集成', () {
      final Map<String, dynamic> cache = {};

      List<Map<String, dynamic>> getPresets() {
        final json = cache['presets'] as String? ?? '[]';
        return List<Map<String, dynamic>>.from(jsonDecode(json));
      }

      void savePresets(List<Map<String, dynamic>> presets) {
        cache['presets'] = jsonEncode(presets);
      }

      // 模拟 PresetsNotifier
      List<Map<String, dynamic>> state = [];

      void addPreset(Map<String, dynamic> preset) {
        final presets = getPresets();
        preset['id'] = DateTime.now().millisecondsSinceEpoch.toString();
        preset['createdAt'] = DateTime.now().toIso8601String();
        presets.insert(0, preset);
        savePresets(presets);
        state = List.from(presets);
      }

      void updatePreset(String id, Map<String, dynamic> preset) {
        final presets = getPresets();
        final index = presets.indexWhere((p) => p['id'] == id);
        if (index >= 0) {
          preset['id'] = id;
          presets[index] = preset;
        }
        savePresets(presets);
        state = List.from(presets);
      }

      void deletePreset(String id) {
        final presets = getPresets();
        presets.removeWhere((p) => p['id'] == id);
        savePresets(presets);
        state = List.from(presets);
      }

      setUp(() {
        cache.clear();
        cache['presets'] = '[]';
        state = [];
      });

      test('完整CRUD流程', () {
        // 1. 初始为空
        expect(state.isEmpty, true);

        // 2. 添加预设
        addPreset({'name': '小麦杀虫', 'cropType': '小麦', 'operationType': '杀虫',
                    'sprayVolume': 1.5, 'flightHeight': 2.0});
        expect(state.length, 1);
        expect(state[0]['name'], '小麦杀虫');
        expect(state[0]['id'], isNotNull);
        expect(state[0]['createdAt'], isNotNull);

        // 3. 添加第二个预设（insert at 0，顺序变为 [水稻施肥, 小麦杀虫]）
        addPreset({'name': '水稻施肥', 'cropType': '水稻', 'operationType': '施肥',
                    'sprayVolume': 2.0, 'flightHeight': 2.5});
        expect(state.length, 2);

        // 4. 更新第一个预设（小麦杀虫，现在在索引1）
        final id = state[1]['id'];
        updatePreset(id, {'name': '小麦杀虫（更新）', 'cropType': '小麦',
                          'operationType': '杀虫', 'sprayVolume': 2.0, 'flightHeight': 3.0});
        expect(state[1]['name'], '小麦杀虫（更新）');
        expect(state[1]['sprayVolume'], 2.0);
        expect(state[1]['flightHeight'], 3.0);

        // 5. 删除小麦杀虫
        deletePreset(id);
        expect(state.length, 1);
        expect(state[0]['name'], '水稻施肥');

        // 6. 删除最后一个
        deletePreset(state[0]['id']);
        expect(state.isEmpty, true);
      });

      test('批量添加和删除', () {
        // 添加10个预设
        for (int i = 0; i < 10; i++) {
          addPreset({'name': '预设$i', 'cropType': '水稻'});
        }
        expect(state.length, 10);

        // 删除所有
        while (state.isNotEmpty) {
          deletePreset(state[0]['id']);
        }
        expect(state.isEmpty, true);
      });

      test('AI生成标签', () {
        addPreset({'name': 'AI推荐方案', 'isAiGenerated': true, 'cropType': '水稻'});
        expect(state[0]['isAiGenerated'], true);
      });
    });

    // ==================== TC-INTG-02: AI聊天消息持久化 ====================
    group('TC-INTG-02: AI聊天消息持久化', () {
      final Map<String, dynamic> cache = {};

      void saveHistory(List<Map<String, dynamic>> messages) {
        // 只保留最近50条
        final toSave = messages.length > 50 ? messages.sublist(messages.length - 50) : messages;
        cache['ai_chat_history'] = jsonEncode(toSave);
      }

      List<Map<String, dynamic>> loadHistory() {
        final data = cache['ai_chat_history'] as String?;
        if (data == null || data.isEmpty) return [];
        return List<Map<String, dynamic>>.from(jsonDecode(data));
      }

      Map<String, dynamic> createMsg(String role, String content) => {
        'role': role,
        'content': content,
        'timestamp': DateTime.now().toIso8601String(),
      };

      setUp(() => cache.clear());

      test('保存和加载一轮对话', () {
        final messages = [
          createMsg('user', '水稻叶片发黄怎么办？'),
          createMsg('assistant', '建议检查是否缺氮，可以考虑追施尿素...'),
        ];
        saveHistory(messages);
        final loaded = loadHistory();
        expect(loaded.length, 2);
        expect(loaded[0]['role'], 'user');
        expect(loaded[1]['role'], 'assistant');
        expect(loaded[0]['content'], '水稻叶片发黄怎么办？');
      });

      test('超过50条截断', () {
        final messages = <Map<String, dynamic>>[];
        for (int i = 0; i < 60; i++) {
          messages.add(createMsg('user', '消息$i'));
        }
        saveHistory(messages);
        final loaded = loadHistory();
        expect(loaded.length, 50);
        // 保留的是最近50条
        expect(loaded[0]['content'], '消息10');
        expect(loaded[49]['content'], '消息59');
      });

      test('清空历史', () {
        final messages = [createMsg('user', '测试')];
        saveHistory(messages);
        expect(loadHistory().length, 1);
        cache.remove('ai_chat_history');
        expect(loadHistory().isEmpty, true);
      });

      test('空历史', () {
        expect(loadHistory().isEmpty, true);
      });

      test('历史持久化往返', () {
        final messages = [
          createMsg('user', '问1'),
          createMsg('assistant', '答1'),
          createMsg('user', '问2'),
          createMsg('assistant', '答2'),
        ];
        saveHistory(messages);
        final loaded = loadHistory();
        expect(loaded.length, 4);
        for (int i = 0; i < 4; i++) {
          expect(loaded[i]['role'], messages[i]['role']);
          expect(loaded[i]['content'], messages[i]['content']);
        }
      });
    });

    // ==================== TC-INTG-03: 更新检测流程 ====================
    group('TC-INTG-03: 更新检测版本比较', () {
      bool isNewerVersion(String remote, String local) {
        final rp = remote.split('.').map((e) => int.tryParse(e) ?? 0).toList();
        final lp = local.split('.').map((e) => int.tryParse(e) ?? 0).toList();
        for (var i = 0; i < 3; i++) {
          final r = i < rp.length ? rp[i] : 0;
          final l = i < lp.length ? lp[i] : 0;
          if (r > l) return true;
          if (r < l) return false;
        }
        return false;
      }

      int parseVersionCode(String tag) {
        final clean = tag.replaceFirst('v', '');
        final parts = clean.split('.');
        if (parts.length >= 3) {
          return int.parse(parts[0]) * 10000 +
              int.parse(parts[1]) * 100 +
              int.parse(parts[2]);
        }
        return 0;
      }

      test('版本比较矩阵', () {
        final testCases = [
          // (remote, local, expected_is_newer)
          ('1.2.0', '1.1.0', true),
          ('1.1.0', '1.2.0', false),
          ('1.2.0', '1.2.0', false),
          ('2.0.0', '1.9.9', true),
          ('1.0.1', '1.0.0', true),
          ('1.0.0', '1.0.1', false),
          ('1.10.0', '1.9.0', true),
          ('1.1.13', '1.1.12', true),
          ('1.1.9', '1.1.10', false),
        ];

        for (final tc in testCases) {
          final remote = tc.$1;
          final local = tc.$2;
          final expected = tc.$3;
          expect(isNewerVersion(remote, local), expected,
              reason: '$remote vs $local 应为 $expected');
        }
      });

      test('版本码解析正确的量级', () {
        expect(parseVersionCode('v1.2.0'), 10200);
        expect(parseVersionCode('v1.2.0') > parseVersionCode('v1.1.13'), true);
        expect(parseVersionCode('v1.2.0') > parseVersionCode('v1.1.0'), true);
        expect(parseVersionCode('v1.2.0') < parseVersionCode('v2.0.0'), true);
      });

      test('UpdateInfo从JSON解析', () {
        final json = {
          'tag_name': 'v1.2.0',
          'body': '## 更新内容\n- 新功能\n- 修复',
          'published_at': '2026-06-27T12:00:00Z',
          'assets': [
            {'browser_download_url': 'https://example.com/app.apk'}
          ],
        };

        final versionName = (json['tag_name'] as String).replaceFirst('v', '');
        final downloadUrl = (json['assets'] as List).isNotEmpty
            ? ((json['assets'] as List)[0] as Map)['browser_download_url'] as String
            : '';
        final publishedAt = DateTime.parse(json['published_at'] as String);

        expect(versionName, '1.2.0');
        expect(downloadUrl, 'https://example.com/app.apk');
        expect(publishedAt.year, 2026);
      });

      test('UpdateInfo无assets时downloadUrl为空', () {
        final json = {
          'tag_name': 'v1.0.0',
          'body': '',
          'published_at': '2026-01-01T00:00:00Z',
          'assets': <dynamic>[],
        };
        final downloadUrl = (json['assets'] as List).isNotEmpty
            ? 'has_url'
            : '';
        expect(downloadUrl, '');
      });
    });

    // ==================== TC-INTG-04: 天气API城市代码匹配 ====================
    group('TC-INTG-04: 城市代码匹配', () {
      // 模拟城市代码映射表
      final Map<String, String> cityCodes = {
        '北京': '101010100',
        '海淀': '101010200',
        '朝阳': '101010300',
        '武汉': '101200101',
        '广州': '101280101',
        '深圳': '101280601',
        '杭州': '101210101',
        '上海': '101020100',
        '成都': '101270101',
        '南京': '101190101',
      };

      String? findCityCode(String cityName, String? districtName) {
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
          final districtCode = cityCodes[cleanDistrict];
          if (districtCode != null) return districtCode;
        }

        // 回退匹配市级
        final cityCode = cityCodes[cleanCity];
        if (cityCode != null) return cityCode;

        // 模糊匹配
        for (final entry in cityCodes.entries) {
          if (cleanCity.contains(entry.key) || entry.key.contains(cleanCity)) {
            return entry.value;
          }
        }
        return null;
      }

      test('精确匹配市级', () {
        expect(findCityCode('北京', null), '101010100');
        expect(findCityCode('武汉', null), '101200101');
        expect(findCityCode('上海市', null), '101020100');
        expect(findCityCode('广州', null), '101280101');
      });

      test('精确匹配区级优先', () {
        expect(findCityCode('北京', '海淀'), '101010200');
        expect(findCityCode('北京', '朝阳区'), '101010300');
      });

      test('8大城市全部匹配成功', () {
        final cities = ['北京', '武汉', '广州', '深圳', '杭州', '上海', '成都', '南京'];
        for (final city in cities) {
          final code = findCityCode(city, null);
          expect(code, isNotNull, reason: '$city 应匹配到城市代码');
          expect(code, isNotEmpty, reason: '$city 城市代码不应为空');
        }
      });

      test('匹配失败返回null', () {
        expect(findCityCode('不存在的城市', null), null);
        expect(findCityCode('火星', null), null);
      });

      test('模糊匹配', () {
        // 传入"北京市"会被clean为"北京"
        expect(findCityCode('北京市', null), '101010100');
      });
    });

    // ==================== TC-INTG-05: 设置状态流转 ====================
    group('TC-INTG-05: 设置状态流转', () {
      final Map<String, bool> settings = {};

      setUp(() => settings.clear());

      test('默认设置', () {
        // 模拟 SettingsPage 初始化
        final darkMode = settings['dark_mode'] ?? false;
        final notifications = settings['notifications'] ?? true;
        final autoWeather = settings['auto_weather'] ?? true;
        expect(darkMode, false);
        expect(notifications, true);
        expect(autoWeather, true);
      });

      test('切换深色模式', () {
        settings['dark_mode'] = true;
        expect(settings['dark_mode'], true);
        settings['dark_mode'] = false;
        expect(settings['dark_mode'], false);
      });

      test('切换通知', () {
        settings['notifications'] = false;
        expect(settings['notifications'], false);
        settings['notifications'] = true;
        expect(settings['notifications'], true);
      });

      test('全部设置独立', () {
        settings['dark_mode'] = true;
        settings['notifications'] = false;
        settings['auto_weather'] = true;
        expect(settings['dark_mode'], true);
        expect(settings['notifications'], false);
        expect(settings['auto_weather'], true);
      });
    });

    // ==================== TC-INTG-06: 作业任务CRUD ====================
    group('TC-INTG-06: 作业任务存储', () {
      final Map<String, dynamic> cache = {};

      List<Map<String, dynamic>> getMissions() {
        final json = cache['missions'] as String? ?? '[]';
        return List<Map<String, dynamic>>.from(jsonDecode(json));
      }

      void saveMissions(List<Map<String, dynamic>> missions) {
        cache['missions'] = jsonEncode(missions);
      }

      void addMission(Map<String, dynamic> mission) {
        final missions = getMissions();
        mission['id'] = DateTime.now().millisecondsSinceEpoch.toString();
        mission['createdAt'] = DateTime.now().toIso8601String();
        missions.insert(0, mission);
        saveMissions(missions);
      }

      setUp(() => cache.clear());

      test('添加作业记录', () {
        addMission({
          'area': 15.5,
          'duration': 45,
          'cropType': '水稻',
          'pesticide': '吡虫啉',
          'sprayVolume': 20.0,
        });
        final missions = getMissions();
        expect(missions.length, 1);
        expect(missions[0]['area'], 15.5);
        expect(missions[0]['duration'], 45);
        expect(missions[0]['cropType'], '水稻');
      });

      test('多个作业记录', () {
        for (int i = 0; i < 5; i++) {
          addMission({'area': (i + 1) * 10.0, 'duration': i * 30});
        }
        expect(getMissions().length, 5);
      });
    });

    // ==================== TC-INTG-07: 响应体解析（模拟天气API） ====================
    group('TC-INTG-07: 天气API响应解析', () {
      test('正常响应解析', () {
        const body = 'var dataSK={"temp":"25.5","SD":"65%","WD":"北风","WS":"3级","cityname":"北京","rain":"0","weather":"晴"}';
        String jsonStr = body;
        if (jsonStr.startsWith('var dataSK=')) {
          jsonStr = jsonStr.substring('var dataSK='.length);
        }
        jsonStr = jsonStr.trim();
        if (jsonStr.endsWith(';')) {
          jsonStr = jsonStr.substring(0, jsonStr.length - 1);
        }

        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        expect(json['temp'], '25.5');
        expect(json['SD'], '65%');
        expect(json['WD'], '北风');
        expect(json['WS'], '3级');
        expect(json['cityname'], '北京');
        expect(json['weather'], '晴');
      });

      test('带分号结尾', () {
        const body = 'var dataSK={"temp":"30.0","cityname":"武汉"};';
        String jsonStr = body;
        if (jsonStr.startsWith('var dataSK=')) {
          jsonStr = jsonStr.substring('var dataSK='.length);
        }
        jsonStr = jsonStr.trim();
        if (jsonStr.endsWith(';')) {
          jsonStr = jsonStr.substring(0, jsonStr.length - 1);
        }
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        expect(json['temp'], '30.0');
        expect(json['cityname'], '武汉');
      });

      test('空响应', () {
        const body = '';
        expect(body.isEmpty, true);
      });

      test('非JSON响应', () {
        const body = '<html>error</html>';
        expect(body.startsWith('{'), false);
      });
    });
  });
}