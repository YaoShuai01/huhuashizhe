import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// 帖子配图：兼容服务器 URL 与内存数据源的 data URI
class ForumPostImage extends StatelessWidget {
  const ForumPostImage({
    super.key,
    required this.url,
    this.aspectRatio = 16 / 9,
    this.borderRadius = 10,
  });

  final String url;
  final double aspectRatio;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: _buildImage(),
      ),
    );
  }

  Widget _buildImage() {
    if (url.startsWith('data:')) {
      try {
        final bytes = base64Decode(url.substring(url.indexOf(',') + 1));
        return Image.memory(bytes, fit: BoxFit.cover);
      } catch (_) {
        return _error();
      }
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const ColoredBox(
          color: AppColors.surfaceVariant,
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) => _error(),
    );
  }

  Widget _error() {
    return const ColoredBox(
      color: AppColors.surfaceVariant,
      child: Center(
        child: Icon(Icons.broken_image_outlined, color: AppColors.textHint),
      ),
    );
  }
}
