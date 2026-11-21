import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/constants/schedule_config.dart';
import '../data/local_database.dart';
import '../features/schedule/models/schedule_models.dart';
import 'schedule_api.dart';
import 'schedule_notification_service.dart';

/// 轮协会话与静默同步
///
/// 负责：
/// - token / 成员身份的本地持久化
/// - 轮协缓存、启动/回前台/进页面时静默拉取
/// - 自己协管日期变化的检测与本地通知
/// - 管理员提交后的缓存刷新
class ScheduleService {
  ScheduleService._();
  static final ScheduleService instance = ScheduleService._();

  static const String _tokenKey = 'schedule_auth_token';
  static const String _roleKey = 'schedule_auth_role';
  static const String _memberIdKey = 'schedule_member_id';
  static const String _memberNameKey = 'schedule_member_name';
  static const String _cacheKey = 'schedule_cache';
  static const String _pendingChangeKey = 'schedule_pending_change';
  static const String _lastNotifiedRevisionKey =
      'schedule_last_notified_revision';
  static const String _lastSyncAtKey = 'schedule_last_sync_at';
  static const String _lastSyncFailedKey = 'schedule_last_sync_failed';

  static const Duration _syncInterval = Duration(minutes: 30);

  /// 在线心跳间隔；服务端按最近 5 分钟判断在线
  static const Duration _presenceInterval = Duration(minutes: 2);

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final ScheduleApi _api = ScheduleApi();

  ScheduleData? cachedSchedule;
  String? _token;
  String? _role;
  String? _memberId;
  String? _memberName;
  String? _pendingChangeMessage;
  DateTime? _lastSyncAt;
  bool _lastSyncFailed = false;
  bool _initialized = false;
  Future<ScheduleData?>? _inflight;
  Timer? _presenceTimer;

  /// 页面可监听这个值，实时显示轮协变更提示
  final ValueNotifier<String?> changeNotifier = ValueNotifier<String?>(null);

