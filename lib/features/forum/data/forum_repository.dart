import 'package:flutter/foundation.dart';

import 'forum_models.dart';

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

  ForumPost publish({
    required String section,
    required String title,
    required String content,
  });

  void toggleLike(ForumPost post);

  /// 帖子评论（按时间正序）
  List<ForumComment> commentsOf(String postId);

  ForumComment addComment({
    required ForumPost post,
    required String content,
  });

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
      _favoriteIds.addAll(favoritePostIds);
    }
  }

  static const String currentUserName = '我';

  final List<ForumCategory> _categories;
  final List<ForumSection> _sections;
  final List<ForumPost> _posts = [];
  final List<ForumMessage> _messages = [];
  final Map<String, List<ForumComment>> _comments = {};
  final Set<String> _favoriteIds = {};
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
    final list = _posts.where((p) => p.section == section).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  List<ForumPost> get myPosts {
    final list =
        _posts.where((p) => p.author == currentUserName).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  int countOf(String section) =>
      _posts.where((p) => p.section == section).length;

  @override
  ForumPost publish({
    required String section,
    required String title,
    required String content,
  }) {
    final post = ForumPost(
      id: 'local_${DateTime.now().microsecondsSinceEpoch}_${_idSeed++}',
      section: section,
      title: title.trim(),
      content: content.trim(),
      author: currentUserName,
      createdAt: DateTime.now(),
    );
    _posts.add(post);
    notifyListeners();
    return post;
  }

  @override
  void toggleLike(ForumPost post) {
    final target = _posts.firstWhere((p) => p.id == post.id, orElse: () => post);
    // 本地没有该帖（理论上不会出现）时直接忽略
    if (!_posts.contains(target)) return;
    target.likes += target.likes > 0 && post.likes == target.likes ? -1 : 1;
    post.likes = target.likes;
    notifyListeners();
  }

  @override
  List<ForumComment> commentsOf(String postId) {
    final list = [...?_comments[postId]];
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return List.unmodifiable(list);
  }

  @override
  ForumComment addComment({
    required ForumPost post,
    required String content,
  }) {
    final comment = ForumComment(
      id: 'comment_${DateTime.now().microsecondsSinceEpoch}_${_idSeed++}',
      postId: post.id,
      author: currentUserName,
      content: content.trim(),
      createdAt: DateTime.now(),
    );
    _comments.putIfAbsent(post.id, () => []).add(comment);
    notifyListeners();
    return comment;
  }

  @override
  bool isFavorite(ForumPost post) => _favoriteIds.contains(post.id);

  @override
  void toggleFavorite(ForumPost post) {
    if (!_favoriteIds.remove(post.id)) {
      _favoriteIds.add(post.id);
    }
    notifyListeners();
  }

  @override
  List<ForumPost> get favoritePosts {
    final list = _posts.where((p) => _favoriteIds.contains(p.id)).toList();
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

/// 默认数据源：App 内直接使用，也可被外部替换
final ForumRepository defaultForumRepository = InMemoryForumRepository();
