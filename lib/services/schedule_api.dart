import 'package:dio/dio.dart';

import '../core/constants/schedule_config.dart';
import '../features/schedule/models/schedule_models.dart';

/// 轮协 API 异常基类
class ScheduleApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? code;

  const ScheduleApiException(this.message, {this.statusCode, this.code});

  @override
  String toString() => message;
}

class ScheduleNotConfiguredException extends ScheduleApiException {
  const ScheduleNotConfiguredException() : super('轮协服务暂未配置，请管理员先部署 Worker');
}

class ScheduleAuthException extends ScheduleApiException {
  const ScheduleAuthException(super.message, {super.statusCode, super.code});
}

class ScheduleConflictException extends ScheduleApiException {
  final int currentRevision;
  final ScheduleData? remoteSchedule;

  const ScheduleConflictException(
    super.message, {
    required this.currentRevision,
    this.remoteSchedule,
  }) : super(statusCode: 409, code: 'conflict');
}

class ScheduleNetworkException extends ScheduleApiException {
  const ScheduleNetworkException([super.message = '网络连接失败，请检查网络后重试']);
}

/// 轮协 Worker HTTP 客户端
class ScheduleApi {
  String? _baseUrl;

  ScheduleApi({String? baseUrl}) : _baseUrl = baseUrl;

  Future<Dio> _client() async {
    final base = _baseUrl ?? await ScheduleConfig.resolveApiBaseUrl();
    if (base == null) {
      throw const ScheduleNotConfiguredException();
    }
    _baseUrl = base;
    return Dio(
      BaseOptions(
        baseUrl: base,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        responseType: ResponseType.json,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        // 4xx 也交给业务层处理，便于区分密钥错误 / 冲突 / 限流
        validateStatus: (status) => status != null,
      ),
    );
  }

  /// 用轮协密钥或管理员密钥换取 token
  Future<ScheduleAuthResult> authenticate(String key) async {
    final dio = await _client();
    try {
      final response = await dio.post<dynamic>('/auth', data: {'key': key});
      final status = response.statusCode ?? 0;
      if (status == 200 && response.data is Map) {
        return ScheduleAuthResult.fromJson(
          Map<String, dynamic>.from(response.data as Map),
        );
      }
      final message = _messageFrom(response, '轮协密钥验证失败');
      if (status == 401 || status == 400) {
        throw ScheduleAuthException(message, statusCode: status);
      }
      if (status == 429) {
        throw ScheduleAuthException(
          message,
          statusCode: status,
          code: 'rate_limited',
        );
      }
      throw ScheduleApiException(message, statusCode: status);
    } on DioException catch (e) {
      throw ScheduleNetworkException(_dioMessage(e));
    }
  }

