import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../data/forum_repository.dart';
import '../forum_scope.dart';
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
  });

  final String? initialSection;

  /// 外部注入的数据源，为空时取 ForumScope 或默认实现
  final ForumRepository? repository;

  /// 外部注入的语音识别实现，为空时使用系统语音识别
  final ForumVoiceRecognizer? voiceRecognizer;

  @override
  State<ForumComposePage> createState() => _ForumComposePageState();
}

class _ForumComposePageState extends State<ForumComposePage> {
  static const int _titleMaxLength = 40;
  static const int _contentMaxLength = 1000;

  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();

  String? _section;

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

  void _publish() {
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

    _repository.publish(section: section, title: title, content: content);
    final messenger = ScaffoldMessenger.of(context);
    context.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('发布成功')));
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
            onPressed: _publish,
            child: const Text(
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
            const Text(
              '发布后所有用户可见，请遵守社区版规，勿发布广告与违规内容。',
              style: TextStyle(fontSize: 12, color: AppColors.textHint),
            ),
          ],
        ),
      ),
    );
  }
}
