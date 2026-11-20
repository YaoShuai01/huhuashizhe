import 'package:flutter/material.dart';

import '../../../core/accessibility/elder_care_reader.dart';
import '../../../core/theme/app_theme.dart';
import '../data/forum_models.dart';
import '../data/forum_repository.dart';
import '../forum_scope.dart';
import '../services/forum_moderation_service.dart';
import '../services/forum_voice_input.dart';
import '../widgets/forum_back_button.dart';
import '../widgets/forum_comment_tile.dart';
import '../widgets/forum_responsive_body.dart';
import '../widgets/forum_voice_button.dart';

/// 帖子详情：查看正文、点赞、收藏与评论
class ForumPostDetailPage extends StatefulWidget {
  const ForumPostDetailPage({
    super.key,
    required this.post,
    this.repository,
    this.voiceRecognizer,
    this.moderationService,
  });

  final ForumPost post;

  /// 外部注入的数据源，为空时取 ForumScope 或默认实现
  final ForumRepository? repository;

  /// 外部注入的语音识别实现，为空时使用系统语音识别
  final ForumVoiceRecognizer? voiceRecognizer;

  /// 外部注入的内容初审实现，为空时使用 AI 初审
  final ForumModerationService? moderationService;

  @override
  State<ForumPostDetailPage> createState() => _ForumPostDetailPageState();
}

