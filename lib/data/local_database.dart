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
    // 预热缓存：从文件加载到内存
    for (final key in ['presets', 'missions', 'favorites', 'settings', 'ai_chat_history']) {
      final file = File(_filePath(key));
      if (await file.exists()) {
        _cache[key] = await file.readAsString();
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
}
