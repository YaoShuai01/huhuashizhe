import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class LocalDatabase {
  static final LocalDatabase _instance = LocalDatabase._();
  factory LocalDatabase() => _instance;
  LocalDatabase._();

  final Map<String, dynamic> _cache = {};

  String? _dataDir;

  Future<String> _getDataDir() async {
    if (_dataDir != null) return _dataDir!;
    final dir = await getApplicationDocumentsDirectory();
    _dataDir = '${dir.path}/huhuashizhe_data';
    return _dataDir!;
  }

  String _filePath(String key) => '${_dataDir!}/$key.json';

  Future<void> init() async {
    final dataDir = await _getDataDir();
    final dir = Directory(dataDir);
    if (!await dir.exists()) await dir.create(recursive: true);
    // 预热缓存：加载目录下全部 .json 数据文件（含数据管理各模块与生长检测记录），
    // 避免仅预热固定key导致其余模块数据在重启后丢失
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        final key = entity.uri.pathSegments.last.replaceAll('.json', '');
        try {
          _cache[key] = await entity.readAsString();
        } catch (_) {
          // 单个文件损坏不影响其他数据加载
        }
      }
    }
  }

  /// 异步持久化到文件（内部使用，不阻塞调用方）
  Future<void> _persistToFile(String key) async {
    final content = _cache[key];
    if (content == null) return;
    final file = File(_filePath(key));
    await file.writeAsString(content as String);
  }

  String? _readCache(String key) {
    return _cache[key] as String?;
  }

  // ==================== 预设 ====================

  List<Map<String, dynamic>> getPresets() {
    final json = _readCache('presets') ?? '[]';
    return List<Map<String, dynamic>>.from(jsonDecode(json));
  }

  void savePresets(List<Map<String, dynamic>> presets) {
    _cache['presets'] = jsonEncode(presets);
    unawaited(_persistToFile('presets'));
  }

  void addPreset(Map<String, dynamic> preset) {
    final presets = getPresets();
    preset['id'] = DateTime.now().millisecondsSinceEpoch.toString();
    preset['createdAt'] = DateTime.now().toIso8601String();
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

  // ==================== 作业任务 ====================

  List<Map<String, dynamic>> getMissions() {
    final json = _readCache('missions') ?? '[]';
    return List<Map<String, dynamic>>.from(jsonDecode(json));
  }

  void saveMissions(List<Map<String, dynamic>> missions) {
    _cache['missions'] = jsonEncode(missions);
    unawaited(_persistToFile('missions'));
  }

  void addMission(Map<String, dynamic> mission) {
    final missions = getMissions();
    mission['id'] = DateTime.now().millisecondsSinceEpoch.toString();
    mission['createdAt'] = DateTime.now().toIso8601String();
    missions.insert(0, mission);
    saveMissions(missions);
  }

  // ==================== 设置 ====================

  bool getBool(String key) {
    final val = _readCache(key);
    if (val != null) return val.toLowerCase() == 'true';
    return false;
  }

  void setBool(String key, bool value) {
    _cache[key] = value.toString();
    unawaited(_persistToFile(key));
  }

  String? get(String key) => _readCache(key);

  void set(String key, String value) {
    _cache[key] = value;
    unawaited(_persistToFile(key));
  }

  void remove(String key) {
    _cache.remove(key);
    final file = File(_filePath(key));
    unawaited(file.exists().then((exists) { if (exists) file.delete(); }));
  }

  // ==================== 收藏 ====================

  List<String> getFavorites() {
    final json = _readCache('favorites') ?? '[]';
    return List<String>.from(jsonDecode(json));
  }

  void toggleFavorite(String courseId) {
    final favorites = getFavorites();
    if (favorites.contains(courseId)) {
      favorites.remove(courseId);
    } else {
      favorites.add(courseId);
    }
    _cache['favorites'] = jsonEncode(favorites);
    unawaited(_persistToFile('favorites'));
  }

  // ==================== 通用数据CRUD（PC端数据管理模块） ====================

  List<Map<String, dynamic>> getDataList(String storageKey) {
    final json = _readCache(storageKey) ?? '[]';
    return List<Map<String, dynamic>>.from(jsonDecode(json));
  }

  void saveDataList(String storageKey, List<Map<String, dynamic>> data) {
    _cache[storageKey] = jsonEncode(data);
    unawaited(_persistToFile(storageKey));
  }

  void addDataItem(String storageKey, Map<String, dynamic> item) {
    final list = getDataList(storageKey);
    item['id'] = DateTime.now().millisecondsSinceEpoch.toString();
    item['createdAt'] = DateTime.now().toIso8601String();
    list.insert(0, item);
    saveDataList(storageKey, list);
  }

  void updateDataItem(String storageKey, String id, Map<String, dynamic> item) {
    final list = getDataList(storageKey);
    final index = list.indexWhere((d) => d['id'] == id);
    if (index >= 0) {
      item['id'] = id;
      item['createdAt'] = list[index]['createdAt'];
      list[index] = item;
    }
    saveDataList(storageKey, list);
  }

  void deleteDataItem(String storageKey, String id) {
    final list = getDataList(storageKey);
    list.removeWhere((d) => d['id'] == id);
    saveDataList(storageKey, list);
  }
}
