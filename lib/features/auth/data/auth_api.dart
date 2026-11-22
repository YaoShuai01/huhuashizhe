import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// 登录用户：登录号由服务端自动生成，昵称只用于展示
class AuthUser {
  const AuthUser({
    required this.id,
    required this.loginId,
    required this.nickname,
  });

  final int id;

  /// 8 位数字登录号，登录时使用
  final String loginId;

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
  /// 设置密码并注册，返回系统分配的登录号
  Future<AuthUser> register({
    required String nickname,
    required String password,
  });

  /// 用登录号 + 密码登录
  Future<AuthUser> login({
    required String loginId,
    required String password,
  });
}

/// 默认后端地址：
/// - 优先取 --dart-define=FORUM_API_BASE=http://电脑IP:3000
/// - Android 模拟器用 10.0.2.2 访问电脑本机
/// - 其他平台（Windows / Web）直接用 127.0.0.1
const String _envForumApiBase = String.fromEnvironment('FORUM_API_BASE');

String get defaultForumApiBase {
  if (_envForumApiBase.isNotEmpty) return _envForumApiBase;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:3000';
  }
  return 'http://127.0.0.1:3000';
}

class DioAuthApi implements AuthApi {
  DioAuthApi({Dio? dio, String? baseUrl})
      : _baseUrl = baseUrl ?? defaultForumApiBase,
        _dio = dio ?? _createDio(baseUrl ?? defaultForumApiBase);

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
      _post('/api/auth/register', {
        'nickname': nickname,
        'password': password,
      });

  @override
  Future<AuthUser> login({
    required String loginId,
    required String password,
  }) =>
      _post('/api/auth/login', {
        'loginId': loginId,
        'password': password,
      });

  Future<AuthUser> _post(String path, Map<String, dynamic> body) async {
    try {
      final response =
          await _dio.post<Map<String, dynamic>>(path, data: body);
      final data = response.data ?? const {};
      return AuthUser(
        id: (data['id'] as num).toInt(),
        loginId: data['loginId'] as String,
        nickname: data['nickname'] as String,
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
