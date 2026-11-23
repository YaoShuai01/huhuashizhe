import 'dart:typed_data';

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

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

  /// 外部注入的内容初审实现，为空时使用本地屏蔽词检查
  final ForumModerationService? moderationService;

  @override
  State<ForumComposePage> createState() => _ForumComposePageState();
}

class _ForumComposePageState extends State<ForumComposePage> {
  static const int _titleMaxLength = 40;
  static const int _contentMaxLength = 1000;
  static const int _maxImages = 3;
  static const int _maxTags = 3;
  static const int _tagMaxLength = 10;

  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final List<_PickedImage> _images = [];
  final List<String> _tags = [];
  bool _voiceListening = false;

  String? _section;
  bool _submitting = false;
  String _submittingLabel = '内容检查中，请稍候…';

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _tagCtrl.dispose();
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
      builder:
          (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('拍照'),
                  onTap:
                      () => Navigator.of(sheetContext).pop(ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('从相册选择'),
                  onTap:
                      () => Navigator.of(sheetContext).pop(ImageSource.gallery),
                ),
              ],
            ),
          ),
    );
    if (source == null) return;
    if (!await _ensureImagePermission(source)) return;

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

  /// 发送照片前申请相机 / 相册权限
  Future<bool> _ensureImagePermission(ImageSource source) async {
    final permission =
        source == ImageSource.camera
            ? Permission.camera
            : (Platform.isIOS ? Permission.photos : null);
    // Android 相册走系统选择器，由系统按次授权，无需额外申请
    if (permission == null) return true;

    var status = await permission.status;
    if (!status.isGranted) {
      status = await permission.request();
    }
    if (status.isGranted || status.isLimited) return true;

    if (!mounted) return false;
    _toast(
      status.isPermanentlyDenied
          ? (source == ImageSource.camera
              ? '相机权限已被拒绝，请在系统设置中开启'
              : '相册权限已被拒绝，请在系统设置中开启')
          : (source == ImageSource.camera ? '需要相机权限才能拍照' : '需要相册权限才能选择照片'),
    );
    return false;
  }

  String _extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    return const {'jpg', 'jpeg', 'png', 'webp'}.contains(ext) ? ext : 'jpg';
  }

  void _removeImage(int index) {
    setState(() => _images.removeAt(index));
  }

  /// 添加一个附加 #标签
  void _addTag() {
    final raw = _tagCtrl.text.trim().replaceAll('#', '').trim();
    if (raw.isEmpty) return;
    if (raw.length > _tagMaxLength) {
      _toast('单个标签不超过 $_tagMaxLength 个字');
      return;
    }
    if (_tags.contains(raw)) {
      _tagCtrl.clear();
      return;
    }
    if (_tags.length >= _maxTags) {
      _toast('最多添加 $_maxTags 个标签');
      return;
    }
    setState(() {
      _tags.add(raw);
      _tagCtrl.clear();
    });
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

    // 本地屏蔽词检查：命中词库直接驳回，否则立即发布
    setState(() => _submitting = true);
    final result = await _moderator.review(
      title: title,
      content: [content, ..._tags.map((tag) => '#$tag')].join('\n'),
    );
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
      tags: _tags,
      pendingReview: result.needsManualReview,
    );
  }

  Future<void> _finishPublish({
    required String section,
    required String title,
    required String content,
    required List<String> tags,
    bool pendingReview = false,
  }) async {
    setState(() {
      _submitting = true;
      _submittingLabel = _images.isEmpty ? '内容检查中，请稍候…' : '正在上传图片…';
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
        tags: tags,
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
        SnackBar(content: Text(pendingReview ? '已提交，人工复审通过后展示' : '发布成功')),
      );
  }

  Future<void> _showRejectDialog(ForumAuditResult result) {
    return showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
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

  /// 弹窗输入一个附加 #标签
  Future<void> _showAddTagDialog() async {
    _tagCtrl.clear();
    final tag = await showDialog<String>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('添加 #标签'),
            content: TextField(
              controller: _tagCtrl,
              autofocus: true,
              maxLength: _tagMaxLength,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(hintText: '例如：水稻、病虫害'),
              onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(_tagCtrl.text),
                child: const Text('添加'),
              ),
            ],
          ),
    );
    if (tag == null) return;
    _tagCtrl.text = tag;
    _addTag();
  }

  /// 语音识别写入正文后，若标题为空则用第一句话自动补全标题
  void _onVoiceText(String text) {
    if (_titleCtrl.text.trim().isNotEmpty) return;
    final firstLine = text.split(RegExp(r'[。！？!?\n]')).first.trim();
    if (firstLine.isEmpty) return;
    _titleCtrl.text =
        firstLine.length > 20 ? firstLine.substring(0, 20) : firstLine;
  }

  Widget _voicePostBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          ForumVoiceButton(
            controller: _contentCtrl,
            recognizer: widget.voiceRecognizer,
            iconSize: 26,
            onText: _onVoiceText,
            onListeningChanged:
                (listening) => setState(() => _voiceListening = listening),
          ),
          const ForumVoiceDialectSelector(),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              _voiceListening ? '正在聆听，请说出帖子内容，再次点击结束' : '语音发帖：点击麦克风，说出内容自动转文字',
              style: TextStyle(
                fontSize: 12,
                color: _voiceListening ? AppColors.error : AppColors.textHint,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tagEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '附加 #标签（选填）',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${_tags.length}/$_maxTags',
              style: const TextStyle(fontSize: 12, color: AppColors.textHint),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in _tags)
              InputChip(
                label: Text('#$tag'),
                onDeleted: () => setState(() => _tags.remove(tag)),
                backgroundColor: AppColors.surface,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                labelStyle: const TextStyle(
                  fontSize: 13,
                  color: AppColors.primary,
                ),
              ),
            if (_tags.length < _maxTags)
              ActionChip(
                avatar: const Icon(
                  Icons.add,
                  size: 16,
                  color: AppColors.primary,
                ),
                label: const Text('添加标签'),
                onPressed: _showAddTagDialog,
                backgroundColor: AppColors.surface,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                labelStyle: const TextStyle(
                  fontSize: 13,
                  color: AppColors.primary,
                ),
              ),
          ],
        ),
      ],
    );
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
          border: Border.all(color: AppColors.textHint.withValues(alpha: 0.3)),
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
            child:
                _submitting
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
              label: '#标签',
              onChanged: (value) => setState(() => _section = value),
            ),
            const SizedBox(height: 16),
            _tagEditor(),
            const SizedBox(height: 16),
            _voicePostBar(),
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
