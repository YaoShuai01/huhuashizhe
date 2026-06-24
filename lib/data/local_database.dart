import 'dart:convert';

class LocalDatabase {
  static final LocalDatabase _instance = LocalDatabase._();
  factory LocalDatabase() => _instance;
  LocalDatabase._();

  final Map<String, dynamic> _store = {};

  Future<void> init() async {}

  // 预设
  List<Map<String, dynamic>> getPresets() {
    final json = _store['presets'] ?? '[]';
    return List<Map<String, dynamic>>.from(jsonDecode(json as String));
  }

  void savePresets(List<Map<String, dynamic>> presets) {
    _store['presets'] = jsonEncode(presets);
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

  // 作业任务
  List<Map<String, dynamic>> getMissions() {
    final json = _store['missions'] ?? '[]';
    return List<Map<String, dynamic>>.from(jsonDecode(json as String));
  }

  void saveMissions(List<Map<String, dynamic>> missions) {
    _store['missions'] = jsonEncode(missions);
  }

  void addMission(Map<String, dynamic> mission) {
    final missions = getMissions();
    mission['id'] = DateTime.now().millisecondsSinceEpoch.toString();
    mission['createdAt'] = DateTime.now().toIso8601String();
    missions.insert(0, mission);
    saveMissions(missions);
  }

  // 设置
  bool getBool(String key) => _store[key] as bool? ?? false;
  void setBool(String key, bool value) { _store[key] = value; }
  String? get(String key) => _store[key] as String?;
  void set(String key, String value) { _store[key] = value; }
  void remove(String key) { _store.remove(key); }

  // 收藏
  List<String> getFavorites() =>
      (_store['favorites'] as List?)?.cast<String>() ?? [];

  void toggleFavorite(String courseId) {
    final favorites = getFavorites();
    if (favorites.contains(courseId)) {
      favorites.remove(courseId);
    } else {
      favorites.add(courseId);
    }
    _store['favorites'] = favorites;
  }
}