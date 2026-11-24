import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../auth/data/auth_api.dart';
import '../../auth/data/auth_session.dart';
import '../../auth/data/auth_token_interceptor.dart';
import 'forum_models.dart';
import 'forum_repository.dart';

/// 对接论坛后端的实现：帖子、评论、点赞、收藏与消息提醒都保存在服务器。
class ForumApiRepository extends InMemoryForumRepository {
  ForumApiRepository({Dio? dio, String? baseUrl})
    : _dio =
          dio ??
          (Dio(
            BaseOptions(
              baseUrl: _normalizeBase(baseUrl ?? defaultForumApiBase),
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
            ),
          )..interceptors.add(
            AuthTokenInterceptor(() => AuthSession.instance.token),
          )),
      super(seed: false) {
    // 登录 / 退出后同步私有数据（消息、点赞、收藏），避免不同账号串号
    AuthSession.instance.user.addListener(_onAccountChanged);
  }

  final Dio _dio;

  /// 账号变化：登录后立即拉取，退出后清空本账号维度的缓存
  void _onAccountChanged() {
    final me = AuthSession.instance.user.value;
    if (me == null) {
      likedIds.clear();
      favoriteIds.clear();
      replaceMessages(<ForumMessage>[]);
      return;
    }
    refresh().catchError((_) {});
  }

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
      final posts = <ForumPost>[];
      final liked = <String>{};
      final favorited = <String>{};
      for (final item in items) {
        final json = item as Map<String, dynamic>;
        final post = _postFromJson(json);
        posts.add(post);
        if (json['liked'] == true) liked.add(post.id);
        if (json['favorited'] == true) favorited.add(post.id);
      }
      likedIds
        ..clear()
        ..addAll(liked);
      favoriteIds
        ..clear()
        ..addAll(favorited);
      replacePosts(posts);
    } on DioException catch (error) {
      throw ForumException(_errorMessage(error));
    }
    // 帖子刷新后顺带同步消息提醒，失败不影响帖子展示
    try {
      await loadMessages();
    } on ForumException {
      // 忽略消息拉取失败，下次轮询会重试
    }
  }

  @override
  bool get supportsRealtimeMessages => true;

  @override
  Future<void> loadMessages() async {
    final me = AuthSession.instance.user.value;
    if (me == null) return;
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/messages',
        queryParameters: {'limit': 100},
      );
      final items = response.data?['items'];
      if (items is! List) return;
      replaceMessages(
        items.map((item) => _messageFromJson(item as Map<String, dynamic>)),
      );
    } on DioException catch (error) {
      throw ForumException(_errorMessage(error));
    }
  }

  /// 点赞 / 收藏同步到服务端；失败时回滚本地状态
  @override
  void toggleLike(ForumPost post) {
    super.toggleLike(post);
    _syncPostAction(
      path: '/api/posts/${post.id}/like',
      field: 'liked',
      value: isLiked(post),
      rollback: () => super.toggleLike(post),
    );
  }

  @override
  void toggleFavorite(ForumPost post) {
    super.toggleFavorite(post);
    _syncPostAction(
      path: '/api/posts/${post.id}/favorite',
      field: 'favorited',
      value: isFavorite(post),
      rollback: () => super.toggleFavorite(post),
    );
  }

  Future<void> _syncPostAction({
    required String path,
    required String field,
    required bool value,
    required VoidCallback rollback,
  }) async {
    final me = AuthSession.instance.user.value;
    if (me == null) return;
    try {
      await _dio.post<Map<String, dynamic>>(path, data: {field: value});
    } on DioException {
      rollback();
    }
  }

  @override
  void markAllMessagesRead() {
    final hadUnread = hasUnreadMessages;
    super.markAllMessagesRead();
    if (hadUnread) _syncMessagesRead(null);
  }

  @override
  void markMessageRead(ForumMessage message) {
    final wasUnread = message.unread;
    super.markMessageRead(message);
    if (wasUnread) _syncMessagesRead(int.tryParse(message.id));
  }

  /// 已读状态同步到服务端，失败时保留本地状态，下次拉取会纠正
  Future<void> _syncMessagesRead(int? id) async {
    final me = AuthSession.instance.user.value;
    if (me == null) return;
    try {
      await _dio.post<Map<String, dynamic>>(
        '/api/messages/read',
        data: {if (id != null) 'id': id},
      );
    } on DioException {
      // 忽略同步失败
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
    List<String> images = const [],
    List<String> tags = const [],
  }) async {
    _requireUser();
    final data = await _post('/api/posts', {
      'section': section,
      'title': title.trim(),
      'content': content.trim(),
      if (images.isNotEmpty) 'images': images.take(3).toList(),
      if (tags.isNotEmpty) 'tags': tags.take(3).toList(),
    });
    final post = _postFromJson(data);
    replacePosts([post, ...cachedPosts.where((item) => item.id != post.id)]);
    return post;
  }

  @override
  Future<String> uploadImage({
    required Uint8List bytes,
    required String extension,
  }) async {
    _requireUser();
    final data = await _post(
      '/api/uploads',
      {'ext': extension.toLowerCase(), 'data': base64Encode(bytes)},
      options: Options(
        sendTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    final url = data['url'];
    if (url is! String || url.isEmpty) {
      throw const ForumException('图片上传失败，请重试');
    }
    // 发帖时服务端只接受 /uploads/ 相对路径，展示时才补全域名
    return url;
  }

  @override
  ForumPost? postById(String id) {
    for (final post in cachedPosts) {
      if (post.id == id) return post;
    }
    return null;
  }

  @override
  Future<String> uploadAudio({
    required Uint8List bytes,
    required int durationMs,
  }) async {
    _requireUser();
    final data = await _post(
      '/api/uploads',
      {'ext': 'wav', 'data': base64Encode(bytes)},
      options: Options(
        sendTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    final url = data['url'];
    if (url is! String || url.isEmpty) {
      throw const ForumException('语音上传失败，请重试');
    }
    return url;
  }

  @override
  Future<String> transcribeAudio({
    required Uint8List bytes,
    String dialect = 'mandarin',
  }) async {
    final data = await _post(
      '/api/asr',
      {'audio': base64Encode(bytes), 'dialect': dialect},
      options: Options(
        sendTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    final text = data['text'];
    return text is String ? text.trim() : '';
  }

  @override
  Future<ForumComment> addComment({
    required ForumPost post,
    required String content,
    ForumComment? replyTo,
    String? audioUrl,
    int? audioDurationMs,
  }) async {
    _requireUser();
    final parentId = replyTo == null ? null : int.tryParse(replyTo.id);
    final data = await _post('/api/posts/${post.id}/replies', {
      'content': content.trim(),
      if (parentId != null) 'parentId': parentId,
      if (audioUrl != null) 'audioUrl': audioUrl,
      if (audioDurationMs != null) 'audioDuration': audioDurationMs,
    });
    final comment = _commentFromJson(data);
    post.replyCount += 1;
    replaceComments(post.id, [...commentsOf(post.id), comment]);
    return comment;
  }

  @override
  Future<void> setFeatured(ForumPost post, bool featured) async {
    _requireUser();
    final previous = post.featured;
    await super.setFeatured(post, featured);
    try {
      await _dio.post<Map<String, dynamic>>(
        '/api/posts/${post.id}/feature',
        data: {'featured': featured},
      );
    } on DioException catch (error) {
      await super.setFeatured(post, previous);
      throw ForumException(_errorMessage(error));
    }
  }

  @override
  Future<void> deletePost(ForumPost post) async {
    _requireUser();
    try {
      await _dio.delete<Map<String, dynamic>>('/api/posts/${post.id}');
    } on DioException catch (error) {
      throw ForumException(_errorMessage(error));
    }
    await super.deletePost(post);
  }

  @override
  Future<void> deleteComment(ForumComment comment) async {
    _requireUser();
    try {
      await _dio.delete<Map<String, dynamic>>('/api/replies/${comment.id}');
    } on DioException catch (error) {
      throw ForumException(_errorMessage(error));
    }
    await super.deleteComment(comment);
  }

  @override
  Future<void> report({
    required String targetType,
    required String targetId,
    required String reason,
  }) async {
    _requireUser();
    final id = int.tryParse(targetId);
    if (id == null) throw const ForumException('该内容不支持投诉');
    await _post('/api/reports', {
      'targetType': targetType,
      'targetId': id,
      'reason': reason,
    });
  }

  /// 我的帖子：按当前账号用过的昵称匹配（改昵称前的帖子也算）
  @override
  List<ForumPost> get myPosts {
    final me = AuthSession.instance.user.value;
    if (me == null) return const [];
    final list =
        cachedPosts
            .where((post) => AuthSession.instance.isMyUserId(post.authorId))
            .toList();
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
    Map<String, dynamic> body, {
    Options? options,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        path,
        data: body,
        options: options,
      );
      return response.data ?? const {};
    } on DioException catch (error) {
      throw ForumException(_errorMessage(error));
    }
  }

  /// 服务端返回的是 `/uploads/xxx.jpg` 相对路径，这里补全为可访问地址
  String _absoluteUrl(String raw) {
    if (raw.isEmpty ||
        raw.startsWith('http://') ||
        raw.startsWith('https://') ||
        raw.startsWith('data:')) {
      return raw;
    }
    final base = _dio.options.baseUrl;
    return raw.startsWith('/') ? '$base$raw' : '$base/$raw';
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
    authorId: json['author_id'] == null ? null : '${json['author_id']}',
    createdAt: _parseTime(json['created_at']),
    likes: (json['likes'] as num?)?.toInt() ?? 0,
    replyCount: (json['reply_count'] as num?)?.toInt() ?? 0,
    featured: json['featured'] == true,
    images: _parseImages(json['images']),
    tags: _parseTags(json['tags']),
  );

  /// 服务端时间不带时区，按 UTC 解析后再转本地，避免显示慢 8 小时
  DateTime _parseTime(Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return DateTime.now();
    final hasZone =
        text.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(text);
    final parsed = DateTime.tryParse(hasZone ? text : '${text}Z');
    return (parsed ?? DateTime.now()).toLocal();
  }

  List<String> _parseTags(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<String>()
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .take(3)
        .toList(growable: false);
  }

  List<String> _parseImages(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<String>()
        .where((url) => url.isNotEmpty)
        .take(3)
        .map(_absoluteUrl)
        .toList(growable: false);
  }

  ForumComment _commentFromJson(Map<String, dynamic> json) => ForumComment(
    id: '${json['id']}',
    postId: '${json['post_id']}',
    author: json['author'] as String? ?? '农友',
    authorId: json['author_id'] == null ? null : '${json['author_id']}',
    content: json['content'] as String? ?? '',
    createdAt: _parseTime(json['created_at']),
    parentId: json['parent_id'] == null ? null : '${json['parent_id']}',
    replyToAuthor: json['parent_author'] as String?,
    audioUrl:
        (json['audio_url'] as String?)?.isNotEmpty == true
            ? _absoluteUrl(json['audio_url'] as String)
            : null,
    audioDurationMs: (json['audio_duration'] as num?)?.toInt(),
  );

  ForumMessage _messageFromJson(Map<String, dynamic> json) => ForumMessage(
    id: '${json['id']}',
    kind: switch (json['kind']) {
      'reply' => ForumMessageKind.reply,
      'favorite' => ForumMessageKind.favorite,
      _ => ForumMessageKind.like,
    },
    title: json['title'] as String? ?? '新的消息',
    body: json['body'] as String? ?? '',
    createdAt: _parseTime(json['created_at']),
    unread: json['unread'] == true,
    postId: json['post_id'] == null ? null : '${json['post_id']}',
    // 后端新字段叫 reply_id，旧字段 comment_id 也兼容
    replyId:
        json['reply_id'] != null
            ? '${json['reply_id']}'
            : (json['comment_id'] == null ? null : '${json['comment_id']}'),
  );
}

/// App 默认论坛数据源：所有登录用户共享服务器数据
final ForumApiRepository defaultForumApiRepository = ForumApiRepository();
