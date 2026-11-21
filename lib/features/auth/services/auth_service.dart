import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../../data/local_database.dart';

/// 本地演示账号（用户名+密码，数据仅存本机）
class UserModel {
  const UserModel({
    required this.username,
    required this.nickname,
    required this.createdAt,
  });

  final String username;
  final String nickname;
  final DateTime createdAt;

  factory UserModel.fromMap(Map<String, dynamic> map) => UserModel(
        username: map['username'] as String,
        nickname: map['nickname'] as String? ?? map['username'] as String,
        createdAt:
            DateTime.tryParse(map['createdAt'] as String? ?? '') ??
                DateTime.now(),
      );

  Map<String, dynamic> toMap() => <String, dynamic>{
        'username': username,
        'nickname': nickname,
        'createdAt': createdAt.toIso8601String(),
      };
}

/// 本地账号服务：注册/登录/登出，全部落在本机 LocalDatabase。
///
/// 演示定位：无服务器、无云端同步，卸载 App 即清空。
/// 密码以"随机盐 + SHA-256"哈希存储，任何情况下不落明文。
class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  static const _usersKey = 'auth_users';
  static const _sessionKey = 'auth_session';

  final LocalDatabase _db = LocalDatabase();

  // ==================== 查询 ====================

  /// 当前登录用户；未登录返回 null
  UserModel? get currentUser {
    final username = _db.get(_sessionKey);
    if (username == null || username.isEmpty) return null;
    for (final u in _users()) {
      if (u['username'] == username) {
        return UserModel.fromMap(u);
      }
    }
    return null;
  }

  bool get isLoggedIn => currentUser != null;

  List<Map<String, dynamic>> _users() {
    final json = _db.get(_usersKey);
    if (json == null || json.isEmpty) return <Map<String, dynamic>>[];
    final raw = jsonDecode(json) as List<dynamic>;
    return raw.cast<Map<String, dynamic>>();
  }

  void _saveUsers(List<Map<String, dynamic>> users) {
    _db.set(_usersKey, jsonEncode(users));
  }

  // ==================== 注册 ====================

  /// 注册并自动登录。返回 null 表示成功，否则为错误提示文案。
  String? register({
    required String username,
    required String password,
    required String confirm,
    String? nickname,
  }) {
    final name = username.trim();
    if (name.length < 2 || name.length > 20) {
      return '用户名长度需在 2-20 个字符之间';
    }
    if (name.contains(RegExp(r'\s'))) {
      return '用户名不能包含空格';
    }
    final pwdError = _checkPassword(password, confirm);
    if (pwdError != null) return pwdError;

    final users = _users();
    for (final u in users) {
      if (u['username'] == name) return '该用户名已被注册';
    }

    final salt = _randomSalt();
    users.add(<String, dynamic>{
      'username': name,
      'nickname': (nickname?.trim().isNotEmpty ?? false)
          ? nickname!.trim()
          : name,
      'salt': salt,
      'hash': _hash(salt, password),
      'createdAt': DateTime.now().toIso8601String(),
    });
    _saveUsers(users);
    _db.set(_sessionKey, name);
    return null;
  }

  // ==================== 登录/登出 ====================

  /// 登录。返回 null 表示成功，否则为错误提示文案。
  String? login({required String username, required String password}) {
    final name = username.trim();
    if (name.isEmpty || password.isEmpty) return '请填写用户名和密码';
    for (final u in _users()) {
      if (u['username'] == name) {
        if (u['hash'] != _hash(u['salt'] as String, password)) {
          return '密码错误，请重试';
        }
        _db.set(_sessionKey, name);
        return null;
      }
    }
    return '用户不存在，请先注册';
  }

  void logout() {
    _db.remove(_sessionKey);
  }

  // ==================== 资料 ====================

  /// 修改当前用户昵称。返回 null 表示成功。
  String? updateNickname(String nickname) {
    final user = currentUser;
    if (user == null) return '未登录';
    final name = nickname.trim();
    if (name.isEmpty || name.length > 20) return '昵称需为 1-20 个字符';
    final users = _users();
    for (final u in users) {
      if (u['username'] == user.username) u['nickname'] = name;
    }
    _saveUsers(users);
    return null;
  }

  // ==================== 内部工具 ====================

  String? _checkPassword(String password, String confirm) {
    if (password.length < 6) return '密码至少 6 位';
    if (password != confirm) return '两次输入的密码不一致';
    return null;
  }

  String _randomSalt() {
    final rnd = Random.secure();
    return List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
  }

  String _hash(String salt, String password) {
    return sha256.convert(utf8.encode('$salt:$password')).toString();
  }

  /// 测试专用：清空内存中的账号与会话（不影响磁盘）
  void resetForTest() {
    _db.remove(_usersKey);
    _db.remove(_sessionKey);
  }
}
