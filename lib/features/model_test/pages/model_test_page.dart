import 'dart:async';

import 'package:camera/camera.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/local_database.dart';
import '../../../providers/weather_provider.dart';
import '../../../services/ai_suggestion_worker.dart';
import '../../../services/growth_record_store.dart';
import '../../../services/model_inference_service.dart';
import '../../../services/ys_image_store.dart';
import '../data/model_catalog.dart';
import '../data/model_labels.dart';
import '../widgets/warning_detail_card.dart';

/// 模型测试页：摄像头开关式实时识别（竖屏）
///
/// - 开关默认关闭，打开后启动摄像头并运行本地TFLite模型推理
/// - 命中的作物问题画面自动按类别采集入库（.ys加密存储）
/// - 识别到的问题实时加入预警列表
/// - 退出时本次数据自动同步到数据管理-生长检测模块
class ModelTestPage extends ConsumerStatefulWidget {
  const ModelTestPage({super.key});

  @override
  ConsumerState<ModelTestPage> createState() => _ModelTestPageState();
}

class _ModelTestPageState extends ConsumerState<ModelTestPage> {
  static const double _captureThreshold = 0.5;
  static const int _inferenceIntervalMs = 600;
  static const int _captureCooldownMs = 3000;

  CameraController? _camera;
  final ModelInferenceService _inference = ModelInferenceService();
  final YsImageStore _ysStore = YsImageStore();

  /// 当前选中模型（下拉可切换，本地记忆上次选择）
  late AppModelEntry _model = modelEntryOf(
      LocalDatabase().get('selected_model_id'));
  bool _switchingModel = false;

  bool _cameraOn = false; // 开关状态（默认关闭）
  bool _switching = false; // 开关切换中
  bool _modelReady = false;
  bool _syncing = false;
  String _statusText = '';

  InferenceResult? _lastResult;
  DateTime _lastInference = DateTime.fromMillisecondsSinceEpoch(0);
  final Map<int, DateTime> _lastCaptureByClass = {};

