import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/app_version.dart' show appVersion;
import 'apk_installer.dart';
const String _githubReleaseApi = 'https://api.github.com/repos/YaoShuai01/huhuashizhe/releases/latest';

/// GitHub 下载加速前缀（国内直连 release 文件服务器经常超时，按顺序回退）
const List<String> _downloadMirrors = [
  'https://ghfast.top/',
  'https://ghproxy.net/',
  'https://gh-proxy.com/',
];

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
    // 只取 .apk 资源，避免误选其他附件
    String downloadUrl = '';
    for (final a in assets) {
      final name = (a['name'] as String? ?? '').toLowerCase();
      final url = a['browser_download_url'] as String? ?? '';
      if (name.endsWith('.apk') && url.isNotEmpty) {
        downloadUrl = url;
        break;
      }
    }

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
      } else if (response.statusCode == 403) {
        // GitHub API 限流 (60次/小时)，应提示用户稍后重试
        return (CheckResult.networkError, null);
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
      if (e.type == DioExceptionType.badResponse) {
        final statusCode = e.response?.statusCode;
        if (statusCode == 403) {
          return (CheckResult.networkError, null);
        }
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

  /// 上次下载失败的原因（供UI提示排查）
  String lastError = '';

  /// 并行探测各通道，返回最先成功响应的URL（竞速选最快通道）
  ///
  /// 之前顺序回退：镜像挂了就白白等超时，下载前排队很久。
  /// 现在所有通道同时发 HEAD 请求，谁先响应 200 就用谁，全部失败返回 null。
  Future<String?> _probeFastest(List<String> candidates) async {
    String? fastest;
    await Future.wait(candidates.map((source) async {
      try {
        final resp = await _dio.head(
          source,
          options: Options(
            sendTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 5),
            followRedirects: true,
          ),
        );
        if (resp.statusCode == 200 && fastest == null) {
          fastest = source;
        }
      } catch (_) {
        // 该通道不可用，忽略
      }
    }));
    return fastest;
  }

  /// 下载更新包：并行竞速选最快通道 + 断点续传 + 断网自动续传重试
  ///
  /// - 半包文件按 release 版本命名（vX.Y.Z_update.apk.part），断网/切后台后
  ///   再次下载时从已完成的字节续传，不再从头来过
  /// - 服务器不支持 Range 时自动退回整包下载
  /// - 全部通道失败时保留 .part 文件供下次续传，APK 下载完成才落地正式文件名
  Future<bool> downloadUpdate(
    String url,
    void Function(int received, int total) onProgress,
  ) async {
    lastError = '';
    final dir = await ApkInstaller.getDownloadDir();
    final filePath = '$dir/huhuashizhe_update.apk';
    _downloadPath = filePath;

    // 半包按版本命名：不同版本的残留自然失效，同名残留就是可续传的
    final tagMatch = RegExp(r'/download/(v[\d.]+)/').firstMatch(url);
    final tag = tagMatch?.group(1) ?? 'unknown';
    final partPath = '$dir/${tag}_update.apk.part';
    // 清掉其他版本的过期残留
    final dirEntity = Directory(dir);
    if (await dirEntity.exists()) {
      await for (final e in dirEntity.list()) {
        if (e is File && e.path.endsWith('.part') && e.path != partPath) {
          try {
            await e.delete();
          } catch (_) {}
        }
      }
    }

    // 镜像 + 直连全部候选，竞速排序
    final all = <String>[
      for (final prefix in _downloadMirrors) '$prefix$url',
      url,
    ];
    final fastest = await _probeFastest(all);
    final candidates = fastest == null ? all : [fastest, ...all.where((c) => c != fastest)];
    debugPrint('[Update] 竞速通道: ${fastest ?? '全部探测失败，按原顺序回退'}');

    for (var i = 0; i < candidates.length; i++) {
      final source = candidates[i];
      // 本通道最多重试4次，断点续传从.part接着下
      for (var attempt = 0; attempt < 4; attempt++) {
        final part = File(partPath);
        var base = 0;
        if (await part.exists()) base = await part.length();
        if (base > 0) {
          debugPrint('[Update] 断点续传：已下载 $base 字节（通道${i + 1} 第${attempt + 1}次）');
          onProgress(base, base); // 先把已有进度显示出来
        }

        IOSink? sink;
        try {
          final headers = <String, dynamic>{
            if (base > 0) 'range': 'bytes=$base-',
          };
          final resp = await _dio.get<ResponseBody>(
            source,
            options: Options(
              responseType: ResponseType.stream,
              headers: headers,
              receiveTimeout: const Duration(seconds: 30), // 数据块间隔超时即断流
              followRedirects: true,
              // 416=范围超出文件末尾（可能已下完），单独处理
              validateStatus: (s) => s != null && (s == 200 || s == 206 || s == 416),
            ),
          );

          final status = resp.statusCode ?? 0;
          if (status == 416) {
            // 服务器认为范围不对：如果文件大小合理，视为已下载完成
            final size = await part.length();
            if (size > 1024 * 1024) {
              await part.rename(filePath);
              debugPrint('[Update] Range 416，按已完整处理（$size 字节）');
              return true;
            }
            // 残留异常，删掉从头下
            await part.delete();
            base = 0;
            continue;
          }

          // 206=断点续传成功；200=服务器不支持Range，必须从头写
          final resumed = status == 206 && base > 0;
          if (!resumed && base > 0) {
            debugPrint('[Update] 服务器不支持断点，从头下载');
            onProgress(0, 1);
          }
          final startAt = resumed ? base : 0;

          final remoteTotal =
              int.tryParse(resp.headers.value('content-length') ?? '') ?? 0;
          final grandTotal = remoteTotal > 0 ? startAt + remoteTotal : 0;

          sink = part.openWrite(mode: resumed ? FileMode.append : FileMode.write);
          var received = 0;
          await for (final chunk in resp.data!.stream) {
            sink.add(chunk);
            received += chunk.length;
            if (grandTotal > 0) {
              onProgress(startAt + received, grandTotal);
            }
          }
          await sink.flush();
          await sink.close();
          sink = null;

          final size = await part.length();
          if (size < 1024 * 1024) {
            throw Exception('下载文件过小($size 字节)');
          }
          // 完成：半包转正
          await part.rename(filePath);
          debugPrint('[Update] 下载完成（${resumed ? '含续传' : '整包'}，$size 字节，通道${i + 1}）');
          return true;
        } on DioException catch (e) {
          lastError = e.message ?? e.toString();
          debugPrint('[Update] 下载中断(${e.type})，.part已保留待续传');
          await Future.delayed(Duration(seconds: 1 + attempt));
          // 循环继续：重新计算.part长度续传
        } catch (e) {
          lastError = e.toString();
          debugPrint('[Update] 通道${i + 1}失败: $e');
          break; // 非网络错误，换下一个通道
        } finally {
          await sink?.flush();
          await sink?.close();
        }
      }
    }
    // 全部失败：保留.part，下次进入下载时自动续传
    return false;
  }

  /// 获取下载文件路径
  String get downloadPath => _downloadPath;

  /// 安装已下载的APK文件（调用系统安装器）
  Future<bool> installUpdate(String filePath) async {
    return await ApkInstaller.install(filePath);
  }
}
