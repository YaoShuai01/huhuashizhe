import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

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
  static const int _maxImages = 3;

  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final List<_PickedImage> _images = [];

  String? _section;
  bool _submitting = false;
  String _submittingLabel = 'AI 审核中，请稍候…';

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

  Future<void> _addImage() async {
    if (_images.length >= _maxImages) return;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('拍照'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1280,
        imageQuality: 70,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _images.add(
          _PickedImage(bytes: bytes, extension: _extensionOf(file.name)),
        );
      });
    } catch (_) {
      if (mounted) _toast('选择图片失败，请重试');
    }
  }

  String _extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    return const {'jpg', 'jpeg', 'png', 'webp'}.contains(ext) ? ext : 'jpg';
  }

  void _removeImage(int index) {
    setState(() => _images.removeAt(index));
  }

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
    await _finishPublish(
      section: section,
      title: title,
      content: content,
      pendingReview: result.needsManualReview,
    );
  }

  Future<void> _finishPublish({
    required String section,
    required String title,
    required String content,
    bool pendingReview = false,
  }) async {
    setState(() {
      _submitting = true;
      _submittingLabel = _images.isEmpty ? 'AI 审核中，请稍候…' : '正在上传图片…';
    });
    try {
      final imageUrls = <String>[];
      for (final image in _images) {
        imageUrls.add(
          await _repository.uploadImage(
            bytes: image.bytes,
            extension: image.extension,
          ),
        );
      }
      await _repository.publish(
        section: section,
        title: title,
        content: content,
        pendingReview: pendingReview,
        images: imageUrls,
      );
    } on ForumException catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _toast(error.message);
      return;
    }
    if (!mounted) return;
    setState(() => _submitting = false);
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

  Widget _imagePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '配图（选填）',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(width: 6),
            Text(
              '${_images.length}/$_maxImages',
              style: const TextStyle(fontSize: 12, color: AppColors.textHint),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < _images.length; i++) _thumbnail(i),
            if (_images.length < _maxImages) _addImageTile(),
          ],
        ),
      ],
    );
  }

  Widget _thumbnail(int index) {
    return SizedBox(
      width: 76,
      height: 76,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(_images[index].bytes, fit: BoxFit.cover),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _removeImage(index),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 13, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addImageTile() {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: _addImage,
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.textHint.withValues(alpha: 0.3),
          ),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_a_photo_outlined,
              size: 20,
              color: AppColors.textHint,
            ),
            SizedBox(height: 4),
            Text(
              '添加图片',
              style: TextStyle(fontSize: 10, color: AppColors.textHint),
            ),
          ],
        ),
      ),
    );
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
              maxLines: 14,
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
            const SizedBox(height: 12),
            _imagePicker(),
            const SizedBox(height: 8),
            const Text(
              '发布后所有用户可见，请遵守社区版规，勿发布广告与违规内容。',
              style: TextStyle(fontSize: 12, color: AppColors.textHint),
            ),
            if (_submitting) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _submittingLabel,
                    style: const TextStyle(
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

/// 待上传的本地图片
class _PickedImage {
  const _PickedImage({required this.bytes, required this.extension});

  final Uint8List bytes;
  final String extension;
}
