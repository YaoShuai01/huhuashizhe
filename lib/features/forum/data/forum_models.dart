import 'package:flutter/material.dart';

/// 论坛分区（顶部分区入口的数据模型）
class ForumCategory {
  const ForumCategory({
    required this.name,
    required this.icon,
  });

  final String name;
  final IconData icon;
}

/// 论坛版块（分区下的具体版块）
class ForumSection {
  const ForumSection({
    required this.title,
    required this.desc,
    required this.category,
    this.hot = false,
  });

  final String title;
  final String desc;

  /// 所属分区名称
  final String category;
  final bool hot;
}

/// 论坛帖子
class ForumPost {
  ForumPost({
    required this.id,
    required this.section,
    required this.title,
    required this.content,
    required this.author,
    required this.createdAt,
    this.likes = 0,
    this.replyCount = 0,
    this.featured = false,
    this.pendingReview = false,
    this.images = const [],
    this.tags = const [],
  });

  final String id;
  final String section;
  final String title;
  final String content;
  final String author;
  final DateTime createdAt;
  int likes;
  int replyCount;

  /// 是否被标记为精选（推荐分区优先展示）
  bool featured;

  /// 帖子配图（服务器可访问的 URL，最多 3 张）
  final List<String> images;

  /// 附加 #标签（不含版块，最多 3 个）
  final List<String> tags;

  /// 是否等待人工复审（AI 初审无法直接判定时标记）
  final bool pendingReview;
}

/// 首页顶部的聚合分区：汇总精选内容，不足时用热门帖子补齐
const String forumRecommendedSection = '推荐';

/// 帖子评论
class ForumComment {
  ForumComment({
    required this.id,
    required this.postId,
    required this.author,
    required this.content,
    required this.createdAt,
    this.parentId,
    this.replyToAuthor,
  });

  final String id;
  final String postId;
  final String author;
  final String content;
  final DateTime createdAt;

  /// 回复的评论 id，为空表示直接评论帖子
  final String? parentId;

  /// 被回复人昵称，用于在评论内容前展示「回复 @某某」
  final String? replyToAuthor;
}

/// 消息类型（决定图标与语义）
enum ForumMessageKind { like, reply, favorite, announcement, moderation }

/// 论坛消息
class ForumMessage {
  ForumMessage({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    this.unread = false,
  });

  final String id;
  final ForumMessageKind kind;
  final String title;
  final String body;
  final DateTime createdAt;
  bool unread;
}

/// 默认分区目录（可被外部数据源覆盖）
const List<ForumCategory> forumCategories = [
  ForumCategory(name: '交流区', icon: Icons.forum_outlined),
  ForumCategory(name: '问答区', icon: Icons.rate_review_outlined),
  ForumCategory(name: '管理区', icon: Icons.shield_outlined),
];

/// 默认版块目录（可被外部数据源覆盖）
const List<ForumSection> forumSections = [
  ForumSection(
    title: '农友留言区',
    desc: '不限植保领域，想说、疑问、吐槽、讨论，都可以在这里发',
    category: '交流区',
    hot: true,
  ),
  ForumSection(
    title: '飞防作业交流',
    desc: '航线规划、作业参数、避障技巧，一起交流实战经验',
    category: '交流区',
  ),
  ForumSection(
    title: '设备与保养',
    desc: '电池、桨叶、喷头的日常维护与故障处理心得',
    category: '交流区',
  ),
  ForumSection(
    title: '作业晒图',
    desc: '晒作业航线、作业面积与喷洒效果，分享你的成果',
    category: '交流区',
  ),
  ForumSection(
    title: '病虫害问答',
    desc: '水稻、小麦、玉米等作物病虫害识别与防治讨论',
    category: '问答区',
  ),
  ForumSection(
    title: '新手提问区',
    desc: '零基础上手、参数设置、常见报错，新手问题都放这里',
    category: '问答区',
  ),
  ForumSection(
    title: '药效点评',
    desc: '施药效果、配药方案的点评与讨论',
    category: '问答区',
  ),
  ForumSection(
    title: '作业复盘',
    desc: '分享作业记录，交流改进建议',
    category: '问答区',
  ),
  ForumSection(
    title: '公告与通知',
    desc: 'APP 版本更新、活动公告与重要通知',
    category: '管理区',
  ),
  ForumSection(
    title: '意见反馈',
    desc: '使用问题、功能建议与投诉处理',
    category: '管理区',
  ),
  ForumSection(
    title: '举报与版规',
    desc: '社区版规说明、违规内容举报与处理公示',
    category: '管理区',
  ),
];

/// 时间展示：直接显示发布时刻（时分/日期），不使用“几分钟前”这类相对时间
String forumTimeText(DateTime time) {
  final local = time.toLocal();
  final now = DateTime.now();
  final clock =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    return '今天 $clock';
  }
  final yesterday = now.subtract(const Duration(days: 1));
  if (local.year == yesterday.year &&
      local.month == yesterday.month &&
      local.day == yesterday.day) {
    return '昨天 $clock';
  }
  if (local.year == now.year) {
    return '${local.month}月${local.day}日 $clock';
  }
  return '${local.year}年${local.month}月${local.day}日 $clock';
}