  /// 本次测试会话
  late final String _sessionId =
      'session_${DateTime.now().millisecondsSinceEpoch}';
  /// 本次采集分类库：类别索引 → 问题组
  final Map<int, ProblemGroup> _sessionGroups = {};
  /// 缩略图缓存（.ys路径 → 解密JPEG字节）
  final Map<String, Uint8List?> _thumbCache = {};

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _loadModel();
  }

  @override
  void dispose() {
    _stopCamera();
    _inference.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  /// 返回退出：先停摄像头，再同步本次数据到生长检测模块，然后pop
  Future<void> _onBack() async {
    if (_syncing) return;
    _syncing = true;
    await _stopCamera();
    await _syncSessionOnExit();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _loadModel() async {
    setState(() => _statusText = '正在加载模型...');
    final ok = await _inference.load(
      assetPath: _model.assetPath,
      inputSize: _model.inputSize,
    );
    if (!mounted) return;
    setState(() {
      _modelReady = ok;
      _statusText = ok ? '' : '模型加载失败';
    });
  }

  /// 切换模型：停摄像头 → 重载推理引擎 → 清空实时结果
  Future<void> _switchModel(AppModelEntry entry) async {
    if (entry.id == _model.id || _switchingModel) return;
    setState(() {
      _switchingModel = true;
      _model = entry;
      _statusText = '正在加载模型...';
    });
    LocalDatabase().set('selected_model_id', entry.id);
    await _stopCamera();
    if (mounted) setState(() => _cameraOn = false);
    final ok = await _inference.load(
      assetPath: entry.assetPath,
      inputSize: entry.inputSize,
    );
    if (!mounted) return;
    setState(() {
      _lastResult = null;
      _modelReady = ok;
      _statusText = ok ? '' : '模型加载失败';
      _switchingModel = false;
    });
    _showSnack(ok ? '已切换：${entry.name}' : '模型加载失败');
  }

  // ==================== 摄像头开关 ====================

  Future<void> _toggleCamera(bool enable) async {
    if (_switching) return;
    setState(() => _switching = true);
    try {
      if (enable) {
        await _startCamera();
      } else {
        await _stopCamera();
      }
      setState(() => _cameraOn = enable);
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  Future<void> _startCamera() async {
    if (!_modelReady) {
      _showSnack('模型尚未就绪，请稍候');
      return;
    }
    // 相机权限
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }
    if (!status.isGranted) {
      if (mounted) _showSnack('需要相机权限才能进行实时识别');
      return;
    }
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) _showSnack('设备无可用摄像头');
        return;
      }
      final back =
          cameras.where((c) => c.lensDirection == CameraLensDirection.back);
      final cameraDesc = back.isNotEmpty ? back.first : cameras.first;
      final controller = CameraController(
        cameraDesc,
        ResolutionPreset.medium,
        imageFormatGroup: ImageFormatGroup.yuv420,
        enableAudio: false,
      );
      await controller.initialize();
      await controller.startImageStream(_onFrame);
      _camera = controller;
    } catch (e) {
      debugPrint('[ModelTest] 摄像头启动失败: $e');
      if (mounted) _showSnack('摄像头启动失败，请重试');
    }
  }

  Future<void> _stopCamera() async {
    final controller = _camera;
    _camera = null;
    _lastResult = null;
    try {
      if (controller != null) {
        if (controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }
        await controller.dispose();
      }
    } catch (e) {
      debugPrint('[ModelTest] 摄像头停止异常: $e');
    }
  }

  // ==================== 推理与采集 ====================

  void _onFrame(CameraImage image) {
    final now = DateTime.now();
    if (now.difference(_lastInference).inMilliseconds < _inferenceIntervalMs) {
      return;
    }
    _lastInference = now;
    if (!_inference.isLoaded || _inference.isBusy) return;

    // 相机帧快照（仅主线程拷贝字节），YUV转换+推理全部在常驻后台isolate完成，
    // 主线程不阻塞，消除周期性卡顿
    final snapshot = FrameSnapshot.fromCameraImage(image);
    _inference.inferAsync(snapshot, (result) {
      if (!mounted || _camera == null) return;
      setState(() => _lastResult = result);
      _maybeCapture(result);
    });
  }

  /// 命中问题类→采集入库（按类别节流，同一类3秒最多1张）
  /// 仅关联了记录模块的模型（如农作物模型）才采集；其他模型仅实时识别
  Future<void> _maybeCapture(InferenceResult result) async {
    if (_model.recordModuleKey == null) return;
    final idx = result.topIndex;
    final labels = _model.labels;
    if (idx < 0 || idx >= labels.length || labels[idx].healthy) return;
    if (result.topConfidence < _captureThreshold) return;

    final now = DateTime.now();
    final last = _lastCaptureByClass[idx];
    if (last != null && now.difference(last).inMilliseconds < _captureCooldownMs) {
      return;
    }
    _lastCaptureByClass[idx] = now;

    final controller = _camera;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      final f = File(file.path);
      if (await f.exists()) await f.delete(); // 原始图不入相册/公共目录
      final ysPath = await _ysStore.saveCapturedImage(_sessionId, bytes);
      if (!mounted) return;
      setState(() {
        final group = _sessionGroups[idx];
        if (group != null) {
          group.imagePaths.add(ysPath);
          group.hitCount += 1;
          if (result.topConfidence > group.maxConfidence) {
            group.maxConfidence = result.topConfidence;
          }
        } else {
          _sessionGroups[idx] = ProblemGroup(
            labelIndex: idx.toString(),
            zhName: labels[idx].zh,
            desc: labels[idx].desc,
            maxConfidence: result.topConfidence,
            hitCount: 1,
            imagePaths: [ysPath],
          );
        }
      });
    } catch (e) {
      debugPrint('[ModelTest] 采集失败: $e');
    }
  }

  // ==================== 退出同步 ====================

  /// 退出页面：本次数据自动同步到 病虫害记录 模块
  ///
  /// 注意：仅由 _onBack 调用（其负责 _syncing 防重入），此处不再自查，
  /// 否则标志位先被置位会导致同步被跳过（v2.4.0 同步失效根因）。
  Future<void> _syncSessionOnExit() async {
    if (_sessionGroups.isEmpty) return;
    try {
      final location =
          ref.read(weatherProvider).valueOrNull?.locationName ?? '未知地区';
      final now = DateTime.now();
      final timeText =
          '${now.year}-${_p2(now.month)}-${_p2(now.day)} ${_p2(now.hour)}:${_p2(now.minute)}';
      // 卡片命名：地区（某某市某某县/区）+ 时间戳
      final shortLocation = _shortLocation(location);
      final record = GrowthRecord(
        id: _sessionId,
        name: '$shortLocation $timeText',
        locationName: shortLocation,
        timeText: timeText,
        createdAt: now,
        problems: _sessionGroups.values.map((g) => ProblemGroup(
              labelIndex: g.labelIndex,
              zhName: g.zhName,
              desc: g.desc,
              maxConfidence: g.maxConfidence,
              hitCount: g.hitCount,
              imagePaths: List<String>.from(g.imagePaths),
            )).toList(),
        aiPending: true,
      );
      GrowthRecordStore().add(record);
      // 立即尝试生成AI建议（离线时AiWorker会暂存，联网后自动补全）
      unawaited(AiSuggestionWorker().generateFor(record.id));
    } catch (e) {
      debugPrint('[ModelTest] 退出同步失败: $e');
    }
  }

  /// 地区信息只保留"某某市某某县/区"两级，过长自动换行由UI处理
  String _shortLocation(String location) {
    final parts = location.split(RegExp(r'[·•·]'));
    if (parts.length >= 2) {
      return '${parts[0].trim()}${parts[1].trim()}';
    }
    return location.trim();
  }

  String _p2(int n) => n.toString().padLeft(2, '0');

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    final groups = _sessionGroups.values.toList()
      ..sort((a, b) => b.hitCount.compareTo(a.hitCount));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _onBack,
          ),
          // 模型下拉选择：显示当前模型名，点击弹出全部可用模型
          title: PopupMenuButton<AppModelEntry>(
            initialValue: _model,
            tooltip: '选择识别模型',
            onSelected: (entry) => _switchModel(entry),
            itemBuilder: (context) => [
              for (final m in kAppModels)
                PopupMenuItem<AppModelEntry>(
                  value: m,
                  child: Row(
                    children: [
                      Icon(
                        m.id == _model.id
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 18,
                        color: m.id == _model.id
                            ? AppColors.primary
                            : AppColors.textHint,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          m.name,
                          style: TextStyle(
                            fontSize: 14,
                            color: m.id == _model.id
                                ? AppColors.primary
                                : AppColors.textPrimary,
                            fontWeight: m.id == _model.id
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    _model.name,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down, size: 22),
              ],
            ),
          ),
        ),
        body: Column(
          children: [
            // 摄像头预览区
            _buildCameraArea(),
            // 开关与状态
            _buildSwitchBar(),
            const Divider(height: 1),
            // 预警列表
            Expanded(child: _buildWarningList(groups)),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraArea() {
    final controller = _camera;
    final result = _lastResult;
    return Stack(
      children: [
        AspectRatio(
          aspectRatio: 3 / 4,
          child: _cameraOn && controller != null && controller.value.isInitialized
              ? CameraPreview(controller)
              : Container(
                  color: const Color(0xFF1E2A20),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.videocam_off, size: 48, color: Colors.white38),
                        SizedBox(height: 10),
                        Text(
                          '摄像头已关闭',
                          style: TextStyle(color: Colors.white54, fontSize: 14),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '打开下方开关开始实时识别',
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
        // 实时识别结果叠加标注（分类模型：标签条；检测模型升级后绘制框）
        if (result != null) _buildOverlayLabel(result),
        // 模型加载中提示
        if (!_modelReady)
          Positioned.fill(
            child: Container(
              color: Colors.black45,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 8),
                    Text('正在加载识别模型...', style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 实时标注叠加条：问题类红色、健康类绿色
  Widget _buildOverlayLabel(InferenceResult result) {
    final idx = result.topIndex;
    final labels = _model.labels;
    final isProblem = idx >= 0 && idx < labels.length && !labels[idx].healthy;
    final color = isProblem ? AppColors.error : AppColors.success;
    final label = (idx >= 0 && idx < labels.length)
        ? labels[idx].zh
        : '未知';
    final conf = (result.topConfidence * 100).toStringAsFixed(1);
    return Positioned(
      top: 12,
      left: 12,
      right: 12,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(isProblem ? Icons.warning_amber_rounded : Icons.check_circle,
                    color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '$label  $conf%',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchBar() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.camera_alt, color: AppColors.primary, size: 22),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('实时识别',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          Text(
            _switching
                ? '切换中...'
                : _statusText.isNotEmpty
                    ? _statusText
                    : (_cameraOn ? '识别中' : '已关闭'),
            style: TextStyle(
              fontSize: 12,
              color: _cameraOn ? AppColors.success : AppColors.textHint,
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: _cameraOn,
            onChanged: _switching ? null : _toggleCamera,
            activeColor: AppColors.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildWarningList(List<ProblemGroup> groups) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              const Icon(Icons.notifications_active,
                  size: 18, color: AppColors.accent),
              const SizedBox(width: 6),
              Text('实时预警（${groups.length}）',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        Expanded(
          child: groups.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.shield_outlined,
                          size: 52, color: AppColors.textDisabled),
                      SizedBox(height: 10),
                      Text('暂无预警，打开摄像头开始识别',
                          style: TextStyle(color: AppColors.textHint, fontSize: 13)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: groups.length,
                  itemBuilder: (context, index) => _buildWarningItem(groups[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildWarningItem(ProblemGroup group) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showWarningDetailCard(
          context,
          problem: group,
          imageLoader: _loadImageBytes,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.pest_control,
                    color: AppColors.error, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.zhName,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                      '识别 ${group.hitCount} 次 · 置信度 '
                      '${(group.maxConfidence * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textHint),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }

  /// 解密.ys图片字节（带缓存）
  Future<Uint8List?> _loadImageBytes(String path) async {
    if (_thumbCache.containsKey(path)) return _thumbCache[path];
    try {
      final bytes = await _ysStore.readImageBytes(path);
      _thumbCache[path] = bytes;
      return bytes;
    } catch (e) {
      debugPrint('[ModelTest] 图片解密失败: $e');
      _thumbCache[path] = null;
      return null;
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }
}
