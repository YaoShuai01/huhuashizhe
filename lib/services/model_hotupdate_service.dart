import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/constants/server_config.dart';
import '../features/model_test/data/model_catalog.dart';
import '../features/model_test/data/model_labels.dart';

/// 模型热更新服务
///
/// 模型清单与二进制都托管在自有阿里云服务器（Tomcat 静态目录 /app/models/），
/// GitHub 仅作兜底通道。
/// App 启动/进入模型测试页时静默检查：对比清单与本地已下载模型，
/// 有新模型就在后台下载，完成后模型下拉列表自动多出对应条目，无需发版更新App。
///
/// 发布新模型的流程：
/// 1. 把 .tflite 和 manifest.json 放到服务器 C:\huhuashizhe\tomcat\webapps\app\models\
/// 2. 打开 http://<服务器IP>:8080/app/models/manifest.json 确认可访问
/// 3. App 联网后自动下载生效
class ModelHotupdateService {
  ModelHotupdateService._();
  static final ModelHotupdateService instance = ModelHotupdateService._();

  static const _repo = 'YaoShuai01/huhuashizhe';
  static const _branch = 'main';

  /// 自有服务器上的模型目录（Tomcat webapps/app/models 静态目录）
  static const _serverModelsBase = '$serverBaseUrl/app/models';

  /// 清单地址：优先自有服务器，GitHub 镜像兜底。
  /// 加时间戳参数绕过缓存，避免刚发布的清单几分钟内看不到。
  static List<String> get _manifestUrls {
    final ts = DateTime.now().millisecondsSinceEpoch;
    const raw =
        'https://raw.githubusercontent.com/$_repo/$_branch/models/manifest.json';
    return [
      '$_serverModelsBase/manifest.json?t=$ts',
      'https://ghproxy.net/$raw?t=$ts',
      'https://gh-proxy.com/$raw?t=$ts',
      'https://ghfast.top/$raw?t=$ts',
      '$raw?t=$ts',
    ];
  }

