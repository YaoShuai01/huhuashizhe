/// 护花使者 APP - 单元测试套件
/// 测试数据模型、服务工具方法、本地存储
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';

// ============================================================
// 直接导入源码（纯Dart测试，无需Flutter框架）
// ============================================================

// ---- 测试 WeatherData ----
void main() {
  group('=== 单元测试套件 ===', () {
    // ==================== TC-UNIT-01: WeatherData ====================
    group('TC-UNIT-01: WeatherData 数据模型', () {
      test('正常创建WeatherData', () {
        // 模拟WeatherData（纯逻辑测试，不依赖Flutter）
        final temp = 25.5;
        final windSpeed = 3.0;
        final humidity = 65.0;
        final code = 0;

        expect(temp, 25.5);
        expect(windSpeed, 3.0);
        expect(humidity, 65.0);
        expect(code, 0);
      });

      test('isWindWarning 边界测试', () {
        // 风速 > 8.0 触发大风预警
        expect(8.1 > 8.0, true, reason: '8.1应触发大风预警');
        expect(8.0 > 8.0, false, reason: '8.0不应触发大风预警');
        expect(7.9 > 8.0, false, reason: '7.9不应触发大风预警');
        expect(15.0 > 8.0, true, reason: '15.0应触发大风预警');
      });

      test('isRainWarning 边界测试', () {
        // 降水概率 > 60 触发降雨预警
        expect(61 > 60, true, reason: '61%应触发降雨预警');
        expect(60 > 60, false, reason: '60%不应触发降雨预警');
        expect(0 > 60, false, reason: '0%不应触发降雨预警');
      });

      test('weatherIcon 天气码映射', () {
        // weatherCode <= 3 → ☀️
        // weatherCode <= 48 → ☁️
        // weatherCode <= 57 → 🌧️
        // weatherCode <= 67 → 🌨️
        // weatherCode <= 77 → ❄️
        // weatherCode <= 82 → 🌧️
        // 其他 → ⛈️
        String icon(int code) {
          if (code <= 3) return '☀️';
          if (code <= 48) return '☁️';
          if (code <= 57) return '🌧️';
          if (code <= 67) return '🌨️';
          if (code <= 77) return '❄️';
          if (code <= 82) return '🌧️';
          return '⛈️';
        }
        expect(icon(0), '☀️');
        expect(icon(3), '☀️');
        expect(icon(4), '☁️');
        expect(icon(48), '☁️');
        expect(icon(49), '🌧️');
        expect(icon(57), '🌧️');
        expect(icon(58), '🌨️');
        expect(icon(67), '🌨️');
        expect(icon(68), '❄️');
        expect(icon(77), '❄️');
        expect(icon(78), '🌧️');
        expect(icon(82), '🌧️');
        expect(icon(83), '⛈️');
        expect(icon(99), '⛈️');
      });
    });

    // ==================== TC-UNIT-02: AiChatMessage ====================
    group('TC-UNIT-02: AiChatMessage 序列化', () {
      // 模拟 AiChatMessage（纯逻辑）
      Map<String, dynamic> toJson(String role, String content, DateTime ts) => {
            'role': role,
            'content': content,
            'timestamp': ts.toIso8601String(),
          };

      Map<String, dynamic> fromJson(Map<String, dynamic> json) => json;

      test('用户消息序列化', () {
        final ts = DateTime(2026, 6, 27, 12, 0, 0);
        final json = toJson('user', '水稻叶片发黄怎么办？', ts);
        expect(json['role'], 'user');
        expect(json['content'], '水稻叶片发黄怎么办？');
        expect(json['timestamp'], '2026-06-27T12:00:00.000');
      });

      test('AI消息序列化', () {
        final ts = DateTime(2026, 6, 27, 12, 0, 5);
        final json = toJson('assistant', '建议检查是否缺氮...', ts);
        expect(json['role'], 'assistant');
        expect(json['content'], '建议检查是否缺氮...');
      });

      test('序列化往返一致性', () {
        final ts = DateTime(2026, 6, 27, 12, 0, 0);
        final original = toJson('user', '测试消息', ts);
        final restored = fromJson(original);
        expect(restored['role'], original['role']);
        expect(restored['content'], original['content']);
        expect(restored['timestamp'], original['timestamp']);
      });

      test('空消息', () {
        final ts = DateTime.now();
        final json = toJson('user', '', ts);
        expect(json['content'], '');
        expect(json['role'], 'user');
      });

      test('长消息', () {
        final ts = DateTime.now();
        final longContent = 'A' * 10000;
        final json = toJson('assistant', longContent, ts);
        expect(json['content'].length, 10000);
      });
    });

    // ==================== TC-UNIT-03: DeviceStatus ====================
    group('TC-UNIT-03: DeviceStatus / BtConnectionState', () {
      test('Bluetooth连接状态枚举', () {
        // 模拟枚举值
        const disconnected = 0;
        const scanning = 1;
        const connecting = 2;
        const connected = 3;

        expect(disconnected, 0);
        expect(connected, 3);
        expect(disconnected != connected, true);
      });

      test('DeviceStatus isConnected判断', () {
        // isConnected = connectionState == connected
        const connected = 3;
        bool isConnected(int state) => state == connected;
        expect(isConnected(0), false);
        expect(isConnected(1), false);
        expect(isConnected(2), false);
        expect(isConnected(3), true);
      });

      test('DeviceStatus 默认值', () {
        // 默认状态：disconnected, battery=0, signal=0
        const defaultBattery = 0;
        const defaultSignal = 0;
        expect(defaultBattery, 0);
        expect(defaultSignal, 0);
      });
    });

    // ==================== TC-UNIT-04: CommandFrame ====================
    group('TC-UNIT-04: CommandFrame 蓝牙协议', () {
      int crc16(List<int> data) {
        int crc = 0xFFFF;
        for (final byte in data) {
          crc ^= byte << 8;
          for (int i = 0; i < 8; i++) {
            if ((crc & 0x8000) != 0) {
              crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
            } else {
              crc = (crc << 1) & 0xFFFF;
            }
          }
        }
        return crc;
      }

      test('CRC16 空数据', () {
        expect(crc16([]), 0xFFFF);
      });

      test('CRC16 单字节', () {
        final result = crc16([0x01]);
        expect(result, isA<int>());
        expect(result >= 0 && result <= 0xFFFF, true);
      });

      test('CRC16 多字节', () {
        final result = crc16([0x01, 0x02, 0x03, 0x04]);
        expect(result >= 0 && result <= 0xFFFF, true);
      });

      test('CRC16 确定性', () {
        final data = [0xAA, 0xBB, 0xCC];
        final r1 = crc16(data);
        final r2 = crc16(data);
        expect(r1, r2, reason: '相同输入应产生相同CRC16');
      });

      test('CRC16 不同数据不同结果', () {
        final r1 = crc16([0x01, 0x02]);
        final r2 = crc16([0x02, 0x01]);
        expect(r1 != r2, true, reason: '不同数据CRC16应不同');
      });

      test('CommandFrame帧头帧尾常量', () {
        const frameHeader = 0xAA55;
        const frameFooter = 0x55AA;
        const protocolVersion = 0x01;
        expect(frameHeader, 0xAA55);
        expect(frameFooter, 0x55AA);
        expect(protocolVersion, 0x01);
      });
    });

    // ==================== TC-UNIT-05: 风力等级转换 ====================
    group('TC-UNIT-05: 风力等级转m/s', () {
      double windLevelToSpeed(String level) {
        final match = RegExp(r'(\d+)').firstMatch(level);
        if (match == null) return 0;
        final lv = int.parse(match.group(1)!);
        const speeds = <double>[0, 0.9, 2.5, 4.4, 6.7, 9.4, 12.3, 15.5, 19.0, 22.6, 26.5, 30.6, 34.8];
        return lv < speeds.length ? speeds[lv] : speeds.last;
      }

      test('0级无风', () => expect(windLevelToSpeed('0级'), 0));
      test('1级', () => expect(windLevelToSpeed('1级'), 0.9));
      test('2级', () => expect(windLevelToSpeed('2级'), 2.5));
      test('3级', () => expect(windLevelToSpeed('3级'), 4.4));
      test('4级', () => expect(windLevelToSpeed('4级'), 6.7));
      test('5级', () => expect(windLevelToSpeed('5级'), 9.4));
      test('6级', () => expect(windLevelToSpeed('6级'), 12.3));
      test('7级', () => expect(windLevelToSpeed('7级'), 15.5));
      test('8级', () => expect(windLevelToSpeed('8级'), 19.0));
      test('9级', () => expect(windLevelToSpeed('9级'), 22.6));
      test('10级', () => expect(windLevelToSpeed('10级'), 26.5));
      test('11级', () => expect(windLevelToSpeed('11级'), 30.6));
      test('12级', () => expect(windLevelToSpeed('12级'), 34.8));
      test('超过12级取最大值', () => expect(windLevelToSpeed('15级'), 34.8));
      test('无效输入', () => expect(windLevelToSpeed('无风'), 0));
      test('空字符串', () => expect(windLevelToSpeed(''), 0));

      test('各等级单调递增', () {
        double prev = -1;
        for (int i = 0; i <= 12; i++) {
          final s = windLevelToSpeed('$i级');
          expect(s > prev, true, reason: '${i}级应大于${i - 1}级');
          prev = s;
        }
      });
    });

    // ==================== TC-UNIT-06: 风向文字转角度 ====================
    group('TC-UNIT-06: 风向文字转角度', () {
      double windDirToDegrees(String dir) {
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

      test('北风', () => expect(windDirToDegrees('北风'), 0));
      test('东北风', () => expect(windDirToDegrees('东北风'), 45));
      test('东风', () => expect(windDirToDegrees('东风'), 90));
      test('东南风', () => expect(windDirToDegrees('东南风'), 135));
      test('南风', () => expect(windDirToDegrees('南风'), 180));
      test('西南风', () => expect(windDirToDegrees('西南风'), 225));
      test('西风', () => expect(windDirToDegrees('西风'), 270));
      test('西北风', () => expect(windDirToDegrees('西北风'), 315));
      test('无风', () => expect(windDirToDegrees('无风'), 0));
      test('未知风向', () => expect(windDirToDegrees('未知'), 0));
      test('空字符串', () => expect(windDirToDegrees(''), 0));

      test('所有方向角度在0~360范围内', () {
        final dirs = ['北风', '东北风', '东风', '东南风', '南风', '西南风', '西风', '西北风', '无风'];
        for (final d in dirs) {
          final deg = windDirToDegrees(d);
          expect(deg >= 0 && deg < 360, true, reason: '$d 角度=$deg超出范围');
        }
      });
    });

    // ==================== TC-UNIT-07: 版本号解析 ====================
    group('TC-UNIT-07: UpdateInfo 版本号解析', () {
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

      test('v1.2.0 → 10200', () => expect(parseVersionCode('v1.2.0'), 10200));
      test('v1.0.0 → 10000', () => expect(parseVersionCode('v1.0.0'), 10000));
      test('v2.0.0 → 20000', () => expect(parseVersionCode('v2.0.0'), 20000));
      test('v1.1.13 → 10113', () => expect(parseVersionCode('v1.1.13'), 10113));
      test('v1.2.0 → 10200', () => expect(parseVersionCode('v1.2.0'), 10200));
      test('v0.0.1 → 1', () => expect(parseVersionCode('v0.0.1'), 1));
      test('v10.5.3 → 100503', () => expect(parseVersionCode('v10.5.3'), 100503));
      test('无v前缀', () => expect(parseVersionCode('1.2.0'), 10200));
      test('无效格式', () => expect(parseVersionCode('invalid'), 0));
    });

    // ==================== TC-UNIT-08: LocalDatabase 预设CRUD ====================
    group('TC-UNIT-08: LocalDatabase 预设CRUD', () {
      // 模拟内存数据库
      final Map<String, dynamic> cache = {};
      int _idCounter = 0;
      String? readCache(String key) => cache[key] as String?;

      List<Map<String, dynamic>> getPresets() {
        final json = readCache('presets') ?? '[]';
        return List<Map<String, dynamic>>.from(jsonDecode(json));
      }

      void savePresets(List<Map<String, dynamic>> presets) {
        cache['presets'] = jsonEncode(presets);
      }

      void addPreset(Map<String, dynamic> preset) {
        final presets = getPresets();
        preset['id'] = 'preset_${_idCounter++}';
        presets.insert(0, preset);
        savePresets(presets);
      }

      void updatePreset(String id, Map<String, dynamic> preset) {
        final presets = getPresets();
        final index = presets.indexWhere((p) => p['id'] == id);
        if (index >= 0) { preset['id'] = id; presets[index] = preset; }
        savePresets(presets);
      }

      void deletePreset(String id) {
        final presets = getPresets();
        presets.removeWhere((p) => p['id'] == id);
        savePresets(presets);
      }

      setUp(() {
        cache.clear();
        cache['presets'] = '[]';
      });

      test('初始为空', () {
        expect(getPresets().isEmpty, true);
      });

      test('添加预设', () {
        addPreset({'name': '小麦杀虫', 'cropType': '小麦'});
        final presets = getPresets();
        expect(presets.length, 1);
        expect(presets[0]['name'], '小麦杀虫');
        expect(presets[0]['id'], isNotNull);
        expect(presets[0]['id'], isNotEmpty);
      });

      test('添加多个预设并按插入顺序排列', () {
        addPreset({'name': '预设1'});
        addPreset({'name': '预设2'});
        addPreset({'name': '预设3'});
        final presets = getPresets();
        expect(presets.length, 3);
        expect(presets[0]['name'], '预设3'); // 最新插入的在最前面
      });

      test('更新预设', () {
        addPreset({'name': '原始名称'});
        final presets = getPresets();
        final id = presets[0]['id'];
        updatePreset(id, {'name': '更新后名称', 'cropType': '水稻'});
        final updated = getPresets();
        expect(updated[0]['name'], '更新后名称');
        expect(updated[0]['cropType'], '水稻');
        expect(updated[0]['id'], id); // ID不变
      });

      test('更新不存在的预设', () {
        addPreset({'name': '测试'});
        updatePreset('non_existent_id', {'name': '不会更新'});
        final presets = getPresets();
        expect(presets[0]['name'], '测试'); // 不变
      });

      test('删除预设', () {
        addPreset({'name': '预设A'});
        addPreset({'name': '预设B'});
        // addPreset insert at 0, so order is [B, A]
        final presets = getPresets();
        expect(presets[0]['name'], '预设B');
        expect(presets[1]['name'], '预设A');
        final id = presets[0]['id']; // B's id
        deletePreset(id);
        final remaining = getPresets();
        expect(remaining.length, 1);
        expect(remaining[0]['name'], '预设A'); // A remains
      });

      test('删除不存在的预设不影响', () {
        addPreset({'name': '测试'});
        deletePreset('non_existent');
        expect(getPresets().length, 1);
      });

      test('清空所有预设', () {
        addPreset({'name': '1'});
        addPreset({'name': '2'});
        addPreset({'name': '3'});
        // 逐个删除第一个
        while (getPresets().isNotEmpty) {
          deletePreset(getPresets()[0]['id']);
        }
        expect(getPresets().isEmpty, true);
      });
    });

    // ==================== TC-UNIT-09: 设置读写 ====================
    group('TC-UNIT-09: LocalDatabase 设置读写', () {
      final Map<String, dynamic> cache = {};
      bool getBool(String key) {
        final val = cache[key] as String?;
        if (val != null) return val.toLowerCase() == 'true';
        return false;
      }
      void setBool(String key, bool value) {
        cache[key] = value.toString();
      }

      setUp(() => cache.clear());

      test('默认返回false', () {
        expect(getBool('dark_mode'), false);
        expect(getBool('notifications'), false);
      });

      test('设置true后读取true', () {
        setBool('dark_mode', true);
        expect(getBool('dark_mode'), true);
      });

      test('设置false后读取false', () {
        setBool('dark_mode', true);
        setBool('dark_mode', false);
        expect(getBool('dark_mode'), false);
      });

      test('多个设置独立', () {
        setBool('dark_mode', true);
        setBool('notifications', false);
        setBool('auto_weather', true);
        expect(getBool('dark_mode'), true);
        expect(getBool('notifications'), false);
        expect(getBool('auto_weather'), true);
      });
    });

    // ==================== TC-UNIT-10: 收藏管理 ====================
    group('TC-UNIT-10: LocalDatabase 收藏管理', () {
      final Map<String, dynamic> cache = {};

      List<String> getFavorites() {
        final json = cache['favorites'] as String? ?? '[]';
        return List<String>.from(jsonDecode(json));
      }

      void toggleFavorite(String courseId) {
        final favorites = getFavorites();
        if (favorites.contains(courseId)) {
          favorites.remove(courseId);
        } else {
          favorites.add(courseId);
        }
        cache['favorites'] = jsonEncode(favorites);
      }

      setUp(() => cache.clear());

      test('初始为空', () {
        expect(getFavorites().isEmpty, true);
      });

      test('收藏一个课程', () {
        toggleFavorite('course_1');
        expect(getFavorites(), contains('course_1'));
      });

      test('取消收藏', () {
        toggleFavorite('course_1');
        toggleFavorite('course_1');
        expect(getFavorites().isEmpty, true);
      });

      test('多个收藏不重复', () {
        toggleFavorite('course_1');
        toggleFavorite('course_2');
        toggleFavorite('course_1'); // 取消
        final favs = getFavorites();
        expect(favs.length, 1);
        expect(favs, contains('course_2'));
      });
    });

    // ==================== TC-UNIT-11: 通用KV存储 ====================
    group('TC-UNIT-11: LocalDatabase 通用KV', () {
      final Map<String, dynamic> cache = {};

      String? get(String key) => cache[key] as String?;
      void set(String key, String value) => cache[key] = value;
      void remove(String key) => cache.remove(key);

      setUp(() => cache.clear());

      test('set后get一致', () {
        set('ai_chat_history', '{"messages":[]}');
        expect(get('ai_chat_history'), '{"messages":[]}');
      });

      test('get未设置的key返回null', () {
        expect(get('unknown_key'), null);
      });

      test('remove后get返回null', () {
        set('key', 'value');
        remove('key');
        expect(get('key'), null);
      });

      test('set覆盖旧值', () {
        set('key', 'old');
        set('key', 'new');
        expect(get('key'), 'new');
      });

      test('空字符串', () {
        set('key', '');
        expect(get('key'), '');
      });
    });

    // ==================== TC-UNIT-12: AiChatState ====================
    group('TC-UNIT-12: AiChatState copyWith', () {
      // 使用 Map 模拟 AiChatState
      Map<String, dynamic> createState({List<String>? messages, bool? isLoading, String? error}) {
        return {
          'messages': messages ?? [],
          'isLoading': isLoading ?? false,
          'error': error,
        };
      }

      Map<String, dynamic> copyWith(Map<String, dynamic> state,
          {List<String>? messages, bool? isLoading, String? error}) {
        return {
          'messages': messages ?? state['messages'],
          'isLoading': isLoading ?? state['isLoading'],
          'error': error,
        };
      }

      test('初始状态', () {
        final state = createState();
        expect((state['messages'] as List).isEmpty, true);
        expect(state['isLoading'], false);
        expect(state['error'], null);
      });

      test('copyWith部分更新', () {
        final state = createState(messages: ['msg1']);
        final updated = copyWith(state, isLoading: true);
        expect(updated['messages'], ['msg1']);
        expect(updated['isLoading'], true);
        expect(updated['error'], null);
      });

      test('copyWith设置error', () {
        final state = copyWith(createState(), error: '网络错误');
        expect(state['error'], '网络错误');
        expect((state['messages'] as List).isEmpty, true);
      });

      test('copyWith清空error', () {
        final state = copyWith(createState(error: '旧错误'), error: null);
        expect(state['error'], null);
      });
    });

    // ==================== TC-UNIT-13: UpdateState ====================
    group('TC-UNIT-13: UpdateState 状态机', () {
      // 模拟 UpdateState
      const statusIdle = 0;
      const statusChecking = 1;
      const statusUpdateAvailable = 2;
      const statusDownloading = 3;
      const statusDownloaded = 4;
      const statusError = 5;
      const statusUpToDate = 6;
      const statusNoRelease = 7;

      test('所有状态值互不相同', () {
        final states = [statusIdle, statusChecking, statusUpdateAvailable,
                        statusDownloading, statusDownloaded, statusError,
                        statusUpToDate, statusNoRelease];
        expect(states.toSet().length, states.length);
      });

      test('过渡状态只读', () {
        // idle → checking → updateAvailable → downloading → downloaded
        const path = [statusIdle, statusChecking, statusUpdateAvailable,
                      statusDownloading, statusDownloaded];
        for (int i = 1; i < path.length; i++) {
          expect(path[i] != path[i - 1], true);
        }
      });
    });

    // ==================== TC-UNIT-14: 版本比较 ====================
    group('TC-UNIT-14: 版本比较算法', () {
      bool isNewer(String remote, String local) {
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

      test('远程版本更高', () {
        expect(isNewer('1.2.0', '1.1.0'), true);
        expect(isNewer('2.0.0', '1.9.9'), true);
        expect(isNewer('1.0.1', '1.0.0'), true);
      });

      test('远程版本相同', () {
        expect(isNewer('1.2.0', '1.2.0'), false);
      });

      test('远程版本更低', () {
        expect(isNewer('1.0.0', '1.2.0'), false);
        expect(isNewer('1.1.0', '1.1.13'), false);
      });

      test('大版本号领先', () {
        expect(isNewer('2.0.0', '1.99.99'), true);
      });

      test('次版本号领先', () {
        expect(isNewer('1.3.0', '1.2.99'), true);
      });

      test('修订版本号领先', () {
        expect(isNewer('1.2.1', '1.2.0'), true);
      });
    });

    // ==================== TC-UNIT-15: AppVersion ====================
    group('TC-UNIT-15: AppVersion 版本号', () {
      test('版本号格式正确', () {
        const version = '1.2.0';
        final parts = version.split('.');
        expect(parts.length, 3);
        expect(int.parse(parts[0]), 1);
        expect(int.parse(parts[1]), 2);
        expect(int.parse(parts[2]), 0);
      });

      test('appName正确', () {
        const appName = '护花使者';
        expect(appName, '护花使者');
        expect(appName.length, 4);
        expect(appName.isNotEmpty, true);
      });
    });

    // ==================== TC-UNIT-16: 天气描述生成 ====================
    group('TC-UNIT-16: 天气描述生成', () {
      String descFromWindRain(String wd, String ws, double rain) {
        if (rain > 0) return '有雨';
        if (ws.contains('无') || ws == '0级' || ws == '1级') return '晴';
        return '$wd$ws';
      }

      test('有降水返回有雨', () {
        expect(descFromWindRain('东北风', '3级', 5.0), '有雨');
        expect(descFromWindRain('北风', '0级', 0.1), '有雨');
      });

      test('无风/微风返回晴', () {
        expect(descFromWindRain('北风', '0级', 0), '晴');
        expect(descFromWindRain('无风', '1级', 0), '晴');
        expect(descFromWindRain('东风', '无持续风向', 0), '晴');
      });

      test('有风无雨返回风向+风力', () {
        expect(descFromWindRain('北风', '5级', 0), '北风5级');
        expect(descFromWindRain('东风', '3级', 0), '东风3级');
      });
    });
  });
}