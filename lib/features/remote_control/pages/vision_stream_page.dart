import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/vision_stream_service.dart';

/// 无人机视觉板图传页面（实时画面 + 拍照）
class VisionStreamPage extends StatefulWidget {
  const VisionStreamPage({super.key});

  @override
  State<VisionStreamPage> createState() => _VisionStreamPageState();
}

class _VisionStreamPageState extends State<VisionStreamPage> {
  final VisionStreamService _service = VisionStreamService();
  static const _galleryChannel = MethodChannel('com.huhuashizhe/gallery');

  @override
  void initState() {
    super.initState();
    _service.start();
    _service.photoNotifier.addListener(_onPhoto);
  }

  @override
  void dispose() {
    _service.photoNotifier.removeListener(_onPhoto);
    _service.dispose();
    super.dispose();
  }

  Uint8List? _lastPhoto;

  void _onPhoto() {
    final jpg = _service.photoNotifier.value;
    if (jpg == null || jpg == _lastPhoto) return;
    _lastPhoto = jpg;
    _saveToGallery(jpg);
  }

  Future<void> _saveToGallery(Uint8List jpg) async {
    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/vision_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(path).writeAsBytes(jpg);
      await _galleryChannel.invokeMethod('saveImageToGallery', {
        'path': path,
        'displayName': '视觉板_${DateTime.now().millisecondsSinceEpoch}.jpg',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('照片已保存到相册'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('无人机图传'),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: _service.streamingNotifier,
            builder: (_, streaming, __) => IconButton(
              icon: Icon(streaming ? Icons.stop_circle_outlined : Icons.play_circle_outline),
              tooltip: streaming ? '停止图传' : '开始图传',
              onPressed: () => streaming ? _service.stop() : _service.start(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.photo_camera_outlined),
            tooltip: '高清拍照',
            onPressed: () => _service.requestSnapshot(),
          ),
        ],
      ),
      body: Column(
        children: [
          // 状态栏
          Container(
            width: double.infinity,
            color: const Color(0xFF1A1A1F),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.videocam, size: 15, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: ValueListenableBuilder<String>(
                    valueListenable: _service.statusNotifier,
                    builder: (_, s, __) => Text(
                      '视觉板 192.168.4.2:8889 · $s',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ),
                ValueListenableBuilder<int>(
                  valueListenable: _service.fpsNotifier,
                  builder: (_, fps, __) => Text(
                    '$fps fps',
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          // 画面区
          Expanded(
            child: Center(
              child: ValueListenableBuilder<Uint8List?>(
                valueListenable: _service.frameNotifier,
                builder: (_, frame, __) {
                  if (frame == null) {
                    return const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.satellite_alt, size: 48, color: Colors.white24),
                        SizedBox(height: 12),
                        Text(
                          '等待视觉板画面...\n\n请确认：\n1. 飞控已开机（热点 HuHuaShiZhe-Drone）\n2. 视觉板已上电（自动入网）\n3. 手机已连接同一热点',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.6),
                        ),
                      ],
                    );
                  }
                  return Image.memory(
                    frame,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
