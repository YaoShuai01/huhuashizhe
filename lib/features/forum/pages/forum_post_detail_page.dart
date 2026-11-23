import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/accessibility/elder_care_reader.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/data/auth_session.dart';
import '../data/forum_models.dart';
import '../data/forum_repository.dart';
import '../forum_scope.dart';
import '../services/forum_moderation_service.dart';
import '../widgets/forum_back_button.dart';
import '../widgets/forum_comment_tile.dart';
import '../widgets/forum_post_image.dart';
import '../widgets/forum_responsive_body.dart';
import '../widgets/forum_voice_comment.dart';

/// 帖子详情：查看正文、点赞、收藏与评论
class ForumPostDetailPage extends StatefulWidget {
  const ForumPostDetailPage({
    super.key,
    required this.post,
    this.repository,
    this.moderationService,
  });

  final ForumPost post;

  /// 外部注入的数据源，为空时取 ForumScope 或默认实现
  final ForumRepository? repository;

  /// 外部注入的内容初审实现，为空时使用本地屏蔽词检查
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

  /// 正在回复的评论，为空表示直接评论帖子
  ForumComment? _replyTo;

  @override
  void initState() {
    super.initState();
    // 以输入框内容为准同步发送按钮状态，语音输入等直接改文本也能发送
    _controller.addListener(_syncCanSend);
  }

