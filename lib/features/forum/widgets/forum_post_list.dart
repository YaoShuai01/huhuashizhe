import 'package:flutter/material.dart';

import '../data/forum_models.dart';
import 'forum_post_card.dart';
import 'forum_responsive_body.dart';

/// 帖子列表：统一列表内边距、自适应宽度与点赞交互
class ForumPostList extends StatelessWidget {
  const ForumPostList({
    super.key,
    required this.posts,
    required this.onLike,
    this.padding = const EdgeInsets.only(top: 8, bottom: 88),
  });

  final List<ForumPost> posts;
  final ValueChanged<ForumPost> onLike;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ForumResponsiveBody(
      padding: padding,
      child: ListView.builder(
        itemCount: posts.length,
        itemBuilder: (context, index) {
          final post = posts[index];
          return ForumPostCard(
            post: post,
            onLike: () => onLike(post),
          );
        },
      ),
    );
  }
}
