import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/local_database.dart';
import '../features/schedule/models/schedule_models.dart';
import 'schedule_api.dart';
import 'schedule_service.dart';

/// 轮协匿名留言池：本地缓存、未读计数与增删操作
class ScheduleMessageService {
  ScheduleMessageService._();
  static final ScheduleMessageService instance = ScheduleMessageService._();

  static const String _anonKey = 'schedule_message_anon_id';
  static const String _cacheKey = 'schedule_messages_cache';
  static const String _seenKey = 'schedule_messages_seen_at';

  final ScheduleApi _api = ScheduleApi();

  /// 未读回复数，页面可监听这个值刷新角标
  final ValueNotifier<int> unreadNotifier = ValueNotifier<int>(0);

  List<ScheduleMessage> _messages = [];
  String? _anonId;
  bool _initialized = false;
  bool _online = true;
  String? _error;

  List<ScheduleMessage> get messages => _messages;
  bool get isOnline => _online;
  String? get error => _error;
  int get unread => unreadNotifier.value;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _anonId = LocalDatabase().get(_anonKey);
    if (_anonId == null || _anonId!.isEmpty) {
      _anonId = _generateAnonId();
      LocalDatabase().set(_anonKey, _anonId!);
    }
    final raw = LocalDatabase().get(_cacheKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _messages =
              decoded
                  .whereType<Map>()
                  .map(
                    (e) =>
                        ScheduleMessage.fromJson(Map<String, dynamic>.from(e)),
                  )
                  .toList();
        }
      } catch (e) {
        debugPrint('[ScheduleMessage] 缓存解析失败: $e');
      }
    }
    _recomputeUnread();
  }

  /// 拉取留言池；silent 模式下网络失败不抛出，仅标记离线
  Future<void> refresh({bool silent = false}) async {
    await init();
    final token = ScheduleService.instance.authToken;
    if (token == null || token.isEmpty) {
      if (!silent) {
        throw const ScheduleAuthException('请先输入轮协密钥', code: 'no_token');
      }
      return;
    }
    try {
      _apply(await _api.fetchMessages(token, _anonId!));
      _online = true;
      _error = null;
    } on ScheduleAuthException {
      if (!silent) rethrow;
    } on ScheduleApiException {
      _online = false;
      _error = '服务器未启动，暂时无法添加留言；当前显示本地缓存。';
    } catch (e) {
      debugPrint('[ScheduleMessage] 拉取失败: $e');
      _online = false;
      _error = '服务器未启动，暂时无法添加留言；当前显示本地缓存。';
    }
  }

  Future<void> postMessage(String content) async {
    await init();
    final token = _requireToken();
    try {
      _apply(await _api.postMessage(token, _anonId!, content));
      _online = true;
      _error = null;
    } on ScheduleApiException {
      _markOffline();
      rethrow;
    }
  }

  Future<void> postReply(String messageId, String content) async {
    await init();
    final token = _requireToken();
    try {
      _apply(await _api.postMessageReply(token, messageId, _anonId!, content));
      _online = true;
      _error = null;
    } on ScheduleApiException {
      _markOffline();
      rethrow;
    }
  }

  Future<void> deleteMessage(String messageId) async {
    await init();
    final token = _requireToken();
    try {
      _apply(await _api.deleteMessage(token, messageId, _anonId!));
      _online = true;
      _error = null;
    } on ScheduleApiException {
      _markOffline();
      rethrow;
    }
  }

  Future<void> deleteReply(String replyId) async {
    await init();
    final token = _requireToken();
    try {
      _apply(await _api.deleteMessageReply(token, replyId, _anonId!));
      _online = true;
      _error = null;
    } on ScheduleApiException {
      _markOffline();
      rethrow;
    }
  }

  /// 进入留言池时调用，清空未读角标
  void markSeen() {
    LocalDatabase().set(_seenKey, DateTime.now().toUtc().toIso8601String());
    unreadNotifier.value = 0;
  }

  String _requireToken() {
    final token = ScheduleService.instance.authToken;
    if (token == null || token.isEmpty) {
      throw const ScheduleAuthException('登录已失效，请重新输入轮协密钥', code: 'no_token');
    }
    return token;
  }

  void _markOffline() {
    _online = false;
    _error = '服务器未启动，暂时无法添加留言；当前显示本地缓存。';
  }

  void _apply(List<ScheduleMessage> messages) {
    _messages = messages;
    LocalDatabase().set(
      _cacheKey,
      jsonEncode(messages.map((e) => e.toJson()).toList()),
    );
    _recomputeUnread();
  }

  void _recomputeUnread() {
    final seen = DateTime.tryParse(LocalDatabase().get(_seenKey) ?? '');
    if (seen == null) {
      markSeen();
      return;
    }
    var count = 0;
    for (final message in _messages) {
      if (!message.isMine) continue;
      for (final reply in message.replies) {
        if (reply.isMine) continue;
        final at = DateTime.tryParse(reply.createdAt);
        if (at != null && at.isAfter(seen)) count++;
      }
    }
    unreadNotifier.value = count;
  }

  String _generateAnonId() {
    final random = math.Random.secure();
    final buffer = StringBuffer('app_');
    for (var i = 0; i < 16; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
