import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// APK安装器（通过原生平台通道调用系统安装）
class ApkInstaller {
  static const _channel = MethodChannel('com.huhuashizhe/apk_installer');

  /// 获取适合下载APK的目录（外部存储，系统安装器可访问）
  static Future<String> getDownloadDir() async {
    try {
      // 优先使用path_provider获取外部存储目录（比MethodChannel更可靠）
      final dir = await getExternalStorageDirectory();
      if (dir != null) return dir.path;
    } catch (_) {}
    // 回退到系统临时目录
    return Directory.systemTemp.path;
  }

  /// 安装指定路径的APK文件
  static Future<bool> install(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;

      if (Platform.isAndroid) {
        return await _channel.invokeMethod<bool>('installApk', {'path': filePath}) ?? false;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}