  bool get isInitialized => _initialized;
  bool get isAuthenticated => (_token?.isNotEmpty ?? false);
  String? get authToken => _token;
  bool get isAdmin => _role == 'admin';
  String? get role => _role;
  String? get memberId => _memberId;
  String? get memberName => _memberName;
  bool get hasMemberIdentity => (_memberId?.isNotEmpty ?? false);
  bool get lastSyncFailed => _lastSyncFailed;
  DateTime? get lastSyncAt => _lastSyncAt;
  String? get pendingChangeMessage => _pendingChangeMessage;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    cachedSchedule = ScheduleData.tryDecode(LocalDatabase().get(_cacheKey));
    _token = await _readSecure(_tokenKey);
    _role = await _readSecure(_roleKey);
    _memberId = await _readSecure(_memberIdKey);
    _memberName = await _readSecure(_memberNameKey);
    _pendingChangeMessage = LocalDatabase().get(_pendingChangeKey);
    _lastSyncAt = DateTime.tryParse(LocalDatabase().get(_lastSyncAtKey) ?? '');
    _lastSyncFailed = LocalDatabase().getBool(_lastSyncFailedKey);
    changeNotifier.value = _pendingChangeMessage;
    await ScheduleNotificationService.instance.init();
    // 应用重启/开机后 AlarmManager 可能被清空，按缓存重排一次
    await rescheduleNotifications();
    if (isAuthenticated && hasMemberIdentity) {
      _startPresence();
    }
  }

  /// 用团队密钥 / 管理员密钥登录，成功后长期保存 token
  Future<ScheduleAuthResult> authenticate(String key) async {
    await init();
    final result = await _api.authenticate(key.trim());
    await _writeSecure(_tokenKey, result.token);
    await _writeSecure(_roleKey, result.role);
    _token = result.token;
    _role = result.role;
    if (hasMemberIdentity) {
      _startPresence();
    }
    return result;
  }

  /// 首次进入时绑定姓名对应的成员 ID，并自动上报已验证与在线状态
  Future<void> selectMember(ScheduleMember member) async {
    await init();
    _memberId = member.id;
    _memberName = member.name;
    await _writeSecure(_memberIdKey, member.id);
    await _writeSecure(_memberNameKey, member.name);
    unawaited(_reportVerified(member.id));
    _startPresence();
    await rescheduleNotifications();
  }

  /// 退出轮协：清 token 和身份
  Future<void> logout() async {
    await init();
    _stopPresence();
    _token = null;
    _role = null;
    _memberId = null;
    _memberName = null;
    _pendingChangeMessage = null;
    changeNotifier.value = null;
    await Future.wait([
      _deleteSecure(_tokenKey),
      _deleteSecure(_roleKey),
      _deleteSecure(_memberIdKey),
      _deleteSecure(_memberNameKey),
    ]);
    LocalDatabase().remove(_pendingChangeKey);
    await ScheduleNotificationService.instance.cancelAllScheduleNotifications();
  }

  /// 清理失效 token，但保留成员身份和缓存
  Future<void> _clearInvalidToken() async {
    _stopPresence();
    _token = null;
    _role = null;
    await Future.wait([_deleteSecure(_tokenKey), _deleteSecure(_roleKey)]);
  }

  /// 姓名验证通过后立即通知服务端，避免成员仍显示“未验证”
  Future<void> _reportVerified(String memberId) async {
    final token = _token;
    if (token == null || token.isEmpty) return;
    try {
      await _api.verifyMember(token, memberId);
    } on ScheduleAuthException {
      await _clearInvalidToken();
    } catch (e) {
      debugPrint('[Schedule] 上报成员验证状态失败: $e');
    }
  }

  void _startPresence() {
    final token = _token;
    final member = _memberId;
    if (token == null || token.isEmpty || member == null || member.isEmpty) {
      return;
    }
    _presenceTimer ??= Timer.periodic(
      _presenceInterval,
      (_) => unawaited(_heartbeat()),
    );
    unawaited(_heartbeat());
  }

  void _stopPresence() {
    _presenceTimer?.cancel();
    _presenceTimer = null;
  }

  Future<void> _heartbeat() async {
    final token = _token;
    final member = _memberId;
    if (token == null || token.isEmpty || member == null || member.isEmpty) {
      _stopPresence();
      return;
    }
    try {
      await _api.sendPresence(token, member);
    } on ScheduleAuthException {
      await _clearInvalidToken();
    } catch (e) {
      debugPrint('[Schedule] 在线心跳失败: $e');
    }
  }

  /// 强制/节流拉取轮协。并发调用共享同一个请求。
  Future<ScheduleData?> refresh({bool force = false, bool silent = false}) {
    if (_inflight != null) return _inflight!;
    final future = _refreshInternal(force: force, silent: silent);
    _inflight = future;
    return future.whenComplete(() {
      _inflight = null;
    });
  }

  Future<ScheduleData?> _refreshInternal({
    required bool force,
    required bool silent,
  }) async {
    await init();
    if (_token == null || _token!.isEmpty) {
      if (silent) return cachedSchedule;
      throw const ScheduleAuthException('请先输入轮协密钥', code: 'no_token');
    }
    if (!force &&
        cachedSchedule != null &&
        _lastSyncAt != null &&
        DateTime.now().difference(_lastSyncAt!) < _syncInterval) {
      return cachedSchedule;
    }

    final old = cachedSchedule;
    try {
      final remote = await _api.fetchSchedule(_token!);
      await _applyRemoteSchedule(old, remote);
      _lastSyncAt = DateTime.now();
      _lastSyncFailed = false;
      LocalDatabase().set(_lastSyncAtKey, _lastSyncAt!.toIso8601String());
      LocalDatabase().setBool(_lastSyncFailedKey, false);
      return remote;
    } on ScheduleAuthException {
      await _clearInvalidToken();
      _lastSyncFailed = true;
      LocalDatabase().setBool(_lastSyncFailedKey, true);
      if (silent) return cachedSchedule;
      rethrow;
    } on ScheduleApiException {
      _lastSyncFailed = true;
      LocalDatabase().setBool(_lastSyncFailedKey, true);
      if (silent) return cachedSchedule;
      rethrow;
    } catch (e) {
      debugPrint('[Schedule] 同步失败: $e');
      _lastSyncFailed = true;
      LocalDatabase().setBool(_lastSyncFailedKey, true);
      if (silent) return cachedSchedule;
      throw const ScheduleNetworkException();
    }
  }

  /// 后台静默同步：启动、回前台时调用；失败不打扰用户
  Future<void> syncSilently({bool force = false}) async {
    try {
      await init();
      if (!isAuthenticated) return;
      await refresh(force: force, silent: true);
    } catch (e) {
      debugPrint('[Schedule] 静默同步忽略错误: $e');
    }
  }

  Future<void> _applyRemoteSchedule(
    ScheduleData? old,
    ScheduleData remote,
  ) async {
    final previous = old ?? cachedSchedule;
    final revisionChanged = previous?.revision != remote.revision;
    cachedSchedule = remote;
    LocalDatabase().set(_cacheKey, remote.encode());

    final member = memberId;
    if (member == null || member.isEmpty) {
      if (revisionChanged) await rescheduleNotifications();
      return;
    }

    final ownChanges = _ownChanges(previous, remote, member);
    final lastNotifiedRevision =
        int.tryParse(LocalDatabase().get(_lastNotifiedRevisionKey) ?? '') ?? 0;
    final isFirstSync = previous == null || previous.revision <= 0;
    final hasChanges =
        ownChanges.added.isNotEmpty || ownChanges.removed.isNotEmpty;

    if (!isFirstSync && hasChanges && remote.revision != lastNotifiedRevision) {
      final message = _buildChangeMessage(ownChanges.added, ownChanges.removed);
      _pendingChangeMessage = message;
      LocalDatabase().set(_pendingChangeKey, message);
      changeNotifier.value = message;
      await ScheduleNotificationService.instance.showScheduleChanged(
        added: ownChanges.added,
        removed: ownChanges.removed,
      );
    }

    LocalDatabase().set(_lastNotifiedRevisionKey, remote.revision.toString());
    if (revisionChanged || isFirstSync) {
      await rescheduleNotifications();
    }
  }

  /// 管理员提交。baseRevision 默认取编辑时基于的版本；
  /// 冲突后 UI 可传入最新版本号让管理员确认覆盖。
  Future<ScheduleSubmitResult> submit(
    ScheduleData edited, {
    int? baseRevisionOverride,
  }) async {
    await init();
    if (_token == null || _token!.isEmpty) {
      throw const ScheduleAuthException('登录已失效，请重新输入管理密钥');
    }
    if (!isAdmin) {
      throw const ScheduleAuthException('没有管理员权限', statusCode: 403);
    }

    final baseRevision = baseRevisionOverride ?? edited.revision;
    final result = await _api.submitSchedule(
      _token!,
      edited,
      baseRevision: baseRevision,
      updatedBy: memberName ?? 'admin',
    );

    final previous = cachedSchedule;
    cachedSchedule = result.schedule;
    LocalDatabase().set(_cacheKey, result.schedule.encode());
    LocalDatabase().set(
      _lastNotifiedRevisionKey,
      result.schedule.revision.toString(),
    );
    LocalDatabase().set(_lastSyncAtKey, DateTime.now().toIso8601String());
    LocalDatabase().setBool(_lastSyncFailedKey, false);
    _lastSyncAt = DateTime.now();
    _lastSyncFailed = false;

    final member = memberId;
    if (member != null && member.isNotEmpty) {
      final own = _ownChanges(previous, result.schedule, member);
      if (own.added.isNotEmpty || own.removed.isNotEmpty) {
        final message = _buildChangeMessage(own.added, own.removed);
        _pendingChangeMessage = message;
        LocalDatabase().set(_pendingChangeKey, message);
        changeNotifier.value = message;
        await ScheduleNotificationService.instance.showScheduleChanged(
          added: own.added,
          removed: own.removed,
        );
      }
    }
    await rescheduleNotifications();
    return result;
  }

  /// 当前身份下，某成员的全部未来协管日期
  List<DateTime> myUpcomingDates({DateTime? now}) {
    final member = memberId;
    final schedule = cachedSchedule;
    if (member == null || member.isEmpty || schedule == null) return [];
    return schedule.upcomingDatesForMember(member, now: now);
  }

  /// 今天是否协管
  bool isOnDutyToday() {
    final member = memberId;
    final schedule = cachedSchedule;
    if (member == null || member.isEmpty || schedule == null) return false;
    return schedule.isMemberOnDuty(member, ScheduleDate.today());
  }

  Future<void> rescheduleNotifications() async {
    final schedule = cachedSchedule;
    if (schedule == null) return;
    await ScheduleNotificationService.instance.rescheduleForMember(
      schedule,
      _memberId,
    );
  }

  void clearPendingChangeMessage() {
    _pendingChangeMessage = null;
    changeNotifier.value = null;
    LocalDatabase().remove(_pendingChangeKey);
  }

  /// 配置是否已就绪（用于门禁页提示）
  Future<bool> isServiceConfigured() async {
    final base = await ScheduleConfig.resolveApiBaseUrl();
    return base != null;
  }

  ({List<DateTime> added, List<DateTime> removed}) _ownChanges(
    ScheduleData? old,
    ScheduleData next,
    String member,
  ) {
    final oldKeys =
        old?.datesForMember(member).map(ScheduleDate.key).toSet() ?? <String>{};
    final newKeys = next.datesForMember(member).map(ScheduleDate.key).toSet();
    final added =
        newKeys
            .difference(oldKeys)
            .map(ScheduleDate.tryParseKey)
            .whereType<DateTime>()
            .toList()
          ..sort();
    final removed =
        oldKeys
            .difference(newKeys)
            .map(ScheduleDate.tryParseKey)
            .whereType<DateTime>()
            .toList()
          ..sort();
    return (added: added, removed: removed);
  }

  String _buildChangeMessage(List<DateTime> added, List<DateTime> removed) {
    final parts = <String>[];
    if (added.isNotEmpty) {
      parts.add('新增 ${added.take(5).map(ScheduleDate.shortLabel).join('、')}');
    }
    if (removed.isNotEmpty) {
      parts.add('取消 ${removed.take(5).map(ScheduleDate.shortLabel).join('、')}');
    }
    return '你的协管日期有变更：${parts.join('；')}。';
  }

  Future<String?> _readSecure(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      debugPrint('[Schedule] 安全存储读取失败: $key');
      return null;
    }
  }

  Future<void> _writeSecure(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      debugPrint('[Schedule] 安全存储写入失败: $key');
    }
  }

  Future<void> _deleteSecure(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      debugPrint('[Schedule] 安全存储删除失败: $key');
    }
  }
}
