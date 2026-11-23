import 'package:flutter/material.dart';

import '../../../core/accessibility/elder_care_reader.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/data/auth_session.dart';
import '../data/forum_models.dart';
import 'forum_voice_bubble.dart';

/// 单条评论
class ForumCommentTile extends StatelessWidget {
  const ForumCommentTile({
    super.key,
    required this.comment,
    this.onReply,
    this.onReport,
    this.onDelete,
  });

  final ForumComment comment;

  /// 点击「回复」回调，为空时不展示回复入口
  final VoidCallback? onReply;

  /// 点击「投诉」回调，为空时不展示投诉入口
  final VoidCallback? onReport;

  /// 点击「删除」回调，仅自己的评论会传入
  final VoidCallback? onDelete;

  bool get _isReply => comment.parentId != null;

  /// 作者名与被回复人名：自己改过昵称后展示新昵称
  String get _authorName => AuthSession.instance.displayName(comment.author);
  String? get _replyToName {
    final name = comment.replyToAuthor;
    return name == null ? null : AuthSession.instance.displayName(name);
  }

  String get _avatarText {
    if (_authorName.isEmpty) return '?';
    return String.fromCharCode(_authorName.runes.first);
  }

  @override
  Widget build(BuildContext context) {
    // 监听登录用户变化，资料改昵称后评论区的昵称立即同步
    return ValueListenableBuilder<AuthUser?>(
      valueListenable: AuthSession.instance.user,
      builder:
          (context, _, __) => ElderCareBlock(
            // 只朗读昵称与评论内容，跳过时间
            readText:
                _isReply
                    ? '$_authorName 回复 $_replyToName。'
                        '${comment.isVoice ? '语音评论：' : ''}${comment.content}'
                    : '$_authorName。'
                        '${comment.isVoice ? '语音评论：' : ''}${comment.content}',
            child: _buildTile(context),
          ),
    );
  }

  Widget _buildTile(BuildContext context) {
    return Padding(
      // 回复别人的评论整体缩进，和时间线区分开
      padding: EdgeInsets.fromLTRB(_isReply ? 44 : 16, 10, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Text(
              _avatarText,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _authorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.palette.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        forumTimeText(comment.createdAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: context.palette.textHint,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (comment.isVoice) ...[
                  if (_isReply && comment.replyToAuthor != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '回复 @$_replyToName：',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ForumVoiceBubble(
                    url: comment.audioUrl!,
                    durationMs: comment.audioDurationMs ?? 0,
                    transcript: comment.content,
                  ),
                ] else
                  Text.rich(
                    TextSpan(
                      children: [
                        if (_isReply)
                          TextSpan(
                            text: '回复 @$_replyToName：',
                            style: const TextStyle(color: AppColors.primary),
                          ),
                        TextSpan(text: comment.content),
                      ],
                    ),
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: context.palette.textSecondary,
                    ),
                  ),
                if (onReply != null ||
                    onReport != null ||
                    onDelete != null) ...[
                  const SizedBox(height: 2),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (onReply != null)
                          _action(Icons.reply, '回复', onReply!),
                        if (onReport != null)
                          _action(Icons.flag_outlined, '投诉', onReport!),
                        if (onDelete != null)
                          _action(
                            Icons.delete_outline,
                            '删除',
                            onDelete!,
                            color: AppColors.error,
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _action(
    IconData icon,
    String label,
    VoidCallback onTap, {
    Color color = AppColors.textHint,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 3),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }
}
