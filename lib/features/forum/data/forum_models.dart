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
    this.pendingReview = false,
  });

  final String id;
  final String section;
  final String title;
  final String content;
  final String author;
  final DateTime createdAt;
  int likes;

  /// 是否等待人工复审（AI 初审无法直接判定时标记）
  final bool pendingReview;
}

/// 帖子评论
class ForumComment {
  ForumComment({
    required this.id,
    required this.postId,
    required this.author,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String postId;
  final String author;
  final String content;
  final DateTime createdAt;
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

/// 相对时间展示
String forumTimeText(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  if (diff.inDays < 30) return '${diff.inDays} 天前';
  return '${time.month}月${time.day}日';
}
