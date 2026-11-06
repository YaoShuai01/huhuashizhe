import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/ai_suggestion_worker.dart';
import '../../../services/growth_record_store.dart';
import '../../../services/ys_image_store.dart';
import '../widgets/zoomable_image_viewer.dart';

/// 生长检测记录详情页
///
/// - 修改记录名称（时间字段不可修改）
/// - 删除记录
/// - 问题描述展示 + 全部采集图像缩略图（相册式交互：点看大图、下载存相册）
/// - AI处理建议 + 追问对话（历史永久保留）
class GrowthRecordDetailPage extends StatefulWidget {
  final String recordId;

  const GrowthRecordDetailPage({super.key, required this.recordId});

  @override
  State<GrowthRecordDetailPage> createState() => _GrowthRecordDetailPageState();
}

class _GrowthRecordDetailPageState extends State<GrowthRecordDetailPage> {
  final GrowthRecordStore _store = GrowthRecordStore();
  final YsImageStore _ysStore = YsImageStore();
  final Map<String, Uint8List?> _thumbCache = {};
  final ScrollController _chatScroll = ScrollController();
  GrowthRecord? _record;

  @override
  void initState() {
    super.initState();
    _record = _store.getById(widget.recordId);
  }

  @override
  void dispose() {
    _chatScroll.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() => _record = _store.getById(widget.recordId));
  }

  // ==================== 名称编辑 / 删除 ====================

  Future<void> _rename() async {
    final record = _record!;
    final controller = TextEditingController(text: record.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改记录名称'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: '请输入记录名称'),
            ),
            const SizedBox(height: 8),
            Text('时间：${record.timeText}（不可修改）',
                style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && newName != record.name) {
      _store.rename(record.id, newName);
      _reload();
    }
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除确认'),
        content: Text('确定删除记录"${_record!.name}"吗？\n对应的全部采集图片将一并删除，删除后无法恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final paths =
                  _record!.problems.expand((p) => p.imagePaths).toList();
              await _ysStore.deleteRecordImages(_record!.id, paths);
              _store.delete(_record!.id);
              if (mounted) Navigator.pop(context, true);
            },
            child: const Text('删除', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  // ==================== 图片交互 ====================

  Future<Uint8List?> _loadImageBytes(String path) async {
    if (_thumbCache.containsKey(path)) return _thumbCache[path];
    try {
      final bytes = await _ysStore.readImageBytes(path);
      _thumbCache[path] = bytes;
      return bytes;
    } catch (e) {
      debugPrint('[GrowthDetail] 解密失败: $e');
      _thumbCache[path] = null;
      return null;
    }
  }

  Future<void> _downloadImage(String path) async {
    final ok = await _ysStore.exportToGallery(path);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '已保存到系统相册（Pictures/护花使者）' : '保存失败，请重试'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ==================== AI建议 ====================

  void _showAiDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AiSuggestionDialog(
        record: _record!,
        onReload: _reload,
        chatScroll: _chatScroll,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final record = _record;
    if (record == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('记录详情')),
        body: const Center(child: Text('记录不存在')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(record.name, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(icon: const Icon(Icons.edit), onPressed: _rename),
          IconButton(
              icon: const Icon(Icons.delete_outline), onPressed: _confirmDelete),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 元信息
          Text(
            '${record.locationName} · ${record.timeText}',
            style: const TextStyle(fontSize: 12, color: AppColors.textHint),
          ),
          const SizedBox(height: 12),
          // 各问题卡片
          ...record.problems.map(_buildProblemCard),
          if (record.problems.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('本次未识别到作物问题，生长状况良好。',
                  style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            ),
          const SizedBox(height: 16),
          // AI建议入口
          _buildAiCard(record),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildProblemCard(ProblemGroup problem) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                const Icon(Icons.pest_control, color: AppColors.error, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(problem.zhName,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Text(problem.desc,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary, height: 1.4)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Text('共 ${problem.imagePaths.length} 张采集图',
                style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
          ),
          // 缩略图网格（相册式交互）
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
                childAspectRatio: 0.8,
              ),
              itemCount: problem.imagePaths.length,
              itemBuilder: (context, index) =>
                  _buildThumb(problem.imagePaths[index], problem.zhName, index),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumb(String path, String title, int index) {
    final bytes = _thumbCache[path];
    if (bytes == null && !_thumbCache.containsKey(path)) {
      _loadImageBytes(path).then((_) => mounted ? setState(() {}) : null);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          bytes != null
              ? Image.memory(bytes, fit: BoxFit.cover)
              : Container(
                  color: AppColors.surfaceVariant,
                  child: const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
          // 底部下载按钮
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.55),
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.download_rounded,
                        color: Colors.white, size: 20),
                    constraints: const BoxConstraints(minWidth: 34, minHeight: 30),
                    padding: EdgeInsets.zero,
                    onPressed: bytes != null ? () => _downloadImage(path) : null,
                  ),
                ],
              ),
            ),
          ),
          // 整体点击 → 大图
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: bytes != null
                    ? () => ZoomableImageViewer.show(
                          context,
                          imageBytes: bytes,
                          title: '$title · ${index + 1}',
                        )
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiCard(GrowthRecord record) {
    final hasAi = record.aiSuggestion != null &&
        record.aiSuggestion!.isNotEmpty &&
        record.chat.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, color: AppColors.accent, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('AI处理建议',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                ),
                if (record.aiPending && record.chat.isEmpty)
                  const Text('生成中/待联网...',
                      style: TextStyle(fontSize: 11, color: AppColors.accent)),
              ],
            ),
          ),
          if (hasAi || record.aiSuggestion != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Text(
                record.chat.isNotEmpty
                    ? '已有${record.chat.length}条对话，点击查看完整对话'
                    : (record.aiSuggestion ?? ''),
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary, height: 1.5),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showAiDialog,
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                label: Text(record.chat.isEmpty ? '查看AI建议' : '查看对话/继续追问'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// AI建议交互对话框：展示建议 + 追问对话（流式），历史永久保留
class _AiSuggestionDialog extends StatefulWidget {
  final GrowthRecord record;
  final VoidCallback onReload;
  final ScrollController chatScroll;

  const _AiSuggestionDialog({
    required this.record,
    required this.onReload,
    required this.chatScroll,
  });

  @override
  State<_AiSuggestionDialog> createState() => _AiSuggestionDialogState();
}

class _AiSuggestionDialogState extends State<_AiSuggestionDialog> {
  final TextEditingController _input = TextEditingController();
  final AiSuggestionWorker _aiWorker = AiSuggestionWorker();
  final GrowthRecordStore _store = GrowthRecordStore();
  late GrowthRecord _record;
  bool _streaming = false;
  String _streamBuffer = '';

  @override
  void initState() {
    super.initState();
    _record = _store.getById(widget.record.id) ?? widget.record;
    // 若建议尚未生成且在线，则立即生成
    if (_record.aiSuggestion == null && !_streaming) {
      _generateSuggestion();
    }
  }

  Future<void> _generateSuggestion() async {
    await _aiWorker.generateFor(_record.id);
    if (mounted) {
      setState(() {
        _record = _store.getById(_record.id) ?? _record;
      });
      widget.onReload();
    }
  }

  Future<void> _send() async {
    final question = _input.text.trim();
    if (question.isEmpty || _streaming) return;
    _input.clear();
    setState(() {
      _streaming = true;
      _streamBuffer = '';
    });
    await for (final chunk in _aiWorker.askFollowUp(_record.id, question)) {
      if (!mounted) return;
      setState(() => _streamBuffer += chunk);
      _scrollChatToBottom();
    }
    if (mounted) {
      setState(() {
        _streaming = false;
        _streamBuffer = '';
        _record = _store.getById(_record.id) ?? _record;
      });
      widget.onReload();
      _scrollChatToBottom();
    }
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.chatScroll.hasClients) {
        widget.chatScroll.animateTo(
          widget.chatScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final history = <Map<String, dynamic>>[];
    if (_record.aiSuggestion != null && _record.aiSuggestion!.isNotEmpty) {
      history.add({'role': 'assistant', 'content': _record.aiSuggestion!});
    }
    history.addAll(_record.chat);
    if (_streaming && _streamBuffer.isNotEmpty) {
      history.add({'role': 'assistant', 'content': '$_streamBuffer▌'});
    }

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 48),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            // 标题栏
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome,
                      color: AppColors.accent, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('AI处理建议',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 22),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 对话历史
            Expanded(
              child: history.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          CircularProgressIndicator(),
                          SizedBox(height: 10),
                          Text('正在生成AI处理建议...',
                              style: TextStyle(
                                  fontSize: 13, color: AppColors.textHint)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: widget.chatScroll,
                      padding: const EdgeInsets.all(14),
                      itemCount: history.length,
                      itemBuilder: (context, index) {
                        final msg = history[index];
                        final isAi = msg['role'] == 'assistant';
                        return _buildBubble(
                          msg['content']?.toString() ?? '',
                          isAi,
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            // 追问输入
            Padding(
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                top: 8,
                bottom: MediaQuery.of(context).viewInsets.bottom > 0
                    ? 8
                    : MediaQuery.of(context).padding.bottom + 8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      decoration: const InputDecoration(
                        hintText: '针对这条建议继续追问...',
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _streaming ? null : _send,
                    icon: const Icon(Icons.send, size: 20),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBubble(String text, bool isAi) {
    return Align(
      alignment: isAi ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.62,
        ),
        decoration: BoxDecoration(
          color: isAi ? AppColors.surfaceVariant : AppColors.primary,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isAi ? 12 : 2),
            bottomRight: Radius.circular(isAi ? 2 : 12),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.5,
            color: isAi ? AppColors.textPrimary : Colors.white,
          ),
        ),
      ),
    );
  }
}
