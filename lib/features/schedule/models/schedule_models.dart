import 'dart:convert';

/// 轮协成员
class ScheduleMember {
  final String id;
  final String name;
  final bool active;

  /// 是否已通过姓名验证（由服务端记录，客户端只读）
  final bool verified;

  /// 最近一次在线心跳时间（服务端返回）
  final String? lastSeenAt;

  /// 是否在线（服务端按心跳时间计算，客户端只读）
  final bool online;

  /// 成员编号，按加入顺序分配，用于“X号成员”
  final int? seq;

  const ScheduleMember({
    required this.id,
    required this.name,
    this.active = true,
    this.verified = false,
    this.lastSeenAt,
    this.online = false,
    this.seq,
  });

  factory ScheduleMember.fromJson(Map<String, dynamic> json) {
    return ScheduleMember(
      id: (json['id'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
      active: json['active'] != false,
      verified: json['verified'] == true,
      lastSeenAt: json['lastSeenAt'] as String?,
      online: json['online'] == true,
      seq: (json['seq'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'active': active,
    if (seq != null) 'seq': seq,
  };

  ScheduleMember copyWith({String? name, bool? active, int? seq}) {
    return ScheduleMember(
      id: id,
      name: name ?? this.name,
      active: active ?? this.active,
      verified: verified,
      lastSeenAt: lastSeenAt,
      online: online,
      seq: seq ?? this.seq,
    );
  }
}

/// 单日变更
class ScheduleDayChange {
  final String date;
  final String? from;
  final String? to;

  const ScheduleDayChange({required this.date, this.from, this.to});

  factory ScheduleDayChange.fromJson(Map<String, dynamic> json) {
    return ScheduleDayChange(
      date: json['date'] as String? ?? '',
      from: json['from'] as String?,
      to: json['to'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {'date': date, 'from': from, 'to': to};
}

/// 一次提交产生的变更日志
class ScheduleChangeEntry {
  final String at;
  final String by;
  final List<ScheduleDayChange> changes;
  final bool truncated;

  const ScheduleChangeEntry({
    required this.at,
    required this.by,
    required this.changes,
    this.truncated = false,
  });

  factory ScheduleChangeEntry.fromJson(Map<String, dynamic> json) {
    return ScheduleChangeEntry(
      at: json['at'] as String? ?? '',
      by: json['by'] as String? ?? '',
      changes:
          (json['changes'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>()
              .map(ScheduleDayChange.fromJson)
              .toList(),
      truncated: json['truncated'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'at': at,
    'by': by,
    'changes': changes.map((e) => e.toJson()).toList(),
    if (truncated) 'truncated': true,
  };
}

/// 轮协表完整数据
class ScheduleData {
  final int schemaVersion;
  final int revision;
  final String updatedAt;
  final String updatedBy;
  final List<ScheduleMember> members;

  /// key: yyyy-MM-dd, value: memberId
  final Map<String, String> assignments;

  /// 自定义顺延序列（成员 ID 顺序）
  final List<String> rotation;
  final List<ScheduleChangeEntry> changeLog;

  const ScheduleData({
    required this.schemaVersion,
    required this.revision,
    required this.updatedAt,
    required this.updatedBy,
    required this.members,
    required this.assignments,
    required this.rotation,
    required this.changeLog,
  });

  factory ScheduleData.empty() {
    return const ScheduleData(
      schemaVersion: 1,
      revision: 0,
      updatedAt: '',
      updatedBy: 'system',
      members: [],
      assignments: {},
      rotation: [],
      changeLog: [],
    );
  }

  factory ScheduleData.fromJson(Map<String, dynamic> json) {
    final rawAssignments = json['assignments'];
    final assignments = <String, String>{};
    if (rawAssignments is Map) {
      for (final entry in rawAssignments.entries) {
        final key = entry.key.toString();
        final value = entry.value?.toString() ?? '';
        if (key.isNotEmpty && value.isNotEmpty) {
          assignments[key] = value;
        }
      }
    }

    return ScheduleData(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      updatedAt: json['updatedAt'] as String? ?? '',
      updatedBy: json['updatedBy'] as String? ?? '',
      members:
          (json['members'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>()
              .map(ScheduleMember.fromJson)
              .toList(),
      assignments: assignments,
      rotation:
          (json['rotation'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList(),
      changeLog:
          (json['changeLog'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>()
              .map(ScheduleChangeEntry.fromJson)
              .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'revision': revision,
    'updatedAt': updatedAt,
    'updatedBy': updatedBy,
    'members': members.map((e) => e.toJson()).toList(),
    'assignments': assignments,
    'rotation': rotation,
    'changeLog': changeLog.map((e) => e.toJson()).toList(),
  };

  String encode() => jsonEncode(toJson());

  static ScheduleData? tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>)
        return ScheduleData.fromJson(decoded);
      if (decoded is Map)
        return ScheduleData.fromJson(Map<String, dynamic>.from(decoded));
      return null;
    } catch (_) {
      return null;
    }
  }

  List<ScheduleMember> get activeMembers =>
      members.where((m) => m.active).toList();

  ScheduleMember? memberById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final m in members) {
      if (m.id == id) return m;
    }
    return null;
  }

  String memberName(String? id) => memberById(id)?.name ?? '未安排';

  /// 某成员的全部协管日期，升序
  List<DateTime> datesForMember(String memberId) {
    final dates =
        assignments.entries
            .where((e) => e.value == memberId)
            .map((e) => ScheduleDate.tryParseKey(e.key))
            .whereType<DateTime>()
            .toList();
    dates.sort();
    return dates;
  }

  /// 某成员今天及以后的协管日期
  List<DateTime> upcomingDatesForMember(String memberId, {DateTime? now}) {
    final today = ScheduleDate.today(now);
    return datesForMember(
      memberId,
    ).where((d) => !ScheduleDate.dayOnly(d).isBefore(today)).toList();
  }

  List<DateTime> get upcomingDutyDates {
    final today = ScheduleDate.today();
    final dates =
        assignments.keys
            .map(ScheduleDate.tryParseKey)
            .whereType<DateTime>()
            .where((d) => !ScheduleDate.dayOnly(d).isBefore(today))
            .toList();
    dates.sort();
    return dates;
  }

  bool isMemberOnDuty(String memberId, DateTime date) {
    return assignments[ScheduleDate.key(date)] == memberId;
  }

  ScheduleData copyWith({
    int? schemaVersion,
    int? revision,
    String? updatedAt,
    String? updatedBy,
    List<ScheduleMember>? members,
    Map<String, String>? assignments,
    List<String>? rotation,
    List<ScheduleChangeEntry>? changeLog,
  }) {
    return ScheduleData(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      revision: revision ?? this.revision,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
      members: members ?? this.members,
      assignments: assignments ?? this.assignments,
      rotation: rotation ?? this.rotation,
      changeLog: changeLog ?? this.changeLog,
    );
  }
}

/// 认证结果
class ScheduleAuthResult {
  final String token;
  final String role;
  final DateTime? expiresAt;

  const ScheduleAuthResult({
    required this.token,
    required this.role,
    this.expiresAt,
  });

  bool get isAdmin => role == 'admin';

  factory ScheduleAuthResult.fromJson(Map<String, dynamic> json) {
    return ScheduleAuthResult(
      token: json['token'] as String? ?? '',
      role: json['role'] as String? ?? 'member',
      expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? ''),
    );
  }
}

/// 提交结果
class ScheduleSubmitResult {
  final ScheduleData schedule;
  final List<ScheduleDayChange> changes;
  final List<String> changedMemberIds;

  const ScheduleSubmitResult({
    required this.schedule,
    required this.changes,
    required this.changedMemberIds,
  });

  factory ScheduleSubmitResult.fromJson(Map<String, dynamic> json) {
    final scheduleJson = json['schedule'];
    return ScheduleSubmitResult(
      schedule:
          scheduleJson is Map
              ? ScheduleData.fromJson(Map<String, dynamic>.from(scheduleJson))
              : ScheduleData.empty(),
      changes:
          (json['changes'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>()
              .map(ScheduleDayChange.fromJson)
              .toList(),
      changedMemberIds:
          (json['changedMemberIds'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList(),
    );
  }
}

/// 留言池回复
class ScheduleReply {
  final String id;
  final String content;
  final String createdAt;
  final bool isMine;

  const ScheduleReply({
    required this.id,
    required this.content,
    required this.createdAt,
    required this.isMine,
  });

  factory ScheduleReply.fromJson(Map<String, dynamic> json) {
    return ScheduleReply(
      id: json['id'] as String? ?? '',
      content: json['content'] as String? ?? '',
      createdAt: json['createdAt'] as String? ?? '',
      isMine: json['isMine'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'createdAt': createdAt,
    'isMine': isMine,
  };
}

/// 匿名留言
class ScheduleMessage {
  final String id;
  final String content;
  final String createdAt;
  final bool isMine;
  final List<ScheduleReply> replies;

  const ScheduleMessage({
    required this.id,
    required this.content,
    required this.createdAt,
    required this.isMine,
    required this.replies,
  });

  factory ScheduleMessage.fromJson(Map<String, dynamic> json) {
    return ScheduleMessage(
      id: json['id'] as String? ?? '',
      content: json['content'] as String? ?? '',
      createdAt: json['createdAt'] as String? ?? '',
      isMine: json['isMine'] == true,
      replies:
          (json['replies'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>()
              .map(ScheduleReply.fromJson)
              .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'createdAt': createdAt,
    'isMine': isMine,
    'replies': replies.map((e) => e.toJson()).toList(),
  };
}

/// 日期工具：轮协日期统一按本地日历日处理，只保留年月日。
class ScheduleDate {
  ScheduleDate._();

  static DateTime today([DateTime? now]) => dayOnly(now ?? DateTime.now());

  static DateTime dayOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static String key(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static DateTime? tryParseKey(String value) {
    final parts = value.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    final date = DateTime(y, m, d);
    if (date.year != y || date.month != m || date.day != d) return null;
    return date;
  }

  static String monthLabel(DateTime date) => '${date.year}年${date.month}月';

  static String shortLabel(DateTime date) => '${date.month}月${date.day}日';

  static String fullLabel(DateTime date) =>
      '${date.year}年${date.month}月${date.day}日';

  static const List<String> _weekdays = [
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  static String weekday(DateTime date) => _weekdays[date.weekday - 1];

  static String shortWithWeekday(DateTime date) =>
      '${shortLabel(date)} ${weekday(date)}';

  static int daysBetween(DateTime from, DateTime to) {
    return dayOnly(to).difference(dayOnly(from)).inDays;
  }

  static bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// 生成某个月的日历格子：前面补空到周一，每行 7 天。
  static List<DateTime?> monthGrid(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = first.weekday - 1;
    final cells = <DateTime?>[];
    for (var i = 0; i < leading; i++) {
      cells.add(null);
    }
    for (var day = 1; day <= daysInMonth; day++) {
      cells.add(DateTime(month.year, month.month, day));
    }
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return cells;
  }
}