  bool _commentsRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_commentsRequested) return;
    _commentsRequested = true;
    _loadComments();
  }

  /// 打开详情时从服务器拉取该帖评论
  Future<void> _loadComments() async {
    final repository = widget.repository ?? ForumScope.of(context);
    try {
      await repository.loadComments(widget.post.id);
    } on ForumException catch (error) {
      if (mounted) _toast(error.message);
    }
  }

  /// 下拉刷新：同步帖子数据并重新拉取评论
  Future<void> _refresh(ForumRepository repository) async {
    try {
      await repository.refresh();
      await repository.loadComments(widget.post.id);
    } on ForumException catch (error) {
      if (mounted) _toast(error.message);
    }
  }

  void _syncCanSend() {
    final canSend = _controller.text.trim().isNotEmpty;
    if (canSend != _canSend) {
      setState(() => _canSend = canSend);
    }
  }

  /// 评论常用表情（点击插入正文）
  static const List<String> _commentEmojis = [
    '😀',
    '😁',
    '😂',
    '🤣',
    '😊',
    '😍',
    '🥰',
    '😎',
    '🤔',
    '😅',
    '😭',
    '😢',
    '😡',
    '😴',
    '🤝',
    '🙏',
    '👍',
    '👎',
    '👏',
    '💪',
    '❤️',
    '🔥',
    '🎉',
    '💯',
    '🌱',
    '🌿',
    '🌾',
    '🌻',
    '🚜',
    '🐛',
    '💧',
    '☀️',
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
  }

  @override
  void dispose() {
    _controller.removeListener(_syncCanSend);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send(ForumRepository repository) async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);

    final service = widget.moderationService ?? defaultForumModerationService;
    final ForumAuditResult result;
    try {
      result = await service.review(
        title: '评论：${widget.post.title}',
        content: text,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    if (!mounted) return;

    if (result.rejected) {
      await _showRejectDialog(result);
      return;
    }

    try {
      await repository.addComment(
        post: widget.post,
        content: text,
        replyTo: _replyTo,
      );
    } on ForumException catch (error) {
      if (mounted) _toast(error.message);
      return;
    }
    _controller.clear();
    _focusNode.unfocus();
    if (mounted) setState(() => _replyTo = null);
    if (result.needsManualReview) {
      _toast('评论已提交，人工复审通过后展示');
    }
  }

  /// 点击某条评论的「回复」，输入框切换为该评论的回复模式
  void _startReply(ForumComment comment) {
    setState(() {
      _replyTo = comment;
      _showEmojiPanel = false;
    });
    _focusNode.requestFocus();
  }

  /// 作者可将自己的帖子设为 / 取消精选
  Future<void> _toggleFeatured(ForumRepository repository) async {
    final next = !widget.post.featured;
    try {
      await repository.setFeatured(widget.post, next);
      if (!mounted) return;
      _toast(next ? '已设为精选，将展示在推荐分区' : '已取消精选');
    } on ForumException catch (error) {
      if (mounted) _toast(error.message);
    }
  }

  /// 投诉原因选项
  static const List<String> _reportReasons = [
    '广告或垃圾信息',
    '色情低俗',
    '辱骂攻击',
    '违法违规',
    '其他',
  ];

  /// 投诉帖子或评论：登录后选择原因提交
  Future<void> _report(
    ForumRepository repository, {
    required String targetType,
    required String targetId,
  }) async {
    if (!AuthSession.instance.isLoggedIn) {
      final goLogin = await showDialog<bool>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: const Text('请先登录'),
              content: const Text('登录后才能投诉，是否现在去登录？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('去登录'),
                ),
              ],
            ),
      );
      if (goLogin == true && mounted) context.push('/login');
      return;
    }

    final reason = await showDialog<String>(
      context: context,
      builder:
          (dialogContext) => SimpleDialog(
            title: const Text('选择投诉原因'),
            children: [
              for (final item in _reportReasons)
                SimpleDialogOption(
                  onPressed: () => Navigator.of(dialogContext).pop(item),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(item),
                  ),
                ),
            ],
          ),
    );
    if (reason == null) return;

    try {
      await repository.report(
        targetType: targetType,
        targetId: targetId,
        reason: reason,
      );
      if (mounted) _toast('投诉已提交，我们会尽快处理');
    } on ForumException catch (error) {
      if (mounted) _toast(error.message);
    }
  }

  /// 删除自己的帖子，确认后返回列表
  Future<void> _confirmDeletePost(ForumRepository repository) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('删除帖子'),
            content: const Text('删除后帖子和评论都会消失，且无法恢复。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text(
                  '删除',
                  style: TextStyle(color: AppColors.error),
                ),
              ),
            ],
          ),
    );
    if (confirmed != true) return;

    try {
      await repository.deletePost(widget.post);
    } on ForumException catch (error) {
      if (mounted) _toast(error.message);
      return;
    }
    if (!mounted) return;
    _toast('帖子已删除');
    Navigator.of(context).pop();
  }

  /// 删除自己的评论，其下的回复会一并删除
  Future<void> _confirmDeleteComment(
    ForumRepository repository,
    ForumComment comment,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('删除评论'),
            content: const Text('删除后该评论及其回复都会消失，且无法恢复。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text(
                  '删除',
                  style: TextStyle(color: AppColors.error),
                ),
              ),
            ],
          ),
    );
    if (confirmed != true) return;

    try {
      await repository.deleteComment(comment);
    } on ForumException catch (error) {
      if (mounted) _toast(error.message);
      return;
    }
    if (mounted) _toast('评论已删除');
  }

  Widget _footerAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = AppColors.textHint,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 3),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }

  Future<void> _showRejectDialog(ForumAuditResult result) {
    return showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
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
        content: Text(wasFavorite ? '已取消收藏' : '已收藏，可在「我的 - 我的收藏」查看'),
        duration: const Duration(milliseconds: 1500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository ?? ForumScope.of(context);

    // 监听登录用户变化，资料改昵称后详情页昵称与操作权限立即同步
    return ValueListenableBuilder<AuthUser?>(
      valueListenable: AuthSession.instance.user,
      builder: (context, _, __) => Scaffold(
        appBar: AppBar(
          leading: const ForumBackButton(),
          title: const Text('帖子详情'),
          actions: [
            if (AuthSession.instance.isAdmin)
              AnimatedBuilder(
                animation: repository,
                builder:
                    (context, _) => IconButton(
                      tooltip: widget.post.featured ? '取消精选' : '设为精选',
                      onPressed: () => _toggleFeatured(repository),
                      icon: Icon(
                        widget.post.featured ? Icons.star : Icons.star_border,
                        color: AppColors.textOnPrimary,
                      ),
                    ),
              ),
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
                  child: RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: () => _refresh(repository),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(top: 10, bottom: 10),
                      children: [
                        _postHeader(repository),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                          child: Text(
                            '全部评论 ${comments.length}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: context.palette.textPrimary,
                            ),
                          ),
                        ),
                        if (comments.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Center(
                              child: Text(
                                '还没有评论，来说两句',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: context.palette.textHint,
                                ),
                              ),
                            ),
                          )
                        else
                          for (final comment in comments)
                            ForumCommentTile(
                              comment: comment,
                              onReply: () => _startReply(comment),
                              onReport:
                                  () => _report(
                                    repository,
                                    targetType: 'reply',
                                    targetId: comment.id,
                                  ),
                              onDelete:
                                  AuthSession.instance.isMyUserId(
                                        comment.authorId,
                                      ) ||
                                      AuthSession.instance.isAdmin
                                  ? () => _confirmDeleteComment(
                                    repository,
                                    comment,
                                  )
                                  : null,
                            ),
                      ],
                    ),
                  ),
                ),
                _commentBar(repository),
              ],
            ),
          );
        },
        ),
      ),
    );
  }

  Widget _postHeader(ForumRepository repository) {
    // 只朗读昵称与提问/回答内容，跳过时间、版块与底部操作区
    return ElderCareBlock(
      readText:
          '${AuthSession.instance.displayName(widget.post.author)}。'
          '${widget.post.title}。${widget.post.content}',
      child: _postHeaderCard(repository),
    );
  }

  Widget _postHeaderCard(ForumRepository repository) {
    final post = widget.post;
    final authorName = AuthSession.instance.displayName(post.author);
    final avatarText =
        authorName.isEmpty ? '?' : String.fromCharCode(authorName.runes.first);

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
                    authorName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.palette.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    forumTimeText(post.createdAt),
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
            const SizedBox(height: 12),
            Text(
              post.title,
              style: TextStyle(
                fontSize: 17,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: context.palette.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              post.content,
              style: TextStyle(
                fontSize: 14,
                height: 1.6,
                color: context.palette.textSecondary,
              ),
            ),
            if (post.images.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final url in post.images)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ForumPostImage(url: url),
                ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final label in [
                          '#${post.section}',
                          ...post.tags.map((tag) => '#$tag'),
                        ])
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: context.palette.surfaceVariant,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              label,
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
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => repository.toggleLike(post),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color:
                          repository.isLiked(post)
                              ? AppColors.accent.withValues(alpha: 0.12)
                              : context.palette.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          repository.isLiked(post)
                              ? Icons.favorite
                              : Icons.favorite_border,
                          size: 16,
                          color:
                              repository.isLiked(post)
                                  ? AppColors.accent
                                  : context.palette.textHint,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${post.likes}',
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                repository.isLiked(post)
                                    ? AppColors.accent
                                    : context.palette.textHint,
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
                          color:
                              repository.isFavorite(post)
                                  ? AppColors.accent
                                  : context.palette.textHint,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          repository.isFavorite(post) ? '已收藏' : '收藏',
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                repository.isFavorite(post)
                                    ? AppColors.accent
                                    : context.palette.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                _footerAction(
                  icon: Icons.flag_outlined,
                  label: '投诉',
                  onTap:
                      () => _report(
                        repository,
                        targetType: 'post',
                        targetId: post.id,
                      ),
                ),
                if (AuthSession.instance.isMyUserId(post.authorId) ||
                    AuthSession.instance.isAdmin)
                  _footerAction(
                    icon: Icons.delete_outline,
                    label: '删除',
                    color: AppColors.error,
                    onTap: () => _confirmDeletePost(repository),
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
        decoration: BoxDecoration(
          color: context.palette.surface,
          border: Border(
            top: BorderSide(color: context.palette.surfaceVariant),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyTo != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 6, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '回复 @${AuthSession.instance.displayName(_replyTo!.author)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => _replyTo = null),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: context.palette.textHint,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
                      maxLength: 450,
                      buildCounter:
                          (
                            context, {
                            required currentLength,
                            required isFocused,
                            required maxLength,
                          }) => null,
                      onChanged: (value) {
                        _syncCanSend();
                      },
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText:
                            _replyTo == null
                                ? '写下你的评论…'
                                : '回复 @${AuthSession.instance.displayName(_replyTo!.author)}…',
                        hintStyle: TextStyle(
                          fontSize: 13,
                          color: context.palette.textHint,
                        ),
                        isDense: true,
                        filled: true,
                        fillColor: context.palette.surfaceVariant,
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
                      color:
                          _showEmojiPanel
                              ? AppColors.primary
                              : AppColors.textHint,
                    ),
                  ),
                  ForumVoiceHoldButton(
                    controller: _controller,
                    repository: repository,
                    post: widget.post,
                    replyTo: _replyTo,
                    onSent: () {
                      if (mounted) setState(() => _replyTo = null);
                    },
                  ),
                  const SizedBox(width: 4),
                  IconButton.filled(
                    tooltip: '发送评论',
                    style: IconButton.styleFrom(
                      disabledBackgroundColor: AppColors.primary.withValues(
                        alpha: 0.6,
                      ),
                      disabledForegroundColor: AppColors.textOnPrimary,
                    ),
                    onPressed:
                        (_canSend && !_sending)
                            ? () => _send(repository)
                            : null,
                    icon:
                        _sending
                            ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.textOnPrimary,
                              ),
                            )
                            : const Icon(Icons.send, size: 18),
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
