import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'forum_models.dart';

/// 论坛操作失败，[message] 可直接展示给用户
class ForumException implements Exception {
  const ForumException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 论坛数据与交互的统一接口。
///
/// 页面只依赖该接口，不关心数据来自内存、本地数据库还是后端。
/// 外部可通过 [ForumScope] 注入自定义实现。
abstract class ForumRepository extends ChangeNotifier {
  List<ForumCategory> get categories;

  List<ForumSection> get sections;

  /// 发帖时可选的全部版块名称
  List<String> get sectionTitles;

  List<ForumSection> sectionsOf(String category);

  List<ForumPost> postsOf(String section);

  List<ForumPost> get myPosts;

  int countOf(String section);

  Future<ForumPost> publish({
    required String section,
    required String title,
    required String content,
    bool pendingReview = false,
    List<String> images = const [],
    List<String> tags = const [],
  });

  /// 上传一张帖子配图，返回可访问的 URL。
  ///
  /// 内存实现返回 data URI，远端实现上传到服务器。
  Future<String> uploadImage({
    required Uint8List bytes,
    required String extension,
  }) async {
    throw const ForumException('当前数据源不支持上传图片');
  }

  void toggleLike(ForumPost post);

  /// 当前用户是否已给该帖点赞
  bool isLiked(ForumPost post);

  /// 帖子评论（按时间正序，来自本地缓存）
  List<ForumComment> commentsOf(String postId);

  /// 从远端加载某帖的评论，内存实现无需处理
  Future<void> loadComments(String postId) async {}

  Future<ForumComment> addComment({
    required ForumPost post,
    required String content,
    ForumComment? replyTo,
  });

  /// 设置 / 取消精选（推荐分区优先展示精选内容）
  Future<void> setFeatured(ForumPost post, bool featured) async {}

  /// 删除自己的帖子（服务端会校验作者）
  Future<void> deletePost(ForumPost post) async {}

  /// 删除自己的评论，回复该评论的内容会一并删除
  Future<void> deleteComment(ForumComment comment) async {}

  /// 投诉帖子或评论，[targetType] 为 post 或 reply
  Future<void> report({
    required String targetType,
    required String targetId,
    required String reason,
  }) async {}

  bool isFavorite(ForumPost post);

  /// 收藏 / 取消收藏
  void toggleFavorite(ForumPost post);

  List<ForumPost> get favoritePosts;

  List<ForumMessage> get messages;

  /// 按类型筛选消息（点赞 / 回复）
  List<ForumMessage> messagesOf(ForumMessageKind kind);

  bool get hasUnreadMessages;

  void markAllMessagesRead();

  void markMessageRead(ForumMessage message);

  /// 下拉手动刷新时调用，外部数据源可在此拉取最新数据后通知界面
  Future<void> refresh() async {
    notifyListeners();
  }

  /// 是否支持从服务端实时拉取消息提醒（内存实现不支持）
  bool get supportsRealtimeMessages => false;

  /// 拉取当前用户的消息提醒，内存实现无需处理
  Future<void> loadMessages() async {}
}

/// 默认的内存实现（App 重启后恢复示例数据）。
///
/// 所有目录数据都允许在构造时传入，便于测试或外部数据源覆盖。
class InMemoryForumRepository extends ForumRepository {
  InMemoryForumRepository({
    List<ForumCategory>? categories,
    List<ForumSection>? sections,
    List<ForumPost>? posts,
    List<ForumMessage>? messages,
    Map<String, List<ForumComment>>? comments,
    List<String>? favoritePostIds,
    bool seed = true,
  })  : _categories = List.unmodifiable(categories ?? forumCategories),
        _sections = List.unmodifiable(sections ?? forumSections) {
    if (posts != null) {
      _posts.addAll(posts);
    } else if (seed) {
      _posts.addAll(_seedPosts());
    }
    if (messages != null) {
      _messages.addAll(messages);
    } else if (seed) {
      _messages.addAll(_seedMessages());
    }
    if (comments != null) {
      comments.forEach((postId, list) {
        _comments[postId] = [...list];
      });
    } else if (seed) {
      _seedComments();
    }
    if (favoritePostIds != null) {
      favoriteIds.addAll(favoritePostIds);
    }
  }

  static const String currentUserName = '我';

  final List<ForumCategory> _categories;
  final List<ForumSection> _sections;
  final List<ForumPost> _posts = [];
  final List<ForumMessage> _messages = [];
  final Map<String, List<ForumComment>> _comments = {};
  final Set<String> favoriteIds = {};
  /// 当前用户点过赞的帖子 id，用于正确的点赞/取消点赞切换
  @protected
  final Set<String> likedIds = {};
  int _idSeed = 0;

