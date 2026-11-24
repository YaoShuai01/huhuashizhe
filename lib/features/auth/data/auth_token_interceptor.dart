import 'package:dio/dio.dart';

/// 论坛 / AI 令牌注入：所有请求自动带上 `Authorization: Bearer <token>`。
///
/// 服务端已不再信任请求体里的 userId，写操作必须靠令牌认人；
/// 登录、退出等账号状态变化由 [tokenProvider] 实时读取，无需重建 Dio。
class AuthTokenInterceptor extends Interceptor {
  AuthTokenInterceptor(this.tokenProvider);

  /// 返回当前令牌，未登录时返回空字符串
  final String? Function() tokenProvider;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = tokenProvider();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    } else {
      options.headers.remove('Authorization');
    }
    handler.next(options);
  }
}
