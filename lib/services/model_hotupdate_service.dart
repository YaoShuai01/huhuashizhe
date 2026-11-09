import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../features/model_test/data/model_catalog.dart';

/// 模型热更新服务
///
/// 模型清单托管在仓库 models/manifest.json（raw.githubusercontent.com），
/// 模型二进制托管在 GitHub Release（tag=models，标记为 prerelease 不影响应用更新检测）。
/// App 启动/进入模型测试页时静默检查：对比清单与本地已下载模型，
/// 有新模型就在后台下载，完成后模型下拉列表自动多出对应条目，无需发版更新App。
///
/// 发布新模型的流程（由助手执行）：
/// 1. 导出的 .tflite 上传：gh release upload models xxx.tflite --clobber
/// 2. 编辑 models/manifest.json 增加条目（labels 从 *_labels.txt 转出并补中文）
/// 3. 提交推送，App 联网后自动下载生效
class ModelHotupdateService {
  ModelHotupdateService._();
  static final ModelHotupdateService instance = ModelHotupdateService._();

  static const _repo = 'YaoShuai01/huhuashizhe';
  static const _branch = 'main';

  /// 清单地址：直连优先（raw 一般可通），失败走加速镜像
  static List<String> get _manifestUrls => [
        'https://raw.githubusercontent.com/$_repo/$_branch/models/manifest.json',
        for (final p in const ['https://ghfast.top/', 'https://ghproxy.net/', 'https://gh-proxy.com/'])
          '${p}https://raw.githubusercontent.com/$_repo/$_branch/models/manifest.json',
      ];

  /// 模型二进制下载地址（Release 资产），同样镜像回退
  static List<String> _fileUrls(String file) {
    const base = 'https://github.com/$_repo/releases/download/models/$file';
    return [
      base,
      for (final p in const ['https://ghfast.top/', 'https://ghproxy.net/', 'https://gh-proxy.com/'])
        '$p$base',
    ];
  }

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(minutes: 10),
  ));

  bool _checking = false;

  /// 热更新状态（供UI显示）
  HotupdatePhase phase = HotupdatePhase.idle;
  double progress = 0;
  String currentName = '';
  final List<String> newlyAdded = [];

  Directory? _dirCache;

  /// 本地模型目录（<id>.tflite + <id>.json）
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
        final r = await _dio.get<String>(url);
        final list = (jsonDecode(r.data!) as Map<String, dynamic>)['models']
            as List<dynamic>? ?? [];
        return list
            .map((e) => RemoteModelMeta.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (e) {
        debugPrint('[Hotupdate] 清单通道失败: $url');
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
        await _dio.download(
          url,
          tmp.path,
          onReceiveProgress: (received, total) {
            if (total > 0) progress = received / total;
          },
        );
        final size = await tmp.length();
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
          .map((e) => ModelLabel(
                en: (e['en'] as String?) ?? '',
                zh: (e['zh'] as String?) ?? '',
                desc: (e['desc'] as String?) ?? '',
                healthy: (e['healthy'] as bool?) ?? false,
              ))
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
