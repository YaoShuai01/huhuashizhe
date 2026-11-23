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

  final LocalDatabase _db;

  final ValueNotifier<AuthUser?> user = ValueNotifier<AuthUser?>(null);

  bool get isLoggedIn => user.value != null;

  /// 从本地恢复上次登录的账号（App 启动时调用一次）
  void restore() {
    if (user.value != null) return;
    final id = int.tryParse(_db.get(_idKey) ?? '');
    final loginId = _db.get(_loginIdKey);
    final nickname = _db.get(_nicknameKey);
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
      );
    }
  }

  void signIn(AuthUser account) {
    user.value = account;
    _db.set(_idKey, '${account.id}');
    _db.set(_loginIdKey, account.loginId);
    _db.set(_nicknameKey, account.nickname);
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
  }
}
