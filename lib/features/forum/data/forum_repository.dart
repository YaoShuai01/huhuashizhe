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

  List<ForumMessage> get messages;

  bool get hasUnreadMessages;

  void markAllMessagesRead();

  void markMessageRead(ForumMessage message);
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
  }

  static const String currentUserName = '我';

  final List<ForumCategory> _categories;
  final List<ForumSection> _sections;
  final List<ForumPost> _posts = [];
  final List<ForumMessage> _messages = [];
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
  List<ForumMessage> get messages => List.unmodifiable(_messages);

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
        section: '网友留言区',
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
        section: '网友留言区',
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

  List<ForumMessage> _seedMessages() {
    final now = DateTime.now();
    return [
      ForumMessage(
        id: 'msg_1',
        kind: ForumMessageKind.announcement,
        title: 'v2.9.6 版本已发布',
        body: '修复覆盖安装提示“无法降级安装”的问题，建议尽快更新。',
        createdAt: now.subtract(const Duration(days: 3)),
        unread: true,
      ),
      ForumMessage(
        id: 'msg_2',
        kind: ForumMessageKind.reply,
        title: '有人回复了你的帖子',
        body: '飞防小王：这个高度我们这边一般用 2.8 米，风大再降一点。',
        createdAt: now.subtract(const Duration(hours: 2)),
        unread: true,
      ),
      ForumMessage(
        id: 'msg_3',
        kind: ForumMessageKind.moderation,
        title: '版务通知',
        body: '社区版规已更新，请勿发布广告与联系方式，违规内容将被删除。',
        createdAt: now.subtract(const Duration(days: 5)),
      ),
    ];
  }
}

/// 默认数据源：App 内直接使用，也可被外部替换
final ForumRepository defaultForumRepository = InMemoryForumRepository();
