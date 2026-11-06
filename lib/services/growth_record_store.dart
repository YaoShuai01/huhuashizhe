import 'package:flutter/foundation.dart';

import '../data/local_database.dart';

/// 单条作物问题采集组
class ProblemGroup {
  final String labelIndex; // 模型类别索引（字符串便于JSON存储）
  final String zhName;
  final String desc;
  double maxConfidence;
  int hitCount;
  List<String> imagePaths; // .ys 加密文件绝对路径

  ProblemGroup({
    required this.labelIndex,
    required this.zhName,
    required this.desc,
    this.maxConfidence = 0,
    this.hitCount = 0,
    List<String>? imagePaths,
  }) : imagePaths = imagePaths ?? [];

  Map<String, dynamic> toJson() => {
        'labelIndex': labelIndex,
        'zhName': zhName,
        'desc': desc,
        'maxConfidence': maxConfidence,
        'hitCount': hitCount,
        'imagePaths': imagePaths,
      };

  factory ProblemGroup.fromJson(Map<String, dynamic> json) => ProblemGroup(
        labelIndex: json['labelIndex']?.toString() ?? '0',
        zhName: json['zhName']?.toString() ?? '未知问题',
        desc: json['desc']?.toString() ?? '',
        maxConfidence: (json['maxConfidence'] as num?)?.toDouble() ?? 0,
        hitCount: (json['hitCount'] as num?)?.toInt() ?? 0,
        imagePaths: List<String>.from(json['imagePaths'] ?? []),
      );
}

/// 生长检测记录（模型测试结束同步生成）
class GrowthRecord {
  String id;
  String name; // 默认：地区+时间，用户可改名
  String locationName; // 某某市某某县/区
  String timeText; // 固定时间戳文本（不可修改）
  DateTime createdAt;
  List<ProblemGroup> problems;
  String? aiSuggestion; // AI处理建议
  bool aiPending; // AI建议是否待生成（离线暂存）
  List<Map<String, dynamic>> chat; // AI追问对话历史 [{role,content,ts}]

  GrowthRecord({
    required this.id,
    required this.name,
    required this.locationName,
    required this.timeText,
    required this.createdAt,
    required this.problems,
    this.aiSuggestion,
    this.aiPending = false,
    List<Map<String, dynamic>>? chat,
  }) : chat = chat ?? [];

  int get totalImages =>
      problems.fold(0, (sum, p) => sum + p.imagePaths.length);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'locationName': locationName,
        'timeText': timeText,
        'createdAt': createdAt.toIso8601String(),
        'problems': problems.map((p) => p.toJson()).toList(),
        'aiSuggestion': aiSuggestion,
        'aiPending': aiPending,
        'chat': chat,
      };

  factory GrowthRecord.fromJson(Map<String, dynamic> json) => GrowthRecord(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '未命名记录',
        locationName: json['locationName']?.toString() ?? '',
        timeText: json['timeText']?.toString() ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
                DateTime.now(),
        problems: (json['problems'] as List<dynamic>? ?? [])
            .map((p) => ProblemGroup.fromJson(Map<String, dynamic>.from(p)))
            .toList(),
        aiSuggestion: json['aiSuggestion']?.toString(),
        aiPending: json['aiPending'] == true,
        chat: (json['chat'] as List<dynamic>? ?? [])
            .map((c) => Map<String, dynamic>.from(c))
            .toList(),
      );
}

/// 生长检测记录存储（文件JSON持久化，随App更新保留）
class GrowthRecordStore {
  static final GrowthRecordStore _instance = GrowthRecordStore._();
  factory GrowthRecordStore() => _instance;
  GrowthRecordStore._();

  static const _storageKey = 'growth_records';
  final LocalDatabase _db = LocalDatabase();

  /// 新增记录（置顶），返回id
  String add(GrowthRecord record) {
    final list = getAll();
    list.insert(0, record);
    _save(list);
    return record.id;
  }

  List<GrowthRecord> getAll() {
    final raw = _db.getDataList(_storageKey);
    return raw.map((e) => GrowthRecord.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  GrowthRecord? getById(String id) {
    for (final r in getAll()) {
      if (r.id == id) return r;
    }
    return null;
  }

  void update(GrowthRecord record) {
    final list = getAll();
    final idx = list.indexWhere((r) => r.id == record.id);
    if (idx >= 0) {
      list[idx] = record;
      _save(list);
    }
  }

  void rename(String id, String newName) {
    final r = getById(id);
    if (r != null) {
      r.name = newName;
      update(r);
    }
  }

  void delete(String id) {
    final list = getAll();
    list.removeWhere((r) => r.id == id);
    _save(list);
  }

  /// 所有AI建议待补全的记录id
  List<GrowthRecord> pendingAiRecords() {
    return getAll().where((r) => r.aiPending).toList();
  }

  void _save(List<GrowthRecord> records) {
    _db.saveDataList(
        _storageKey, records.map((r) => r.toJson()).toList());
    debugPrint('[GrowthStore] 已持久化 ${records.length} 条记录');
  }
}