  @override
  List<ForumCategory> get categories => _categories;

  @override
  List<ForumSection> get sections => _sections;

  @override
  List<String> get sectionTitles =>
      List.unmodifiable(_sections.map((s) => s.title));

  @override
  List<ForumSection> sectionsOf(String category) =>
      _sections.where((s) => s.category == category).toList(growable: false);

  @override
  List<ForumPost> postsOf(String section) {
    if (section == forumRecommendedSection) return _recommendedPosts();
    final list = _posts.where((p) => p.section == section).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// 推荐分区：精选帖子全部展示，不足 [recommendedMinCount] 条时用热门帖子补齐
  static const int recommendedMinCount = 12;

  List<ForumPost> _recommendedPosts() {
    final result = _posts.where((p) => p.featured).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (result.length >= recommendedMinCount) return result;

    final chosen = result.map((p) => p.id).toSet();
    final hot = _posts.where((p) => !chosen.contains(p.id)).toList()
      ..sort((a, b) {
        final diff = _heatOf(b).compareTo(_heatOf(a));
        return diff != 0 ? diff : b.createdAt.compareTo(a.createdAt);
      });
    for (final post in hot) {
      if (result.length >= recommendedMinCount) break;
      result.add(post);
    }
    return result;
  }

  /// 热度 = 点赞 + 评论 × 3
  int _heatOf(ForumPost post) => post.likes + post.replyCount * 3;

  @override
  List<ForumPost> get myPosts {
    final list =
        _posts.where((p) => p.author == currentUserName).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  int countOf(String section) => section == forumRecommendedSection
      ? _recommendedPosts().length
      : _posts.where((p) => p.section == section).length;

  /// 供远端实现读取当前缓存
  @protected
  List<ForumPost> get cachedPosts => List.unmodifiable(_posts);

  /// 用远端结果替换帖子缓存
  @protected
  void replacePosts(Iterable<ForumPost> posts) {
    _posts
      ..clear()
      ..addAll(posts);
    notifyListeners();
  }

  /// 用远端结果替换某帖评论缓存
  @protected
  void replaceComments(String postId, Iterable<ForumComment> comments) {
    _comments[postId] = [...comments];
    notifyListeners();
  }

  /// 用远端结果替换消息提醒缓存
  @protected
  void replaceMessages(Iterable<ForumMessage> messages) {
    _messages
      ..clear()
      ..addAll(messages);
    notifyListeners();
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
    final post = ForumPost(
      id: 'local_${DateTime.now().microsecondsSinceEpoch}_${_idSeed++}',
      section: section,
      title: title.trim(),
      content: content.trim(),
      author: currentUserName,
      createdAt: DateTime.now(),
      pendingReview: pendingReview,
      images: List.unmodifiable(images.take(3)),
      tags: List.unmodifiable(
        tags
            .map((tag) => tag.replaceFirst(RegExp(r'^#+'), '').trim())
            .where((tag) => tag.isNotEmpty)
            .toSet()
            .take(3),
      ),
    );
    _posts.add(post);
    notifyListeners();
    return post;
  }

  /// 内存实现把图片转成 data URI，便于本地预览与测试
  @override
  Future<String> uploadImage({
    required Uint8List bytes,
    required String extension,
  }) async {
    final mime = extension.toLowerCase() == 'png' ? 'png' : 'jpeg';
    return 'data:image/$mime;base64,${base64Encode(bytes)}';
  }

  @override
  void toggleLike(ForumPost post) {
    final target = _posts.firstWhere((p) => p.id == post.id, orElse: () => post);
    // 本地没有该帖（理论上不会出现）时直接忽略
    if (!_posts.contains(target)) return;

    if (likedIds.remove(post.id)) {
      // 取消点赞：不能把点赞数减成负数
      target.likes = target.likes > 0 ? target.likes - 1 : 0;
    } else {
      likedIds.add(post.id);
      target.likes += 1;
    }
    post.likes = target.likes;
    notifyListeners();
  }

  @override
  bool isLiked(ForumPost post) => likedIds.contains(post.id);

  @override
  List<ForumComment> commentsOf(String postId) {
    final list = [...?_comments[postId]];
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return List.unmodifiable(list);
  }

  @override
  Future<ForumComment> addComment({
    required ForumPost post,
    required String content,
    ForumComment? replyTo,
  }) async {
    final comment = ForumComment(
      id: 'comment_${DateTime.now().microsecondsSinceEpoch}_${_idSeed++}',
      postId: post.id,
      author: currentUserName,
      content: content.trim(),
      createdAt: DateTime.now(),
      parentId: replyTo?.id,
      replyToAuthor: replyTo?.author,
    );
    _comments.putIfAbsent(post.id, () => []).add(comment);
    final target =
        _posts.firstWhere((p) => p.id == post.id, orElse: () => post);
    if (_posts.contains(target)) target.replyCount += 1;
    post.replyCount = target.replyCount;
    notifyListeners();
    return comment;
  }

  @override
  Future<void> setFeatured(ForumPost post, bool featured) async {
    final target =
        _posts.firstWhere((p) => p.id == post.id, orElse: () => post);
    if (!_posts.contains(target)) return;
    target.featured = featured;
    post.featured = featured;
    notifyListeners();
  }

  @override
  Future<void> deletePost(ForumPost post) async {
    final before = _posts.length;
    _posts.removeWhere((item) => item.id == post.id);
    if (_posts.length == before) return;
    _comments.remove(post.id);
    likedIds.remove(post.id);
    favoriteIds.remove(post.id);
    notifyListeners();
  }

  @override
  Future<void> deleteComment(ForumComment comment) async {
    final list = _comments[comment.postId];
    if (list == null) return;

    // 删除评论时，把直接与间接回复一并移除
    final removedIds = <String>{comment.id};
    var changed = true;
    while (changed) {
      changed = false;
      for (final item in list) {
        final parentId = item.parentId;
        if (parentId != null &&
            removedIds.contains(parentId) &&
            removedIds.add(item.id)) {
          changed = true;
        }
      }
    }

    final before = list.length;
    list.removeWhere((item) => removedIds.contains(item.id));
    final removed = before - list.length;
    for (final post in _posts) {
      if (post.id == comment.postId) {
        post.replyCount =
            post.replyCount > removed ? post.replyCount - removed : 0;
        break;
      }
    }
    notifyListeners();
  }

  @override
  bool isFavorite(ForumPost post) => favoriteIds.contains(post.id);

  @override
  void toggleFavorite(ForumPost post) {
    if (!favoriteIds.remove(post.id)) {
      favoriteIds.add(post.id);
    }
    notifyListeners();
  }

  @override
  List<ForumPost> get favoritePosts {
    final list = _posts.where((p) => favoriteIds.contains(p.id)).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  List<ForumMessage> get messages => List.unmodifiable(_messages);

  @override
  List<ForumMessage> messagesOf(ForumMessageKind kind) =>
      List.unmodifiable(_messages.where((message) => message.kind == kind));

  @override
  bool get hasUnreadMessages => _messages.any((m) => m.unread);

  @override
  void markAllMessagesRead() {
    var changed = false;
    for (final message in _messages) {
      if (message.unread) {
        message.unread = false;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  @override
  void markMessageRead(ForumMessage message) {
    if (!message.unread) return;
    message.unread = false;
    notifyListeners();
  }

  List<ForumPost> _seedPosts() {
    final now = DateTime.now();
    return [
      ForumPost(
        id: 'seed_1',
        section: '农友留言区',
        title: '第一次用护花使者，求作业参数参考',
        content: '水稻田，3 米高度、4 米每秒、行距 5 米，这样设置合理吗？有没有老哥指点一下。',
        author: '种田的老张',
        createdAt: now.subtract(const Duration(minutes: 18)),
        likes: 6,
        replyCount: 2,
      ),
      ForumPost(
        id: 'seed_2',
        section: '飞防作业交流',
        title: '3 米高度和 2.5 米高度，水稻田哪个更合适？',
        content: '风大的时候 3 米飘移明显，2.5 米又怕压苗，想听听大家的实际经验。',
        author: '飞防小王',
        createdAt: now.subtract(const Duration(hours: 2)),
        likes: 12,
      ),
      ForumPost(
        id: 'seed_3',
        section: '病虫害问答',
        title: '叶片上有黄褐色斑点，是稻瘟病吗？',
        content: '近几天连阴雨，田里出现梭形病斑，边缘褐色中间灰白，帮忙看看。',
        author: '小林',
        createdAt: now.subtract(const Duration(hours: 5)),
        likes: 4,
        replyCount: 1,
      ),
      ForumPost(
        id: 'seed_4',
        section: '农友留言区',
        title: '作业记录导出能不能加个 Excel？',
        content: '现在只能看列表，想导出来做台账，希望后面版本考虑一下。',
        author: '农机手阿伟',
        createdAt: now.subtract(const Duration(days: 1)),
        likes: 9,
      ),
      ForumPost(
        id: 'seed_5',
        section: '药效点评',
        title: '吡虫啉复配阿维菌素，一周后效果记录',
        content: '稻飞虱防治，按推荐剂量复配，7 天后虫口明显下降，分享给需要的人。',
        author: '农技小陈',
        createdAt: now.subtract(const Duration(days: 2)),
        likes: 15,
      ),
      ForumPost(
        id: 'seed_6',
        section: '公告与通知',
        title: 'v2.9.6 已发布，修复无法降级安装的问题',
        content: '本次更新提升了 versionCode，解决覆盖安装时提示“无法降级安装”的问题。',
        author: '管理员',
        createdAt: now.subtract(const Duration(days: 3)),
        likes: 2,
      ),
    ];
  }

  void _seedComments() {
    final now = DateTime.now();
    _comments['seed_1'] = [
      ForumComment(
        id: 'comment_1',
        postId: 'seed_1',
        author: '飞防小王',
        content: '3 米高度、4 米每秒我们这边也常用，行距 5 米没问题，注意下风向留出缓冲带。',
        createdAt: now.subtract(const Duration(minutes: 12)),
      ),
      ForumComment(
        id: 'comment_2',
        postId: 'seed_1',
        author: '种田的老李',
        content: '风大的时候建议降到 2.5 米，雾滴飘移会小很多。',
        createdAt: now.subtract(const Duration(minutes: 5)),
      ),
    ];
    _comments['seed_3'] = [
      ForumComment(
        id: 'comment_3',
        postId: 'seed_3',
        author: '农技小陈',
        content: '看描述像稻瘟病，建议拍几张清晰照片，再结合天气和品种判断。',
        createdAt: now.subtract(const Duration(hours: 4)),
      ),
    ];
  }

  List<ForumMessage> _seedMessages() {
    final now = DateTime.now();
    return [
      ForumMessage(
        id: 'msg_like_1',
        kind: ForumMessageKind.like,
        title: '农友 种田的老张 赞了你的帖子',
        body: '「第一次使用护花使者，求作业参数参考」',
        createdAt: now.subtract(const Duration(minutes: 25)),
        unread: true,
      ),
      ForumMessage(
        id: 'msg_like_2',
        kind: ForumMessageKind.like,
        title: '农友 李师傅 赞了你的评论',
        body: '你在「病虫害问答」的回复获得了 3 个赞。',
        createdAt: now.subtract(const Duration(hours: 6)),
      ),
      ForumMessage(
        id: 'msg_reply_1',
        kind: ForumMessageKind.reply,
        title: '意见反馈已回复',
        body: '管理员：你反馈的作业记录导出问题已记录，下个版本将支持 Excel 导出。',
        createdAt: now.subtract(const Duration(hours: 2)),
        unread: true,
      ),
      ForumMessage(
        id: 'msg_reply_2',
        kind: ForumMessageKind.reply,
        title: '举报处理结果通知',
        body: '你举报的广告帖已核实并删除，感谢你对社区环境的维护。',
        createdAt: now.subtract(const Duration(days: 1)),
      ),
      ForumMessage(
        id: 'msg_reply_3',
        kind: ForumMessageKind.reply,
        title: '「举报与版规」版规更新通知',
        body: '新增违规广告与联系方式的处理细则，发布前请先阅读版规。',
        createdAt: now.subtract(const Duration(days: 3)),
      ),
      ForumMessage(
        id: 'msg_fav_1',
        kind: ForumMessageKind.favorite,
        title: '农友 农机手阿伟 收藏了你的帖子',
        body: '「作业记录导出能不能加个 Excel？」',
        createdAt: now.subtract(const Duration(hours: 1)),
        unread: true,
      ),
      ForumMessage(
        id: 'msg_fav_2',
        kind: ForumMessageKind.favorite,
        title: '农友 飞防小王 收藏了你的评论',
        body: '你在「意见反馈」的回复被收藏。',
        createdAt: now.subtract(const Duration(hours: 5)),
      ),
    ];
  }
}

/// 默认数据源：App 内直接使用，也可被外部替换。
/// 不加载内置示例，论坛初始为空，帖子全部由用户发布。
final ForumRepository defaultForumRepository =
    InMemoryForumRepository(seed: false);
