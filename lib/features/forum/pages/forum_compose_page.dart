import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../data/forum_repository.dart';
import '../forum_scope.dart';
import '../services/forum_moderation_service.dart';
import '../services/forum_voice_input.dart';
import '../widgets/forum_back_button.dart';
import '../widgets/forum_responsive_body.dart';
import '../widgets/forum_section_picker.dart';
import '../widgets/forum_voice_button.dart';

/// 发帖页
class ForumComposePage extends StatefulWidget {
  const ForumComposePage({
    super.key,
    this.initialSection,
    this.repository,
    this.voiceRecognizer,
    this.moderationService,
  });

  final String? initialSection;

  /// 外部注入的数据源，为空时取 ForumScope 或默认实现
  final ForumRepository? repository;

  /// 外部注入的语音识别实现，为空时使用系统语音识别
  final ForumVoiceRecognizer? voiceRecognizer;

  /// 外部注入的内容初审实现，为空时使用 AI 初审
  final ForumModerationService? moderationService;

  @override
  State<ForumComposePage> createState() => _ForumComposePageState();
}

class _ForumComposePageState extends State<ForumComposePage> {
  static const int _titleMaxLength = 40;
  static const int _contentMaxLength = 1000;

  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();

  String? _section;
  bool _submitting = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  ForumRepository get _repository =>
      widget.repository ?? ForumScope.of(context);

  /// 初始版块：外部指定值 > 首个可用版块
  String? _resolveSection(List<String> sections) {
    if (sections.isEmpty) return null;
    if (_section != null && sections.contains(_section)) return _section;
    if (widget.initialSection != null &&
        sections.contains(widget.initialSection)) {
      return widget.initialSection;
    }
    return sections.first;
  }

  ForumModerationService get _moderator =>
      widget.moderationService ?? defaultForumModerationService;

  Future<void> _publish() async {
    if (_submitting) return;

    final sections = _repository.sectionTitles;
    final section = _resolveSection(sections);
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();

    if (section == null) {
      _toast('暂无可发布的版块');
      return;
    }
    if (title.isEmpty) {
      _toast('请填写标题');
      return;
    }
    if (content.isEmpty) {
      _toast('请填写正文');
      return;
    }

    // AI 初审：通过即发布，驳回拦截，无法判定转人工复审
    setState(() => _submitting = true);
    final result = await _moderator.review(title: title, content: content);
    if (!mounted) return;
    setState(() => _submitting = false);

    if (result.rejected) {
      await _showRejectDialog(result);
      return;
    }
    _finishPublish(
      section: section,
      title: title,
      content: content,
      pendingReview: result.needsManualReview,
    );
  }

  void _finishPublish({
    required String section,
    required String title,
    required String content,
    bool pendingReview = false,
  }) {
    _repository.publish(
      section: section,
      title: title,
      content: content,
      pendingReview: pendingReview,
    );
    final messenger = ScaffoldMessenger.of(context);
    context.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(pendingReview ? '已提交，人工复审通过后展示' : '发布成功'),
        ),
      );
  }

  Future<void> _showRejectDialog(ForumAuditResult result) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('未通过审核'),
        content: Text(
          '违规类型：${result.violationType}\n\n${result.reason}\n\n请修改后重新发布。',
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

  @override
  Widget build(BuildContext context) {
    final sections = _repository.sectionTitles;
    final section = _resolveSection(sections);

    return Scaffold(
      appBar: AppBar(
        leading: const ForumBackButton(),
        title: const Text('发布帖子'),
        actions: [
          TextButton(
            onPressed: _submitting ? null : _publish,
            child: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.textOnPrimary,
                    ),
                  )
                : const Text(
                    '发布',
                    style: TextStyle(
                      color: AppColors.textOnPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
      body: ForumResponsiveBody(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            ForumSectionPicker(
              sections: sections,
              value: section,
              onChanged: (value) => setState(() => _section = value),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleCtrl,
              maxLength: _titleMaxLength,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                hintText: '标题（$_titleMaxLength 字以内）',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contentCtrl,
              maxLines: 9,
              maxLength: _contentMaxLength,
              decoration: InputDecoration(
                hintText: '正文：描述你的问题、经验或作业情况…',
                alignLabelWithHint: true,
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: ForumVoiceButton(
                    controller: _contentCtrl,
                    recognizer: widget.voiceRecognizer,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
             Text(
              '发布后所有用户可见，请遵守社区版规，勿发布广告与违规内容。',
              style: TextStyle(fontSize: 12, color: context.palette.textHint),
            ),
            if (_submitting) ...[
              const SizedBox(height: 12),
              const Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'AI 审核中，请稍候…',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
