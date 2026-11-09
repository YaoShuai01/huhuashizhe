import 'model_labels.dart';

/// 应用内可切换的识别模型条目
///
/// 新增模型接入步骤：
/// 1. 训练好的 .tflite 文件放入 assets/models/（pubspec 已声明整个目录，无需改配置）
/// 2. 在本文件 kAppModels 中追加一条 AppModelEntry（含类别标签列表）
/// 3. 发布新版本后，用户在模型测试页下拉列表即可选择新模型
class AppModelEntry {
  /// 唯一标识（用于本地记忆上次选择）
  final String id;

  /// 下拉列表显示名
  final String name;

  /// TFLite 模型 asset 路径
  final String assetPath;

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
    inputSize: 224,
    recordModuleKey: 'pest',
  ),
  // 后续模型在此追加，例如：
  // AppModelEntry(
  //   id: 'person_det',
  //   name: '人物识别',
  //   assetPath: 'assets/models/person_det.tflite',
  //   labels: kPersonLabels,
  //   inputSize: 640,
  // ),
];

/// 按 id 查找模型，找不到返回第一个（兜底）
AppModelEntry modelEntryOf(String? id) {
  for (final m in kAppModels) {
    if (m.id == id) return m;
  }
  return kAppModels.first;
}
