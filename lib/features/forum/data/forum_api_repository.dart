import 'package:dio/dio.dart';

import '../../auth/data/auth_api.dart';
import '../../auth/data/auth_session.dart';
import 'forum_models.dart';
import 'forum_repository.dart';

/// 对接论坛后端的实现：帖子与评论保存在服务器，登录用户之间互相可见。
///
/// 点赞、收藏、消息仍沿用本地内存逻辑。
class ForumApiRepository extends InMemoryForumRepository {
  ForumApiRepository({Dio? dio, String? baseUrl})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: _normalizeBase(baseUrl ?? defaultForumApiBase),
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 8),
              ),
            ),
        super(seed: false);

  final Dio _dio;

  static String _normalizeBase(String base) =>
      base.endsWith('/') ? base.substring(0, base.length - 1) : base;

  /// 拉取全部帖子，替换本地缓存
  @override
  Future<void> refresh() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/posts',
        queryParameters: {'limit': 100},
      );
      final items = response.data?['items'];
      if (items is! List) return;
      replacePosts(
        items.map((item) => _postFromJson(item as Map<String, dynamic>)),
      );
    } on DioException catch (error) {
      throw ForumException(_errorMessage(error));
    }
  }

  @override
  Future<void> loadComments(String postId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/posts/$postId/replies',
      );
      final items = response.data?['items'];
      if (items is! List) return;
      replaceComments(
        postId,
        items.map((item) => _commentFromJson(item as Map<String, dynamic>)),
      );
    } on DioException catch (error) {
      throw ForumException(_errorMessage(error));
    }
  }

  @override
  Future<ForumPost> publish({
    required String section,
    required String title,
    required String content,
    bool pendingReview = false,
  }) async {
    final me = _requireUser();
    final data = await _post('/api/posts', {
      'userId': me.id,
      'section': section,
      'title': title.trim(),
      'content': content.trim(),
    });
    final post = _postFromJson(data);
    replacePosts([post, ...cachedPosts.where((item) => item.id != post.id)]);
    return post;
  }

  @override
  Future<ForumComment> addComment({
    required ForumPost post,
    required String content,
  }) async {
    final me = _requireUser();
    final data = await _post('/api/posts/${post.id}/replies', {
      'userId': me.id,
      'content': content.trim(),
    });
    final comment = _commentFromJson(data);
    replaceComments(post.id, [...commentsOf(post.id), comment]);
    return comment;
  }

  /// 我的帖子：按当前登录昵称匹配
  @override
  List<ForumPost> get myPosts {
    final me = AuthSession.instance.user.value;
    if (me == null) return const [];
    final list =
        cachedPosts.where((post) => post.author == me.nickname).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  AuthUser _requireUser() {
    final me = AuthSession.instance.user.value;
    if (me == null) throw const ForumException('请先登录后再操作');
    return me;
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(path, data: body);
      return response.data ?? const {};
    } on DioException catch (error) {
      throw ForumException(_errorMessage(error));
    }
  }

  String _errorMessage(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['error'] is String) {
      return data['error'] as String;
    }
    return '网络异常，请检查网络后重试';
  }

  ForumPost _postFromJson(Map<String, dynamic> json) => ForumPost(
        id: '${json['id']}',
        section: json['section'] as String? ?? '',
        title: json['title'] as String? ?? '',
        content: json['content'] as String? ?? '',
        author: json['author'] as String? ?? '农友',
        createdAt: _parseTime(json['created_at']),
        likes: (json['likes'] as num?)?.toInt() ?? 0,
      );

  ForumComment _commentFromJson(Map<String, dynamic> json) => ForumComment(
        id: '${json['id']}',
        postId: '${json['post_id']}',
        author: json['author'] as String? ?? '农友',
        content: json['content'] as String? ?? '',
        createdAt: _parseTime(json['created_at']),
      );

  DateTime _parseTime(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();
}

/// App 默认论坛数据源：所有登录用户共享服务器数据
final ForumApiRepository defaultForumApiRepository = ForumApiRepository();
