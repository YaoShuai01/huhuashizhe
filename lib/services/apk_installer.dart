import 'dart:io';
import 'package:flutter/services.dart';

/// APK安装器（通过原生平台通道调用系统安装）
class ApkInstaller {
  static const _channel = MethodChannel('com.huhuashizhe/apk_installer');

  /// 安装指定路径的APK文件
  static Future<bool> install(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;

      if (Platform.isAndroid) {
        return await _channel.invokeMethod<bool>('installApk', {'path': filePath}) ?? false;
      } else if (Platform.isIOS) {
        // iOS无法直接安装APK，跳转到App Store或网页
        return false;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}