  /// 模型二进制下载地址：自有服务器优先，GitHub 镜像兜底。
  static List<String> _fileUrls(String file) {
    final base =
        'https://github.com/$_repo/releases/download/models/$file';
    return [
      '$_serverModelsBase/$file',
      'https://ghproxy.net/$base',
      'https://gh-proxy.com/$base',
      'https://ghfast.top/$base',
      base,
    ];
  }

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(minutes: 10),
  ));

  bool _checking = false;

  /// 热更新状态（供UI显示）
  HotupdatePhase phase = HotupdatePhase.idle;
  double progress = 0;
  String currentName = '';
  final List<String> newlyAdded = [];

  Directory? _dirCache;

  /// 本地模型目录（id.tflite + id.json）
  Future<Directory> modelsDir() async {
    if (_dirCache != null) return _dirCache!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/models');
    if (!await dir.exists()) await dir.create(recursive: true);
    _dirCache = dir;
    return dir;
  }

  /// 读取本地已下载的模型列表
  Future<List<AppModelEntry>> listLocalModels() async {
    final dir = await modelsDir();
    final result = <AppModelEntry>[];
    try {
      await for (final f in dir.list()) {
        if (f is! File || !f.path.endsWith('.json')) continue;
        try {
          final meta =
              RemoteModelMeta.fromJson(jsonDecode(await f.readAsString()));
          final tflite = File(f.path.replaceAll('.json', '.tflite'));
          if (await tflite.exists()) {
            result.add(meta.toEntry(tflite.path));
          }
        } catch (e) {
          debugPrint('[Hotupdate] 跳过损坏的模型meta: $e');
        }
      }
    } catch (_) {}
    return result;
  }

  /// 静默检查并下载新模型（可重入安全：进行中直接跳过）
  Future<void> checkAndDownload() async {
    if (_checking) return;
    _checking = true;
    newlyAdded.clear();
    try {
      final manifest = await _fetchManifest();
      if (manifest == null || manifest.isEmpty) {
        phase = HotupdatePhase.idle;
        return;
      }

      final local = await listLocalModels();
      final localIds = local.map((m) => m.id).toSet();
      // 内置模型不重复下载
      final builtinIds = kAppModels.map((m) => m.id).toSet();

      for (final meta in manifest) {
        if (localIds.contains(meta.id) || builtinIds.contains(meta.id)) {
          continue;
        }
        final ok = await _downloadModel(meta);
        if (ok) newlyAdded.add(meta.name);
      }
      phase = HotupdatePhase.done;
    } catch (e) {
      debugPrint('[Hotupdate] 检查失败: $e');
      phase = HotupdatePhase.idle;
    } finally {
      _checking = false;
    }
  }

  Future<List<RemoteModelMeta>?> _fetchManifest() async {
    for (final url in _manifestUrls) {
      try {
        final r = await _dio.get<String>(
          url,
          options: Options(receiveTimeout: const Duration(seconds: 15)),
        );
        final list = (jsonDecode(r.data!) as Map<String, dynamic>)['models']
            as List<dynamic>? ?? [];
        final models = list
            .map((e) => RemoteModelMeta.fromJson(e as Map<String, dynamic>))
            .toList();
        debugPrint('[Hotupdate] 清单成功: $url（${models.length} 个模型）');
        return models;
      } catch (e) {
        debugPrint('[Hotupdate] 清单通道失败: $url（$e）');
      }
    }
    return null;
  }

  Future<bool> _downloadModel(RemoteModelMeta meta) async {
    phase = HotupdatePhase.downloading;
    currentName = meta.name;
    progress = 0;

    final dir = await modelsDir();
    final tmp = File('${dir.path}/${meta.id}.tflite.part');
    final target = File('${dir.path}/${meta.id}.tflite');

    for (final url in _fileUrls(meta.file)) {
      try {
        if (await tmp.exists()) await tmp.delete();
        debugPrint('[Hotupdate] 开始下载: $url');
        await _dio.download(
          url,
          tmp.path,
          options: Options(receiveTimeout: const Duration(seconds: 60)),
          onReceiveProgress: (received, total) {
            if (total > 0) {
              progress = received / total;
              if (received == total) {
                debugPrint('[Hotupdate] 下载完成: ${meta.id}');
              }
            }
          },
        );
        final size = await tmp.length();
        debugPrint('[Hotupdate] ${meta.id} 下载大小: $size / ${meta.size}');
        if (meta.size > 0 && size != meta.size) {
          debugPrint('[Hotupdate] ${meta.id} 大小不符 ($size != ${meta.size})，跳过该通道');
          continue;
        }
        await tmp.rename(target.path);
        await File('${dir.path}/${meta.id}.json')
            .writeAsString(jsonEncode(meta.toJson()));
        debugPrint('[Hotupdate] 已下载模型: ${meta.name}');
        return true;
      } catch (e) {
        debugPrint('[Hotupdate] ${meta.id} 通道失败: $e');
      }
    }
    if (await tmp.exists()) await tmp.delete();
    return false;
  }
}

enum HotupdatePhase { idle, downloading, done }

/// 清单中的一条模型定义
class RemoteModelMeta {
  final String id;
  final String name;
  final String file;
  final int size;
  final int inputSize;
  final String? recordModuleKey;
  final List<ModelLabel> labels;

  const RemoteModelMeta({
    required this.id,
    required this.name,
    required this.file,
    required this.size,
    required this.inputSize,
    required this.labels,
    this.recordModuleKey,
  });

  factory RemoteModelMeta.fromJson(Map<String, dynamic> json) {
    return RemoteModelMeta(
      id: json['id'] as String,
      name: json['name'] as String,
      file: json['file'] as String,
      size: (json['size'] as num?)?.toInt() ?? 0,
      inputSize: (json['inputSize'] as num?)?.toInt() ?? 224,
      recordModuleKey: json['recordModuleKey'] as String?,
      labels: ((json['labels'] as List<dynamic>?) ?? [])
          .map((e) {
            final m = e as Map<String, dynamic>;
            return ModelLabel(
              en: (m['en'] as String?) ?? '',
              zh: (m['zh'] as String?) ?? '',
              desc: (m['desc'] as String?) ?? '',
              healthy: (m['healthy'] as bool?) ?? false,
            );
          })
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'file': file,
        'size': size,
        'inputSize': inputSize,
        'recordModuleKey': recordModuleKey,
        'labels': labels
            .map((l) => {
                  'en': l.en,
                  'zh': l.zh,
                  'desc': l.desc,
                  'healthy': l.healthy,
                })
            .toList(),
      };

  AppModelEntry toEntry(String filePath) {
    return AppModelEntry(
      id: id,
      name: name,
      assetPath: '',
      filePath: filePath,
      labels: labels,
      inputSize: inputSize,
      recordModuleKey: recordModuleKey,
    );
  }
}
