import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../data/local_database.dart';
import 'classroom_courses.dart';

/// 小课堂的阅读数与收藏，持久化在 [LocalDatabase]（documents 目录 JSON）。
///
/// 两个存储键：
/// - [readCountsKey]：`{课程id: 本机累计阅读次数}`，与内置基数相加后展示
/// - [favoritesKey]：`[课程id, ...]`
///
/// 收藏用独立键，不复用 `LocalDatabase.toggleFavorite()` 的 `favorites`
/// （那个 key 语义含糊，且当前无调用方）。
class ClassroomStore extends ChangeNotifier {
  ClassroomStore({LocalDatabase? database}) : _db = database ?? LocalDatabase() {
    _load();
  }

  /// 全局共享实例：列表页、详情页、收藏页必须看到同一份数据
  static final ClassroomStore instance = ClassroomStore();

  static const String readCountsKey = 'classroom_read_counts';
  static const String favoritesKey = 'classroom_favorites';

  final LocalDatabase _db;

  /// 本机累计的真实阅读次数（不含展示基数）
  final Map<String, int> _reads = {};

  final Set<String> _favoriteIds = {};

  void _load() {
    final rawReads = _db.get(readCountsKey);
    if (rawReads != null) {
      try {
        final decoded = jsonDecode(rawReads);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            final count = value is int ? value : int.tryParse('$value');
            if (count != null && key is String) _reads[key] = count;
          });
        }
      } catch (_) {
        // 文件损坏时从空数据开始，不影响页面
      }
    }

    final rawFavorites = _db.get(favoritesKey);
    if (rawFavorites != null) {
      try {
        final decoded = jsonDecode(rawFavorites);
        if (decoded is List) {
          _favoriteIds.addAll(decoded.whereType<String>());
        }
      } catch (_) {
        // 同上
      }
    }
  }

  /// 展示用的基数：由 id 稳定推导出 60~199，避免所有课程显示同一个数字
  static int seedReads(String courseId) {
    var hash = 0;
    for (final unit in courseId.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return 60 + hash % 140;
  }

  /// 展示给用户的阅读数 = 内置基数 + 本机累计
  int readCount(String courseId) => seedReads(courseId) + (_reads[courseId] ?? 0);

  /// 进入课程详情时调用，返回累加后的阅读数
  int incrementRead(String courseId) {
    _reads[courseId] = (_reads[courseId] ?? 0) + 1;
    _db.set(readCountsKey, jsonEncode(_reads));
    notifyListeners();
    return readCount(courseId);
  }

  /// 从存储重新加载，供测试隔离状态使用
  void reload() {
    _reads.clear();
    _favoriteIds.clear();
    _load();
    notifyListeners();
  }

  bool isFavorite(String courseId) => _favoriteIds.contains(courseId);

  /// 切换收藏，返回切换后的状态
  bool toggleFavorite(String courseId) {
    final nowFavorite = !_favoriteIds.remove(courseId);
    if (nowFavorite) _favoriteIds.add(courseId);
    _db.set(favoritesKey, jsonEncode(_favoriteIds.toList()));
    notifyListeners();
    return nowFavorite;
  }

  int get favoriteCount => _favoriteIds.length;

  /// 收藏的课程，按课程表的原始顺序返回；已下架的 id 自动跳过
  List<Course> get favoriteCourses =>
      classroomCourses.where((c) => _favoriteIds.contains(c.id)).toList();
}
