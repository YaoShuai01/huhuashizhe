import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

/// 全屏大图查看器：双指缩放、拖动平移、点击叉号关闭
class ZoomableImageViewer extends StatelessWidget {
  final Uint8List imageBytes;
  final String title;

  const ZoomableImageViewer({
    super.key,
    required this.imageBytes,
    this.title = '',
  });

  /// 静态方法打开大图查看
  static Future<void> show(
    BuildContext context, {
    required Uint8List imageBytes,
    String title = '',
  }) {
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => ZoomableImageViewer(
          imageBytes: imageBytes,
          title: title,
        ),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: PhotoView(
              imageProvider: MemoryImage(imageBytes),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 3,
              enableRotation: false,
              backgroundDecoration: const BoxDecoration(color: Colors.black),
              loadingBuilder: (_, __) => const Center(
                child: CircularProgressIndicator(color: Colors.white70),
              ),
            ),
          ),
          // 顶部标题
          if (title.isNotEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 16,
              right: 60,
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          // 关闭叉号
          Positioned(
            top: MediaQuery.of(context).padding.top + 4,
            right: 12,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
