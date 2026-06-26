import 'dart:async';
import 'package:dio/dio.dart';

import '../core/constants/app_version.dart' show appVersion;
import 'apk_installer.dart';
const String _githubReleaseApi = 'https://api.github.com/repos/YaoShuai01/huhuashizhe/releases/latest';

class UpdateInfo {
  final String versionName;
  final int versionCode;
  final String releaseNotes;
  final String downloadUrl;
  final DateTime publishedAt;

  const UpdateInfo({
    required this.versionName,
    required this.versionCode,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.publishedAt,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    final assets = json['assets'] as List<dynamic>? ?? [];
    final downloadUrl = assets.isNotEmpty
        ? (assets[0]['browser_download_url'] as String? ?? '')
        : '';

    return UpdateInfo(
      versionName: (json['tag_name'] as String?)?.replaceFirst('v', '') ?? '',
      versionCode: _parseVersionCode(json['tag_name'] as String? ?? ''),
      releaseNotes: json['body'] as String? ?? '',
      downloadUrl: downloadUrl,
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  static int _parseVersionCode(String tag) {
    final clean = tag.replaceFirst('v', '');
    final parts = clean.split('.');
    if (parts.length >= 3) {
      return int.parse(parts[0]) * 10000 +
          int.parse(parts[1]) * 100 +
          int.parse(parts[2]);
    }
    return 0;
  }
}

/// 检查更新结果（区分三种情况）
enum CheckResult { hasUpdate, upToDate, noRelease, networkError }

class UpdateService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));

  String _downloadPath = '';

  /// 检查是否有新版本，返回 (结果, 更新信息)
  Future<(CheckResult, UpdateInfo?)> checkForUpdate() async {
    try {
      final response = await _dio.get(_githubReleaseApi);
      if (response.statusCode == 200 && response.data != null) {
        final info = UpdateInfo.fromJson(response.data);
        if (_isNewerVersion(info.versionName)) {
          return (CheckResult.hasUpdate, info);
        } else {
          return (CheckResult.upToDate, info); // 有Release但版本相同或更低
        }
      } else if (response.statusCode == 404) {
        // 仓库还没有任何 Release
        return (CheckResult.noRelease, null);
      }
      return (CheckResult.noRelease, null);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError) {
        return (CheckResult.networkError, null);
      }
      return (CheckResult.noRelease, null);
    } catch (e) {
      return (CheckResult.networkError, null);
    }
  }

  bool _isNewerVersion(String remoteVersion) {
    final remoteParts = remoteVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final localParts = appVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (var i = 0; i < 3; i++) {
      final remote = i < remoteParts.length ? remoteParts[i] : 0;
      final local = i < localParts.length ? localParts[i] : 0;
      if (remote > local) return true;
      if (remote < local) return false;
    }
    return false;
  }

  Future<bool> downloadUpdate(
    String url,
    void Function(int received, int total) onProgress,
  ) async {
    try {
      final dir = await ApkInstaller.getDownloadDir();
      final filePath = '$dir/huhuashizhe_update.apk';
      _downloadPath = filePath;

      await _dio.download(
        url,
        filePath,
        onReceiveProgress: onProgress,
        options: Options(receiveTimeout: const Duration(minutes: 10)),
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  /// 获取下载文件路径
  String get downloadPath => _downloadPath;

  /// 安装已下载的APK文件（调用系统安装器）
  Future<bool> installUpdate(String filePath) async {
    return await ApkInstaller.install(filePath);
  }
}
