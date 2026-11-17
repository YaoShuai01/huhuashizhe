import 'model_labels.dart';

import '../../../services/model_hotupdate_service.dart';

/// 应用内可切换的识别模型条目
///
/// 模型来源有两种：
/// - 内置模型：assetPath 指向 APK 内 asset（随版本发布）
/// - 热更新模型：filePath 指向本地已下载文件（由 ModelHotupdateService 从
///   GitHub Release 静默下载，无需发版）；此时 assetPath 为空字符串
class AppModelEntry {
  /// 唯一标识（用于本地记忆上次选择）
  final String id;

  /// 下拉列表显示名
  final String name;

  /// TFLite 模型 asset 路径（内置模型使用）
  final String assetPath;

  /// TFLite 模型本地文件路径（热更新模型使用）
  final String? filePath;

  /// 输出类别标签（顺序与模型输出索引一一对应）
  final List<ModelLabel> labels;

  /// 模型输入尺寸（正方形边长）
  final int inputSize;

  /// 关联的记录模块 key（null = 仅实时识别，命中不采集入库）
  /// 当前 'pest' = 病虫害记录模块
  final String? recordModuleKey;

  const AppModelEntry({
    required this.id,
    required this.name,
    required this.assetPath,
    this.filePath,
    required this.labels,
    this.inputSize = 224,
    this.recordModuleKey,
  });
}

/// 当前应用内置的可用模型
const List<AppModelEntry> kAppModels = [
  AppModelEntry(
    id: 'crop_39',
    name: '农作物病虫害识别',
    assetPath: 'assets/models/classify_39.tflite',
    labels: kModelLabels,
    inputSize: 320,
    recordModuleKey: 'pest',
  ),
  // 后续内置模型在此追加；热更新模型无需改代码，由 manifest 静默下发
];

/// 加载全部可用模型：内置 + 本地已下载（热更新）
Future<List<AppModelEntry>> loadAllModels() async {
  final local = await ModelHotupdateService.instance.listLocalModels();
  final ids = kAppModels.map((m) => m.id).toSet();
  return [
    ...kAppModels,
    ...local.where((m) => !ids.contains(m.id)),
  ];
}

/// 按 id 查找模型，找不到返回第一个（兜底）
AppModelEntry modelEntryOf(String? id, [List<AppModelEntry>? all]) {
  final list = all ?? kAppModels;
  for (final m in list) {
    if (m.id == id) return m;
  }
  return list.first;
}
