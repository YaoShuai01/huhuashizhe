import 'dart:async';

import 'package:dio/dio.dart';

import '../../data/local_database.dart';

/// 轮协 Worker 地址配置。
///
/// 地址不写死在源码里：优先用编译参数 `--dart-define=SCHEDULE_API_URL=...`，
/// 否则从公开仓库的 config/schedule.json 读取并缓存 24 小时。
/// 这样 Worker 换域名/换后端时，不需要重新发版。
class ScheduleConfig {
  ScheduleConfig._();

  static const String _repo = 'YaoShuai01/huhuashizhe';
  static const String _branch = 'main';
  static const String _configPath = 'config/schedule.json';

  static const String _cacheKey = 'schedule_api_base_url';
  static const String _cacheAtKey = 'schedule_api_base_url_at';
  static const Duration _cacheTtl = Duration(hours: 24);

  /// 编译期覆盖，测试或临时部署时使用
  static const String buildOverride = String.fromEnvironment(
    'SCHEDULE_API_URL',
  );

  /// 兜底地址：GitHub 配置拉取失败时使用，保证新设备首次进入可用
  static const String _fallbackBaseUrl = 'https://437iy0be1396.vicp.fun';

  static List<String> get _configUrls => [
    'https://raw.githubusercontent.com/$_repo/$_branch/$_configPath',
    for (final prefix in const [
      'https://ghfast.top/',
      'https://ghproxy.net/',
      'https://gh-proxy.com/',
    ])
      '${prefix}https://raw.githubusercontent.com/$_repo/$_branch/$_configPath',
  ];

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  static String? _memoryCache;

  /// 解析 Worker 地址；返回 null 表示尚未配置或网络不可用。
  static Future<String?> resolveApiBaseUrl({bool forceRefresh = false}) async {
    if (buildOverride.trim().isNotEmpty) {
      return _normalize(buildOverride);
    }
    if (!forceRefresh && _memoryCache != null) {
      return _memoryCache;
    }

    final db = LocalDatabase();
    final cached = _normalize(db.get(_cacheKey));
    final cachedAt = DateTime.tryParse(db.get(_cacheAtKey) ?? '');
    if (!forceRefresh &&
        cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheTtl) {
      _memoryCache = cached;
      return cached;
    }

    // 多通道并发拉取，避免代理逐个失败时启动过慢
    final remote = await _fetchFirstAvailable();
    if (remote != null) {
      _memoryCache = remote;
      db.set(_cacheKey, remote);
      db.set(_cacheAtKey, DateTime.now().toIso8601String());
      return remote;
    }

    // 网络失败时退回旧缓存，至少让已配置过的设备还能用
    if (cached != null) {
      _memoryCache = cached;
      return cached;
    }

    // 首次进入且配置不可达时使用内置兜底地址，避免卡在“轮协服务未配置”
    _memoryCache = _fallbackBaseUrl;
    db.set(_cacheKey, _fallbackBaseUrl);
    db.set(_cacheAtKey, DateTime.now().toIso8601String());
    return _fallbackBaseUrl;
  }

  static Future<String?> _fetchFirstAvailable() {
    final completer = Completer<String?>();
    var remaining = _configUrls.length;
    for (final url in _configUrls) {
      _fetchConfig(url)
          .then((value) {
            if (value != null && !completer.isCompleted)
              completer.complete(value);
          })
          .whenComplete(() {
            remaining--;
            if (remaining == 0 && !completer.isCompleted)
              completer.complete(null);
          });
    }
    return completer.future;
  }

  static Future<String?> _fetchConfig(String url) async {
    try {
      final response = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: {'cache-control': 'no-cache'},
        ),
      );
      final text = response.data?.trim() ?? '';
      if (text.isEmpty) return null;
      return _normalize(_tryDecode(text));
    } catch (_) {
      return null;
    }
  }

  static String? _tryDecode(String text) {
    try {
      // 简单解析，避免为一个小配置文件引入额外依赖
      final match = RegExp(r'"apiBaseUrl"\s*:\s*"([^"]*)"').firstMatch(text);
      return match?.group(1);
    } catch (_) {
      return null;
    }
  }

  static String? _normalize(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      return null;
    }
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }
}
