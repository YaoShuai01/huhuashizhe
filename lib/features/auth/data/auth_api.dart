import 'package:dio/dio.dart';

/// 登录用户
class AuthUser {
  const AuthUser({required this.id, required this.nickname});

  final int id;
  final String nickname;
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
  Future<AuthUser> register({
    required String nickname,
    required String password,
  });

  Future<AuthUser> login({
    required String nickname,
    required String password,
  });
}

/// 默认后端地址：Android 模拟器用 10.0.2.2 指向电脑本机
/// 真机调试时用 --dart-define=FORUM_API_BASE=http://电脑局域网IP:3000 覆盖
const String defaultForumApiBase = String.fromEnvironment(
  'FORUM_API_BASE',
  defaultValue: 'http://10.0.2.2:3000',
);

class DioAuthApi implements AuthApi {
  DioAuthApi({Dio? dio, String baseUrl = defaultForumApiBase})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl,
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 8),
              ),
            );

  final Dio _dio;

  @override
  Future<AuthUser> register({
    required String nickname,
    required String password,
  }) =>
      _post('/api/auth/register', nickname, password);

  @override
  Future<AuthUser> login({
    required String nickname,
    required String password,
  }) =>
      _post('/api/auth/login', nickname, password);

  Future<AuthUser> _post(String path, String nickname, String password) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        path,
        // 参数化交给后端处理，这里只负责 JSON 传输
        data: {'nickname': nickname, 'password': password},
      );
      final data = response.data ?? const {};
      return AuthUser(
        id: (data['id'] as num).toInt(),
        nickname: data['nickname'] as String,
      );
    } on DioException catch (error) {
      final data = error.response?.data;
      final message = data is Map && data['error'] is String
          ? data['error'] as String
          : '网络异常，请检查网络后重试';
      throw AuthException(message);
    }
  }
}