class _ForumPostDetailPageState extends State<ForumPostDetailPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _canSend = false;
  bool _sending = false;
  bool _showEmojiPanel = false;

  /// 评论常用表情（点击插入正文）
  static const List<String> _commentEmojis = [
    '😀', '😁', '😂', '🤣', '😊', '😍', '🥰', '😎',
    '🤔', '😅', '😭', '😢', '😡', '😴', '🤝', '🙏',
    '👍', '👎', '👏', '💪', '❤️', '🔥', '🎉', '💯',
    '🌱', '🌿', '🌾', '🌻', '🚜', '🐛', '💧', '☀️',
  ];

  void _toggleEmojiPanel() {
    setState(() => _showEmojiPanel = !_showEmojiPanel);
    if (_showEmojiPanel) {
      _focusNode.unfocus();
    } else {
      _focusNode.requestFocus();
    }
  }

  /// 在光标位置插入表情，并保持输入可用
  void _insertEmoji(String emoji) {
    final text = _controller.text;
    final selection = _controller.selection;
    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;
    _controller.value = TextEditingValue(
      text: text.replaceRange(start, end, emoji),
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
    if (!_canSend) setState(() => _canSend = true);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send(ForumRepository repository) async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);

    final service = widget.moderationService ?? defaultForumModerationService;
    final result = await service.review(
      title: '评论：${widget.post.title}',
      content: text,
    );
    if (!mounted) return;
    setState(() => _sending = false);

    if (result.rejected) {
      await _showRejectDialog(result);
      return;
    }

    repository.addComment(
      post: widget.post,
      content: text,
    );
    _controller.clear();
    _focusNode.unfocus();
    setState(() => _canSend = false);
    if (result.needsManualReview) {
      _toast('评论已提交，人工复审通过后展示');
    }
  }

  Future<void> _showRejectDialog(ForumAuditResult result) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('评论未通过审核'),
        content: Text(
          '违规类型：${result.violationType}\n\n${result.reason}\n\n请修改后重新发送。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _toggleFavorite(ForumRepository repository) {
    final wasFavorite = repository.isFavorite(widget.post);
    repository.toggleFavorite(widget.post);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          wasFavorite ? '已取消收藏' : '已收藏，可在「我的 - 我的收藏」查看',
        ),
        duration: const Duration(milliseconds: 1500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository ?? ForumScope.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const ForumBackButton(),
        title: const Text('帖子详情'),
        actions: [
          AnimatedBuilder(
            animation: repository,
            builder: (context, _) {
              final favorited = repository.isFavorite(widget.post);
              return IconButton(
                tooltip: favorited ? '取消收藏' : '收藏',
                onPressed: () => _toggleFavorite(repository),
                icon: Icon(
                  favorited ? Icons.bookmark : Icons.bookmark_border,
                  color: AppColors.textOnPrimary,
                ),
              );
            },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: repository,
        builder: (context, _) {
          final comments = repository.commentsOf(widget.post.id);
          return ForumResponsiveBody(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(top: 10, bottom: 10),
                    children: [
                      _postHeader(repository),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Text(
                          '全部评论 ${comments.length}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (comments.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: Text(
                              '还没有评论，来说两句',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textHint,
                              ),
                            ),
                          ),
                        )
                      else
                        for (final comment in comments)
                          ForumCommentTile(comment: comment),
                    ],
                  ),
                ),
                _commentBar(repository),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _postHeader(ForumRepository repository) {
    // 只朗读昵称与提问/回答内容，跳过时间、版块与底部操作区
    return ElderCareBlock(
      readText:
          '${widget.post.author}。${widget.post.title}。${widget.post.content}',
      child: _postHeaderCard(repository),
    );
  }

  Widget _postHeaderCard(ForumRepository repository) {
    final post = widget.post;
    final avatarText = post.author.isEmpty
        ? '?'
        : String.fromCharCode(post.author.runes.first);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    avatarText,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    post.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    forumTimeText(post.createdAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textHint,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              post.title,
              style: const TextStyle(
                fontSize: 17,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              post.content,
              style: const TextStyle(
                fontSize: 14,
                height: 1.6,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        post.section,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textHint,
                        ),
                      ),
                    ),
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => repository.toggleLike(post),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          post.likes > 0
                              ? Icons.favorite
                              : Icons.favorite_border,
                          size: 16,
                          color: post.likes > 0
                              ? AppColors.accent
                              : AppColors.textHint,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${post.likes}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _toggleFavorite(repository),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          repository.isFavorite(post)
                              ? Icons.bookmark
                              : Icons.bookmark_border,
                          size: 16,
                          color: repository.isFavorite(post)
                              ? AppColors.accent
                              : AppColors.textHint,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          repository.isFavorite(post) ? '已收藏' : '收藏',
                          style: TextStyle(
                            fontSize: 12,
                            color: repository.isFavorite(post)
                                ? AppColors.accent
                                : AppColors.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _commentBar(ForumRepository repository) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(color: AppColors.surfaceVariant),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      minLines: 1,
                      maxLines: 3,
                      maxLength: 300,
                      buildCounter: (context,
                              {required currentLength,
                              required isFocused,
                              required maxLength}) =>
                          null,
                      onChanged: (value) {
                        final canSend = value.trim().isNotEmpty;
                        if (canSend != _canSend) {
                          setState(() => _canSend = canSend);
                        }
                      },
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: '写下你的评论…',
                        hintStyle: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textHint,
                        ),
                        isDense: true,
                        filled: true,
                        fillColor: AppColors.surfaceVariant,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: '表情',
                    onPressed: _toggleEmojiPanel,
                    icon: Icon(
                      _showEmojiPanel
                          ? Icons.emoji_emotions
                          : Icons.emoji_emotions_outlined,
                      size: 26,
                      color: _showEmojiPanel
                          ? AppColors.primary
                          : AppColors.textHint,
                    ),
                  ),
                  ForumVoiceButton(
                    controller: _controller,
                    recognizer: widget.voiceRecognizer,
                  ),
                  const SizedBox(width: 4),
                  IconButton.filled(
                    tooltip: '发送评论',
                    onPressed: _canSend ? () => _send(repository) : null,
                    icon: const Icon(Icons.send, size: 18),
                  ),
                ],
              ),
            ),
            if (_showEmojiPanel) _emojiPanel(),
          ],
        ),
      ),
    );
  }

  /// 表情面板：点击插入到光标位置
  Widget _emojiPanel() {
    return Container(
      height: 168,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.surfaceVariant)),
      ),
      child: GridView.count(
        crossAxisCount: 8,
        padding: EdgeInsets.zero,
        children: [
          for (final emoji in _commentEmojis)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _insertEmoji(emoji),
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 22)),
              ),
            ),
        ],
      ),
    );
  }
}
