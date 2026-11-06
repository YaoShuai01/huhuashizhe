import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/growth_record_store.dart';
import 'zoomable_image_viewer.dart';

/// 预警详情卡片：顶部问题描述固定，下方3列采集缩略图可滚动
class WarningDetailCard extends StatefulWidget {
  final ProblemGroup problem;
  final Future<Uint8List?> Function(String path) imageLoader;

  const WarningDetailCard({
    super.key,
    required this.problem,
    required this.imageLoader,
  });

  @override
  State<WarningDetailCard> createState() => _WarningDetailCardState();
}

class _WarningDetailCardState extends State<WarningDetailCard> {
  final Map<String, Uint8List?> _thumbCache = {};

  @override
  Widget build(BuildContext context) {
    final problem = widget.problem;
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.68,
          child: Column(
            children: [
              // 顶部：问题描述区域（固定）
              Container(
                color: AppColors.primary.withValues(alpha: 0.08),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Icon(Icons.warning_amber_rounded,
                              color: AppColors.error, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            problem.zhName,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      problem.desc,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '共采集 ${problem.imagePaths.length} 张 · 最高置信度 '
                      '${(problem.maxConfidence * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textHint),
                    ),
                  ],
                ),
              ),
              // 分隔线
              const Divider(height: 1, thickness: 1),
              // 采集图片：3列网格，可上下滚动
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(10),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: problem.imagePaths.length,
                  itemBuilder: (context, index) {
                    final path = problem.imagePaths[index];
                    final bytes = _thumbCache[path];
                    if (bytes == null && !_thumbCache.containsKey(path)) {
                      _loadThumb(path);
                    }
                    return GestureDetector(
                      onTap: bytes != null
                          ? () => ZoomableImageViewer.show(
                                context,
                                imageBytes: bytes,
                                title: '${problem.zhName} · 采集图 ${index + 1}',
                              )
                          : null,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: bytes != null
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
                      ),
                    );
                  },
                ),
              ),
              // 底部返回按钮
              Container(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 8,
                  bottom: MediaQuery.of(context).padding.bottom > 0
                      ? MediaQuery.of(context).padding.bottom
                      : 12,
                ),
                decoration: const BoxDecoration(color: Colors.white),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('返回'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadThumb(String path) async {
    final bytes = await widget.imageLoader(path);
    if (mounted) {
      setState(() => _thumbCache[path] = bytes);
    }
  }
}

/// 打开预警详情卡片
Future<void> showWarningDetailCard(
  BuildContext context, {
  required ProblemGroup problem,
  required Future<Uint8List?> Function(String path) imageLoader,
}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    builder: (_) => WarningDetailCard(problem: problem, imageLoader: imageLoader),
  );
}
