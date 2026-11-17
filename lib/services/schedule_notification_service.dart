import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/local_database.dart';
import '../features/schedule/models/schedule_models.dart';

/// 协管本地通知
///
/// - 协管前一天 17:00（北京时间）提醒
/// - 轮协变更立即提醒
/// - 所有通知都是本地定时，不依赖推送服务
class ScheduleNotificationService {
  ScheduleNotificationService._();
  static final ScheduleNotificationService instance = ScheduleNotificationService._();

  static const String _channelId = 'duty_reminder';
  static const String _channelName = '协管提醒';
  static const String _channelDescription = '协管前一天 17:00 提醒';
  static const String _scheduledIdsKey = 'schedule_notification_ids';
  static const String _immediateShownKey = 'schedule_immediate_reminder_dates';
  static const String _permissionAskedKey = 'schedule_notification_permission_asked';
  static const String _permissionGrantedKey = 'schedule_notification_permission_granted';
  static const int _changeNotificationId = 990001;
  static const int _immediateNotificationId = 990002;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _permissionGranted = false;
  bool _exactAlarmsAllowed = false;
  final Set<int> _scheduledIds = {};

  bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get permissionGranted => _permissionGranted;
  bool get exactAlarmsAllowed => _exactAlarmsAllowed;
  bool get permissionAsked => LocalDatabase().getBool(_permissionAskedKey);

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    if (!isSupported) return;
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    } catch (e) {
      debugPrint('[ScheduleNotify] 时区初始化失败: $e');
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestSoundPermission: false,
      requestBadgePermission: false,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );
    try {
      await _plugin.initialize(settings);
    } catch (e) {
      debugPrint('[ScheduleNotify] 插件初始化失败: $e');
      return;
    }

    _loadScheduledIds();

    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      try {
        await android?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDescription,
            importance: Importance.high,
          ),
        );
        _permissionGranted = await android?.areNotificationsEnabled() ?? false;
        _exactAlarmsAllowed =
            await android?.canScheduleExactNotifications() ?? false;
      } catch (e) {
        debugPrint('[ScheduleNotify] Android 初始化失败: $e');
      }
    } else {
      // iOS 无法静默查询；从本地记录恢复上次结果
      _permissionGranted = LocalDatabase().getBool(_permissionGrantedKey);
    }
  }

  /// 在用户绑定姓名后调用，避免启动时突然弹权限框
  Future<bool> requestPermissions() async {
    await init();
    if (!isSupported) return false;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        final granted = await android?.requestNotificationsPermission();
        if (granted != null) _permissionGranted = granted;
        final exact = await android?.requestExactAlarmsPermission();
        if (exact != null) _exactAlarmsAllowed = exact;
        _exactAlarmsAllowed =
            await android?.canScheduleExactNotifications() ?? _exactAlarmsAllowed;
      } else {
        final ios = _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        final granted = await ios?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        if (granted != null) _permissionGranted = granted;
      }
    } catch (e) {
      debugPrint('[ScheduleNotify] 权限请求失败: $e');
    }
    LocalDatabase().setBool(_permissionAskedKey, true);
    LocalDatabase().setBool(_permissionGrantedKey, _permissionGranted);
    return _permissionGranted;
  }

  /// 从系统设置返回后重新读取权限状态
  Future<void> refreshPermissionStatus() async {
    await init();
    if (!isSupported) return;
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        _permissionGranted =
            await android?.areNotificationsEnabled() ?? _permissionGranted;
        _exactAlarmsAllowed =
            await android?.canScheduleExactNotifications() ?? _exactAlarmsAllowed;
      } catch (_) {}
    }
    LocalDatabase().setBool(_permissionGrantedKey, _permissionGranted);
  }

  /// 按成员重新安排所有未来协管提醒
  Future<void> rescheduleForMember(
    ScheduleData schedule,
    String? memberId,
  ) async {
    await init();
    await _cancelScheduled();
    if (!isSupported || memberId == null || memberId.isEmpty) return;
    if (!_permissionGranted) return;

    final dates = schedule.upcomingDatesForMember(memberId);
    final now = tz.TZDateTime.now(tz.local);
    final today = ScheduleDate.today();
    final immediateShown = _loadImmediateShown();

    for (final date in dates.take(60)) {
      final prevDay = DateTime(date.year, date.month, date.day - 1);
      final remindAt = tz.TZDateTime(
        tz.local,
        prevDay.year,
        prevDay.month,
        prevDay.day,
        17,
      );
      final id = _notificationId(date);

      if (remindAt.isAfter(now)) {
        final ok = await _zonedSchedule(
          id: id,
          title: '协管提醒',
          body:
              '明天（${ScheduleDate.shortLabel(date)} ${ScheduleDate.weekday(date)}）轮到你协管，请提前安排。',
          scheduledDate: remindAt,
          payload: ScheduleDate.key(date),
        );
        if (ok) _scheduledIds.add(id);
        continue;
      }

      // 17:00 已过：如果协管日就是明天，立即补一条提醒（每天只补一次）
      final tomorrow = today.add(const Duration(days: 1));
      if (ScheduleDate.isSameDay(date, tomorrow)) {
        final key = ScheduleDate.key(date);
        if (!immediateShown.contains(key)) {
          await showImmediateReminder(date);
          immediateShown.add(key);
          _saveImmediateShown(immediateShown);
        }
      }
    }

    _saveScheduledIds();
  }

  Future<void> showImmediateReminder(DateTime dutyDate) async {
    await init();
    if (!isSupported || !_permissionGranted) return;
    try {
      await _plugin.show(
        _immediateNotificationId,
        '明天协管提醒',
        '明天（${ScheduleDate.shortLabel(dutyDate)} ${ScheduleDate.weekday(dutyDate)}）轮到你协管，请提前安排。',
        _details(),
        payload: ScheduleDate.key(dutyDate),
      );
    } catch (e) {
      debugPrint('[ScheduleNotify] 立即提醒失败: $e');
    }
  }

  /// 轮协变更通知：只列出新增和取消的日期
  Future<void> showScheduleChanged({
    required List<DateTime> added,
    required List<DateTime> removed,
  }) async {
    await init();
    if (!isSupported || !_permissionGranted) return;
    if (added.isEmpty && removed.isEmpty) return;

    final parts = <String>[];
    if (added.isNotEmpty) {
      parts.add('新增 ${added.take(3).map(ScheduleDate.shortLabel).join('、')}');
    }
    if (removed.isNotEmpty) {
      parts.add('取消 ${removed.take(3).map(ScheduleDate.shortLabel).join('、')}');
    }
    final more = added.length + removed.length > 6 ? ' 等' : '';
    try {
      await _plugin.show(
        _changeNotificationId,
        '轮协变更',
        '你的协管日期有调整：${parts.join('；')}$more。',
        _details(),
      );
    } catch (e) {
      debugPrint('[ScheduleNotify] 变更通知失败: $e');
    }
  }

  /// 退出轮协 / 切换身份时清理已排期的提醒
  Future<void> cancelAllScheduleNotifications() async {
    await init();
    await _cancelScheduled();
    _saveScheduledIds();
  }

  Future<bool> _zonedSchedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    String? payload,
  }) async {
    final mode = _exactAlarmsAllowed
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        _details(),
        androidScheduleMode: mode,
        payload: payload,
      );
      return true;
    } catch (e) {
      debugPrint('[ScheduleNotify] 精确闹钟失败，回退非精确: $e');
      try {
        await _plugin.zonedSchedule(
          id,
          title,
          body,
          scheduledDate,
          _details(),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: payload,
        );
        return true;
      } catch (e2) {
        debugPrint('[ScheduleNotify] 排期失败: $e2');
        return false;
      }
    }
  }

  NotificationDetails _details() {
    const android = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const darwin = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    return const NotificationDetails(android: android, iOS: darwin);
  }

  int _notificationId(DateTime date) =>
      date.year * 10000 + date.month * 100 + date.day;

  Future<void> _cancelScheduled() async {
    if (!isSupported) return;
    for (final id in _scheduledIds) {
      try {
        await _plugin.cancel(id);
      } catch (_) {}
    }
    _scheduledIds.clear();
  }

  void _loadScheduledIds() {
    final raw = LocalDatabase().get(_scheduledIdsKey);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw);
      if (list is List) {
        _scheduledIds
          ..clear()
          ..addAll(list.map((e) => int.tryParse(e.toString()) ?? 0).where((e) => e > 0));
      }
    } catch (_) {}
  }

  void _saveScheduledIds() {
    LocalDatabase().set(_scheduledIdsKey, jsonEncode(_scheduledIds.toList()));
  }

  Set<String> _loadImmediateShown() {
    final raw = LocalDatabase().get(_immediateShownKey);
    if (raw == null) return {};
    try {
      final list = jsonDecode(raw);
      if (list is List) return list.map((e) => e.toString()).toSet();
    } catch (_) {}
    return {};
  }

  void _saveImmediateShown(Set<String> dates) {
    // 只保留最近 60 天，避免文件无限增长
    final sorted = dates.toList()..sort();
    final keep = sorted.length > 60 ? sorted.sublist(sorted.length - 60) : sorted;
    LocalDatabase().set(_immediateShownKey, jsonEncode(keep));
  }
}
