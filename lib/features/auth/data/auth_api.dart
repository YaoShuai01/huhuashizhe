import 'package:dio/dio.dart';

/// 登录用户：登录号由服务端自动生成，昵称与头像用于展示
class AuthUser {
  const AuthUser({
    required this.id,
    required this.loginId,
    required this.nickname,
    this.avatarPath,
    this.isAdmin = false,
  });

  final int id;

  /// 8 位数字登录号，登录时使用
  final String loginId;

  final String nickname;

  /// 本地头像文件路径，未设置时为空
  final String? avatarPath;

  /// 论坛管理员可删除任意帖子与评论
  final bool isAdmin;

  AuthUser copyWith({
    String? nickname,
    String? avatarPath,
    bool clearAvatar = false,
  }) {
    return AuthUser(
      id: id,
      loginId: loginId,
      nickname: nickname ?? this.nickname,
      avatarPath: clearAvatar ? null : (avatarPath ?? this.avatarPath),
      isAdmin: isAdmin,
    );
  }
}

/// 登录/注册失败，message 可直接展示给用户
class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 账号接口，便于测试时注入假实现
abstract class AuthApi {
  /// 设置密码并注册，返回系统分配的登录号
  Future<AuthUser> register({
    required String nickname,
    required String password,
  });

  /// 用登录号 + 密码登录
  Future<AuthUser> login({required String loginId, required String password});

  /// 同步昵称到服务端，论坛里的历史帖子与评论会随 users.nickname 一起更新
  Future<void> updateNickname({required int userId, required String nickname});
}

/// 默认后端地址：直接使用已部署的云服务器，手机任意网络都能访问，无需同一 Wi-Fi。
/// 本地联调时可用 --dart-define=FORUM_API_BASE=http://电脑IP:3000 覆盖。
const String _envForumApiBase = String.fromEnvironment('FORUM_API_BASE');

/// 公网后端：Tomcat 8080 的 /forum 反向代理到论坛服务 3000
const String _publicForumApiBase = 'http://121.199.75.235:8080/forum';

String get defaultForumApiBase =>
    _envForumApiBase.isNotEmpty ? _envForumApiBase : _publicForumApiBase;

class DioAuthApi implements AuthApi {
  DioAuthApi({Dio? dio, String? baseUrl})
    : _baseUrl = _normalizeBase(baseUrl ?? defaultForumApiBase),
      _dio = dio ?? _createDio(baseUrl ?? defaultForumApiBase);

  /// 去掉末尾斜杠，避免拼接出双斜杠地址
  static String _normalizeBase(String base) =>
      base.endsWith('/') ? base.substring(0, base.length - 1) : base;

  static Dio _createDio(String baseUrl) => Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );

  final String _baseUrl;
  final Dio _dio;

  @override
  Future<AuthUser> register({
    required String nickname,
    required String password,
  }) =>
      _post('/api/auth/register', {'nickname': nickname, 'password': password});

  @override
  Future<AuthUser> login({required String loginId, required String password}) =>
      _post('/api/auth/login', {'loginId': loginId, 'password': password});

  @override
  Future<void> updateNickname({
    required int userId,
    required String nickname,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/api/auth/profile',
        data: {'userId': userId, 'nickname': nickname},
      );
    } on DioException catch (error) {
      final data = error.response?.data;
      if (data is Map && data['error'] is String) {
        throw AuthException(data['error'] as String);
      }
      throw const AuthException('网络异常，昵称暂未同步到论坛');
    }
  }

  Future<AuthUser> _post(String path, Map<String, dynamic> body) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(path, data: body);
      final data = response.data ?? const {};
      return AuthUser(
        id: (data['id'] as num).toInt(),
        loginId: data['loginId'] as String,
        nickname: data['nickname'] as String,
        isAdmin: data['isAdmin'] == true,
      );
    } on DioException catch (error) {
      final data = error.response?.data;
      if (data is Map && data['error'] is String) {
        throw AuthException(data['error'] as String);
      }
      if (error.response == null) {
        throw AuthException('连不上后端（$_baseUrl），请确认服务已启动');
      }
      throw AuthException('网络异常，请检查网络后重试');
    }
  }
}