  /// 读取轮协表
  Future<ScheduleData> fetchSchedule(String token) async {
    final dio = await _client();
    try {
      final response = await dio.get<dynamic>(
        '/schedule',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final status = response.statusCode ?? 0;
      if (status == 200 && response.data is Map) {
        final map = Map<String, dynamic>.from(response.data as Map);
        final schedule = map['schedule'];
        if (schedule is Map) {
          return ScheduleData.fromJson(Map<String, dynamic>.from(schedule));
        }
        throw const ScheduleApiException('轮协数据格式错误');
      }
      final message = _messageFrom(response, '轮协数据读取失败');
      if (status == 401) {
        throw ScheduleAuthException(
          message,
          statusCode: status,
          code: 'unauthorized',
        );
      }
      throw ScheduleApiException(message, statusCode: status);
    } on DioException catch (e) {
      throw ScheduleNetworkException(_dioMessage(e));
    }
  }

  /// 管理员提交轮协
  Future<ScheduleSubmitResult> submitSchedule(
    String token,
    ScheduleData data, {
    required int baseRevision,
    required String updatedBy,
  }) async {
    final dio = await _client();
    try {
      final response = await dio.put<dynamic>(
        '/schedule',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
        data: {
          'baseRevision': baseRevision,
          'members': data.members.map((m) => m.toJson()).toList(),
          'assignments': data.assignments,
          'rotation': data.rotation,
          'updatedBy': updatedBy,
        },
      );
      final status = response.statusCode ?? 0;
      if (status == 200 && response.data is Map) {
        return ScheduleSubmitResult.fromJson(
          Map<String, dynamic>.from(response.data as Map),
        );
      }
      final map =
          response.data is Map
              ? Map<String, dynamic>.from(response.data as Map)
              : const <String, dynamic>{};
      final message = _messageFrom(response, '轮协提交失败');
      if (status == 409) {
        final currentRevision = (map['currentRevision'] as num?)?.toInt() ?? -1;
        final remote = map['schedule'];
        throw ScheduleConflictException(
          message,
          currentRevision: currentRevision,
          remoteSchedule:
              remote is Map
                  ? ScheduleData.fromJson(Map<String, dynamic>.from(remote))
                  : null,
        );
      }
      if (status == 401 || status == 403) {
        throw ScheduleAuthException(message, statusCode: status);
      }
      throw ScheduleApiException(message, statusCode: status);
    } on DioException catch (e) {
      throw ScheduleNetworkException(_dioMessage(e));
    }
  }

  /// 读取匿名留言池
  Future<List<ScheduleMessage>> fetchMessages(String token, String anonId) {
    return _messagesRequest(
      token,
      (dio) =>
          dio.get<dynamic>('/messages', queryParameters: {'anonId': anonId}),
      '留言读取失败',
    );
  }

  /// 发布留言
  Future<List<ScheduleMessage>> postMessage(
    String token,
    String anonId,
    String content,
  ) {
    return _messagesRequest(
      token,
      (dio) => dio.post<dynamic>(
        '/messages',
        data: {'anonId': anonId, 'content': content},
      ),
      '留言发布失败',
    );
  }

  /// 回复留言
  Future<List<ScheduleMessage>> postMessageReply(
    String token,
    String messageId,
    String anonId,
    String content,
  ) {
    return _messagesRequest(
      token,
      (dio) => dio.post<dynamic>(
        '/messages/${Uri.encodeComponent(messageId)}/replies',
        data: {'anonId': anonId, 'content': content},
      ),
      '回复发布失败',
    );
  }

  /// 删除留言（本人或管理员）
  Future<List<ScheduleMessage>> deleteMessage(
    String token,
    String messageId,
    String anonId,
  ) {
    return _messagesRequest(
      token,
      (dio) => dio.delete<dynamic>(
        '/messages/${Uri.encodeComponent(messageId)}',
        queryParameters: {'anonId': anonId},
      ),
      '删除失败',
    );
  }

  /// 删除回复（本人或管理员）
  Future<List<ScheduleMessage>> deleteMessageReply(
    String token,
    String replyId,
    String anonId,
  ) {
    return _messagesRequest(
      token,
      (dio) => dio.delete<dynamic>(
        '/replies/${Uri.encodeComponent(replyId)}',
        queryParameters: {'anonId': anonId},
      ),
      '删除失败',
    );
  }

  Future<List<ScheduleMessage>> _messagesRequest(
    String token,
    Future<Response<dynamic>> Function(Dio dio) request,
    String fallback,
  ) async {
    final dio = await _client();
    dio.options.headers['Authorization'] = 'Bearer $token';
    try {
      final response = await request(dio);
      final status = response.statusCode ?? 0;
      if (status == 200 && response.data is Map) {
        final map = Map<String, dynamic>.from(response.data as Map);
        return (map['messages'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ScheduleMessage.fromJson)
            .toList();
      }
      final message = _messageFrom(response, fallback);
      if (status == 401) {
        throw ScheduleAuthException(
          message,
          statusCode: status,
          code: 'unauthorized',
        );
      }
      throw ScheduleApiException(message, statusCode: status);
    } on DioException catch (e) {
      throw ScheduleNetworkException(_dioMessage(e));
    }
  }

  String _messageFrom(Response<dynamic> response, String fallback) {
    final data = response.data;
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) return message;
    }
    return fallback;
  }

  String _dioMessage(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '网络超时，请稍后重试';
      case DioExceptionType.connectionError:
        return '无法连接轮协服务，请检查网络';
      case DioExceptionType.badCertificate:
        return '轮协服务证书异常';
      case DioExceptionType.cancel:
        return '请求已取消';
      case DioExceptionType.badResponse:
        return '轮协服务异常（${error.response?.statusCode ?? '未知'}）';
      case DioExceptionType.transformTimeout:
        return '数据处理超时，请稍后重试';
      case DioExceptionType.unknown:
        return '网络连接失败，请检查网络后重试';
    }
  }
}
