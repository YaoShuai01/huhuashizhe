import 'package:flutter/foundation.dart';

import '../../../data/local_database.dart';
import 'auth_api.dart';

/// 当前登录状态，昵称与 id 持久化到本地，重启 App 后自动恢复
class AuthSession {
  AuthSession({LocalDatabase? database}) : _db = database ?? LocalDatabase();

  static final AuthSession instance = AuthSession();

  static const _idKey = 'auth_user_id';
  static const _nicknameKey = 'auth_nickname';

  final LocalDatabase _db;

  final ValueNotifier<AuthUser?> user = ValueNotifier<AuthUser?>(null);

  bool get isLoggedIn => user.value != null;

  /// 从本地恢复上次登录的账号（App 启动时调用一次）
  void restore() {
    if (user.value != null) return;
    final id = int.tryParse(_db.get(_idKey) ?? '');
    final nickname = _db.get(_nicknameKey);
    if (id != null && nickname != null && nickname.isNotEmpty) {
      user.value = AuthUser(id: id, nickname: nickname);
    }
  }

  void signIn(AuthUser account) {
    user.value = account;
    _db.set(_idKey, '${account.id}');
    _db.set(_nicknameKey, account.nickname);
  }

  void signOut() {
    user.value = null;
    _db.remove(_idKey);
    _db.remove(_nicknameKey);
  }
}
