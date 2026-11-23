import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../data/local_database.dart';
import 'auth_api.dart';
/// 当前登录状态，登录号与昵称持久化到本地，重启 App 后自动恢复
class AuthSession {
  AuthSession({LocalDatabase? database}) : _db = database ?? LocalDatabase();

  static final AuthSession instance = AuthSession();

  static const _idKey = 'auth_user_id';
  static const _loginIdKey = 'auth_login_id';
  static const _nicknameKey = 'auth_nickname';
  static const _avatarKey = 'auth_avatar_path';
  static const _adminKey = 'auth_is_admin';
  static const _tokenKey = 'auth_token';

  final LocalDatabase _db;

  final ValueNotifier<AuthUser?> user = ValueNotifier<AuthUser?>(null);

  bool get isLoggedIn => user.value != null;

  /// 当前账号是否为论坛管理员
  bool get isAdmin => user.value?.isAdmin ?? false;

  /// 当前访问令牌；未登录或旧版登录（无令牌）时为空
  String get token => user.value?.token ?? '';

  /// 从本地恢复上次登录的账号（App 启动时调用一次）
  void restore() {
    if (user.value != null) return;
    final id = int.tryParse(_db.get(_idKey) ?? '');
    final loginId = _db.get(_loginIdKey);
    final nickname = _db.get(_nicknameKey);
    final token = _db.get(_tokenKey) ?? '';
    // v3.10.15 起服务端写操作必须带令牌；旧版本登录留下的记录没有令牌，
    // 直接沿用会让用户「已登录却处处 401」，这里清掉并要求重新登录。
    if (token.isEmpty) {
      if (id != null || loginId != null || nickname != null) {
        signOut();
      }
      return;
    }
    if (id != null &&
        loginId != null &&
        loginId.isNotEmpty &&
        nickname != null &&
        nickname.isNotEmpty) {
      user.value = AuthUser(
        id: id,
        loginId: loginId,
        nickname: nickname,
        avatarPath: _db.get(_avatarKey),
        isAdmin: _db.getBool(_adminKey),
        token: token,
      );
    }
  }

  /// 昵称修改历史按账号保存，用于把论坛里旧的昵称显示为当前昵称
  static String _historyKey(int id) => 'auth_nickname_history_$id';

  void _rememberNickname(int id, String nickname) {
    if (nickname.isEmpty) return;
    final names = _historyNamesOf(id)..add(nickname);
    _db.set(_historyKey(id), jsonEncode(names.toList()));
  }

  Set<String> _historyNamesOf(int id) {
    final raw = _db.get(_historyKey(id));
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      return Set<String>.from(jsonDecode(raw) as List);
    } catch (_) {
      return <String>{};
    }
  }

  /// 当前账号用过的全部昵称（含当前昵称）
  Set<String> get myNicknames {
    final me = user.value;
    if (me == null) return <String>{};
    return {..._historyNamesOf(me.id), me.nickname};
  }

  /// 判断论坛里的作者名是否属于当前账号（仅用于昵称展示映射）
  bool isSelf(String author) => myNicknames.contains(author);

  /// 删除权限判断：只认账号 id，昵称相同不代表是本人
  bool isMyUserId(String? authorId) {
    final me = user.value;
    if (me == null || authorId == null) return false;
    return authorId == '${me.id}';
  }

  /// 把论坛里展示的作者名映射为当前昵称
  String displayName(String author) =>
      isSelf(author) ? user.value!.nickname : author;

  void signIn(AuthUser account) {
    final current = user.value;
    if (current != null &&
        current.id == account.id &&
        current.nickname != account.nickname) {
      _rememberNickname(current.id, current.nickname);
    }
    user.value = account;
    _db.set(_idKey, '${account.id}');
    _db.set(_loginIdKey, account.loginId);
    _db.set(_nicknameKey, account.nickname);
    _db.setBool(_adminKey, account.isAdmin);
    if (account.token.isEmpty) {
      _db.remove(_tokenKey);
    } else {
      _db.set(_tokenKey, account.token);
    }
    final avatar = account.avatarPath;
    if (avatar == null || avatar.isEmpty) {
      _db.remove(_avatarKey);
    } else {
      _db.set(_avatarKey, avatar);
    }
  }

  /// 修改昵称与头像（本地保存，重启 App 后仍然生效）
  void updateProfile({required String nickname, String? avatarPath}) {
    final current = user.value;
    if (current == null) return;
    if (current.nickname.isNotEmpty && current.nickname != nickname) {
      _rememberNickname(current.id, current.nickname);
    }
    user.value = current.copyWith(
      nickname: nickname,
      avatarPath: avatarPath,
      clearAvatar: avatarPath == null || avatarPath.isEmpty,
    );
    _db.set(_nicknameKey, nickname);
    if (avatarPath == null || avatarPath.isEmpty) {
      _db.remove(_avatarKey);
    } else {
      _db.set(_avatarKey, avatarPath);
    }
  }

  void signOut() {
    user.value = null;
    _db.remove(_idKey);
    _db.remove(_loginIdKey);
    _db.remove(_nicknameKey);
    _db.remove(_avatarKey);
    _db.remove(_adminKey);
    _db.remove(_tokenKey);
  }
}
