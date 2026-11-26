import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fvp/fvp.dart' show FVPControllerExtensions;
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/local_database.dart';
import '../../../providers/weather_provider.dart';
import '../../../services/ai_suggestion_worker.dart';
import '../../../services/drone_udp_service.dart';
import '../../../services/growth_record_store.dart';
import '../../../services/h264_udp_relay.dart';
import '../../../services/model_hotupdate_service.dart';
import '../../../services/model_inference_service.dart';
import '../../../services/satellite_service.dart';
import '../../../services/vision_stream_service.dart';
import '../../../services/voice_service.dart';
import '../../../services/ys_image_store.dart';
import '../../model_test/data/model_catalog.dart';
import '../../model_test/widgets/warning_detail_card.dart';
import '../widgets/drone_joystick.dart';
import '../widgets/vertical_throttle.dart';
import '../widgets/yaw_joystick.dart';

class RemoteControlPage extends ConsumerStatefulWidget {
  const RemoteControlPage({super.key});

  @override
  ConsumerState<RemoteControlPage> createState() => _RemoteControlPageState();
}

class _RemoteControlPageState extends ConsumerState<RemoteControlPage> {
  final DroneUdpService _udp = DroneUdpService();
  final VisionStreamService _vision = VisionStreamService();
  static const _galleryChannel = MethodChannel('com.huhuashizhe/gallery');
  Uint8List? _lastPhoto;
  bool _flipH = false;   // 画面水平翻转
  bool _flipV = false;   // 画面垂直翻转
  int _throttleValue = 0; // 竖向油门 0~100%
  int _trimRoll = 0; // 横滚微调，单位 0.1 度
  int _trimPitch = 0; // 俯仰微调，单位 0.1 度
  int _trimYaw = 0; // 航向微调，单位 0.1 度/秒
  bool _trimBusy = false;

  // P4 H.264 图传：P4 → 飞控 SPI → 飞控 WiFi(UDP 8889) → 本机中转 HTTP → FVP 解码
  bool _useH264 = true;
  VideoPlayerController? _h264;
  H264UdpRelay? _relay;
  bool _h264Loading = false;
  String? _h264Error;
  Timer? _h264UiTimer;

  // 北斗卫星实时状态（用于底部遥测与起飞播报）
  StreamSubscription<GnssSnapshot>? _gnssSub;
  int _beidouFound = 0;
  int _beidouUsed = 0;

  // ===== 病虫害识别（原模型测试页功能，画面来源全部改为图传帧） =====
  static const double _captureThreshold = 0.5;
  static const int _inferenceIntervalMs = 600;
  static const int _captureCooldownMs = 3000;

  final ModelInferenceService _inference = ModelInferenceService();
  final YsImageStore _ysStore = YsImageStore();

  /// 当前选中模型（本地记忆上次选择，支持热更新模型）
  List<AppModelEntry> _models = kAppModels;
  AppModelEntry _model = modelEntryOf(LocalDatabase().get('selected_model_id'));
  bool _modelReady = false;
  bool _switchingModel = false;

  bool _recogOn = false; // 识别开关
  InferenceResult? _lastResult;
  DateTime _lastInference = DateTime.fromMillisecondsSinceEpoch(0);
  final Map<int, DateTime> _lastCaptureByClass = {};
  bool _decodingFrame = false; // 上一帧JPEG还在解码时跳过新帧

  /// 本次识别会话（退出遥控器时同步到病虫害记录模块）
  late final String _sessionId =
      'session_${DateTime.now().millisecondsSinceEpoch}';
  /// 本次采集分类库：类别索引 → 问题组
  final Map<int, ProblemGroup> _sessionGroups = {};
  /// 缩略图缓存（.ys路径 → 解密JPEG字节）
  final Map<String, Uint8List?> _thumbCache = {};

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initUdp();
    _initGnss();
    // 视觉板图传：进入遥控页自动开播，画面显示在中央预留区
    _vision.start();
    _vision.photoNotifier.addListener(_onPhoto);
    // 病虫害识别：订阅图传帧（识别开关打开后消费帧做推理）
    _vision.frameNotifier.addListener(_onVisionFrame);
    _initRecognition();
    _initH264();
    // 未出画面时每秒刷新一次接收统计，便于现场判断卡在哪一环
    _h264UiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_useH264 && !(_h264?.value.isInitialized ?? false)) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _gnssSub?.cancel();
    _udp.dispose();
    _vision.photoNotifier.removeListener(_onPhoto);
    _vision.frameNotifier.removeListener(_onVisionFrame);
    _vision.dispose();
    _inference.dispose();
    _h264?.dispose();
    _h264UiTimer?.cancel();
    _relay?.dispose();
    super.dispose();
  }

  /// 连接 H.264 图传：先起 UDP 中转（收飞控视频并本地转成 HTTP 流），FVP 负责解码
  Future<void> _initH264() async {
    if (_h264 != null) return;
    setState(() {
      _h264Loading = true;
      _h264Error = null;
    });
    VideoPlayerController? controller;
    try {
      var relay = _relay;
      if (relay == null) {
        relay = H264UdpRelay();
        await relay.start();
        _relay = relay;
      }
      controller = VideoPlayerController.networkUrl(Uri.parse(relay.localUrl));
      await controller.initialize().timeout(const Duration(seconds: 10));
      // 缓冲上限压到 400ms：实时图传宁可丢旧帧也不能攒延迟
      controller.setBufferRange(min: 0, max: 400, drop: true);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _h264 = controller;
        _h264Loading = false;
      });
    } catch (e) {
      await controller?.dispose();
      if (!mounted) return;
      setState(() {
        _h264Loading = false;
        _h264Error = 'H.264 连接失败：$e';
      });
    }
  }

  /// 重试：连中转一起重建（UDP 端口可能已被占用或飞控重启过）
  void _retryH264() {
    final old = _h264;
    _h264 = null;
    old?.dispose();
    final relay = _relay;
    _relay = null;
    relay?.dispose();
    _initH264();
  }

  void _setVideoMode(bool h264) {
    if (_useH264 == h264) return;
    setState(() => _useH264 = h264);
    if (h264) {
      _initH264();
    } else {
      _h264?.pause();
    }
  }

  /// H.264 画面（解码由 FVP/FFmpeg 完成）
  Widget _buildH264View() {
    final controller = _h264;
    if (controller == null || !controller.value.isInitialized) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_h264Loading)
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(Icons.videocam_off_outlined, size: 40, color: Colors.grey[700]),
            const SizedBox(height: 8),
            Text(
              _h264Loading ? '正在连接 H.264 图传...' : (_h264Error ?? '等待 H.264 画面'),
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
              textAlign: TextAlign.center,
            ),
            if (_relay != null) ...[
              const SizedBox(height: 4),
              Text(
                _relay!.statsText,
                style: TextStyle(color: Colors.grey[500], fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ],
            if (!_h264Loading)
              TextButton(
                onPressed: _retryH264,
                child: const Text('重试'),
              ),
          ],
        ),
      );
    }
    final size = controller.value.size;
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..scale(_flipH ? -1.0 : 1.0, _flipV ? -1.0 : 1.0),
          child: VideoPlayer(controller),
        ),
      ),
    );
  }

  /// 订阅北斗卫星实时状态，供底部遥测和起飞播报使用
  Future<void> _initGnss() async {
    try {
      final permission = await Permission.locationWhenInUse.request();
      if (!permission.isGranted) return;
    } catch (_) {
      // 测试环境或精简系统没有权限插件时，仍尝试订阅原生事件
    }
    if (!mounted) return;

    _gnssSub ??= SatelliteService.gnssStream.listen(
      (snapshot) {
        if (!mounted) return;
        setState(() {
          _beidouFound = snapshot.foundOf('beidou');
          _beidouUsed = snapshot.usedOf('beidou');
        });
      },
      onError: (Object error) {
        // 搜星失败时保持上一次状态，不打断遥控
      },
    );
  }

  // ==================== 病虫害识别（画面来源：图传帧） ====================

  /// 初始化：加载完整模型列表 → 加载推理引擎 → 静默检查热更新
  Future<void> _initRecognition() async {
    final all = await loadAllModels();
    if (!mounted) return;
    setState(() {
      _models = all;
      _model = modelEntryOf(LocalDatabase().get('selected_model_id'), all);
    });
    await _loadModel();
    _checkHotupdate();
  }

  Future<void> _loadModel() async {
    final ok = await _inference.load(
      assetPath: _model.assetPath.isEmpty ? null : _model.assetPath,
      filePath: _model.filePath,
      inputSize: _model.inputSize,
    );
    if (!mounted) return;
    setState(() => _modelReady = ok);
    if (!ok) _toast('识别模型加载失败', error: true);
  }

  /// 静默检查模型热更新：有新模型后台下载，完成后自动进选择列表
  Future<void> _checkHotupdate() async {
    final svc = ModelHotupdateService.instance;
    await svc.checkAndDownload();
    if (svc.newlyAdded.isEmpty || !mounted) return;
    final all = await loadAllModels();
    if (!mounted) return;
    setState(() => _models = all);
    _toast('已自动更新模型：${svc.newlyAdded.join('、')}');
  }

  /// 切换模型：重载推理引擎并清空实时结果（图传不受影响）
  Future<void> _switchModel(AppModelEntry entry) async {
    if (entry.id == _model.id || _switchingModel) return;
    setState(() {
      _switchingModel = true;
      _model = entry;
    });
    LocalDatabase().set('selected_model_id', entry.id);
    final ok = await _inference.load(
      assetPath: entry.assetPath.isEmpty ? null : entry.assetPath,
      filePath: entry.filePath,
      inputSize: entry.inputSize,
    );
    if (!mounted) return;
    setState(() {
      _lastResult = null;
      _modelReady = ok;
      _switchingModel = false;
    });
    _toast(ok ? '已切换：${entry.name}' : '模型加载失败', error: !ok);
  }

  /// 识别开关
  Future<void> _toggleRecognition() async {
    if (!_recogOn && !_modelReady) {
      _toast('识别模型尚未就绪，请稍候', error: true);
      return;
    }
    setState(() {
      _recogOn = !_recogOn;
      if (!_recogOn) _lastResult = null;
    });
    VoiceService.instance.speak(
      _recogOn ? '已开启病虫害识别' : '已关闭病虫害识别',
      priority: VoicePriority.status,
    );
    // 打开识别时若图传处于暂停态，自动恢复推流（识别依赖图传帧）
    if (_recogOn && !_vision.streaming) {
      _vision.start();
    }
  }

  /// 图传JPEG帧到达：节流后解码 → 提交后台isolate推理
  Future<void> _onVisionFrame() async {
    if (!_recogOn || _decodingFrame) return;
    final now = DateTime.now();
    if (now.difference(_lastInference).inMilliseconds < _inferenceIntervalMs) {
      return;
    }
    final jpg = _vision.frameNotifier.value;
    if (jpg == null) return;
    if (!_inference.isLoaded || _inference.isBusy) return;
    _lastInference = now;
    _decodingFrame = true;
    try {
      // 直接解码到模型输入尺寸，RGBA字节交给后台isolate转RGB+推理，
      // 主线程只承担一次JPEG解码，不阻塞操控
      final codec = await ui.instantiateImageCodec(
        jpg,
        targetWidth: _model.inputSize,
        targetHeight: _model.inputSize,
      );
      final frame = await codec.getNextFrame();
      final data =
          await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      frame.image.dispose();
      codec.dispose();
      if (data == null || !_recogOn || !mounted) return;
      final snapshot = FrameSnapshot.fromRgba(
        data.buffer.asUint8List(),
        width: _model.inputSize,
        height: _model.inputSize,
      );
      _inference.inferAsync(snapshot, (result) {
        if (!mounted || !_recogOn) return;
        setState(() => _lastResult = result);
        _maybeSpeak(result);
        _maybeCapture(result);
      });
    } catch (e) {
      debugPrint('[RemoteControl] 图传帧解码失败: $e');
    } finally {
      _decodingFrame = false;
    }
  }

  /// 识别到病虫害时语音播报（同一类别 10 秒内不重复，健康类别不播报）
  void _maybeSpeak(InferenceResult result) {
    final labels = _model.labels;
    final idx = result.topIndex;
    if (idx < 0 || idx >= labels.length) return;
    final label = labels[idx];
    if (label.healthy || result.topConfidence < _captureThreshold) return;
    final percent = (result.topConfidence * 100).round();
    VoiceService.instance.speak(
      '检测到${label.zh}，置信度$percent%',
      priority: VoicePriority.alert,
      dedup: const Duration(seconds: 10),
      dedupKey: 'pest_$idx',
    );
  }

  /// 命中问题类→采集当前图传帧入库（按类别节流，同一类3秒最多1张）
  /// 仅关联了记录模块的模型才采集；其他模型仅实时识别
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

    final jpg = _vision.frameNotifier.value;
    if (jpg == null) return;
    try {
      final ysPath = await _ysStore.saveCapturedImage(_sessionId, jpg);
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
      debugPrint('[RemoteControl] 采集失败: $e');
    }
  }

  /// 退出遥控器：本次识别数据自动同步到 病虫害记录 模块
  Future<void> _syncSessionOnExit() async {
    if (_sessionGroups.isEmpty) return;
    try {
      final location =
          ref.read(weatherProvider).valueOrNull?.locationName ?? '未知地区';
      final now = DateTime.now();
      final timeText =
          '${now.year}-${_p2(now.month)}-${_p2(now.day)} ${_p2(now.hour)}:${_p2(now.minute)}';
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
      debugPrint('[RemoteControl] 退出同步失败: $e');
    }
  }

  /// 地区信息只保留"某某市某某县/区"两级
  String _shortLocation(String location) {
    final parts = location.split(RegExp(r'[·•·]'));
    if (parts.length >= 2) {
      return '${parts[0].trim()}${parts[1].trim()}';
    }
    return location.trim();
  }

  String _p2(int n) => n.toString().padLeft(2, '0');

  /// 解密.ys图片字节（带缓存）
  Future<Uint8List?> _loadImageBytes(String path) async {
    if (_thumbCache.containsKey(path)) return _thumbCache[path];
    try {
      final bytes = await _ysStore.readImageBytes(path);
      _thumbCache[path] = bytes;
      return bytes;
    } catch (e) {
      debugPrint('[RemoteControl] 图片解密失败: $e');
      _thumbCache[path] = null;
      return null;
    }
  }

  /// 模型选择弹窗（显示当前模型名，列出全部可用模型含热更新）
  void _showModelPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.grey[900],
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text(
                    '选择识别模型',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const Divider(color: Colors.grey, height: 1),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: [
                      for (final m in _models)
                        ListTile(
                          dense: true,
                          leading: Icon(
                            m.id == _model.id
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: m.id == _model.id
                                ? AppColors.primary
                                : Colors.grey,
                            size: 20,
                          ),
                          title: Text(
                            m.name,
                            style: TextStyle(
                              color: m.id == _model.id
                                  ? AppColors.primary
                                  : Colors.white,
                              fontSize: 13,
                              fontWeight: m.id == _model.id
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            _switchModel(m);
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 预警列表面板：本次识别会话命中的问题分类
  void _showWarningSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.grey[900],
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final groups = _sessionGroups.values.toList()
          ..sort((a, b) => b.hitCount.compareTo(a.hitCount));
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.75,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '实时预警（${groups.length}）',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const Divider(color: Colors.grey, height: 1),
                Flexible(
                  child: groups.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            '暂无预警，打开识别开始检测',
                            style: TextStyle(
                                color: Colors.grey[500], fontSize: 13),
                          ),
                        )
                      : ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          children: [
                            for (final g in groups)
                              ListTile(
                                dense: true,
                                leading: const Icon(Icons.pest_control,
                                    color: AppColors.error, size: 22),
                                title: Text(
                                  g.zhName,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  '识别 ${g.hitCount} 次 · 置信度 '
                                  '${(g.maxConfidence * 100).toStringAsFixed(0)}%',
                                  style: TextStyle(
                                      color: Colors.grey[500], fontSize: 11),
                                ),
                                trailing: const Icon(Icons.chevron_right,
                                    color: Colors.grey, size: 18),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  showWarningDetailCard(
                                    context,
                                    problem: g,
                                    imageLoader: _loadImageBytes,
                                  );
                                },
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 实时标注叠加条：问题类红色、健康类绿色
  Widget _buildRecogOverlay() {
    if (!_recogOn) return const SizedBox.shrink();
    final result = _lastResult;
    Widget content;
    if (_switchingModel) {
      content = _recogChip('正在切换模型...', AppColors.info, Icons.sync);
    } else if (!_modelReady) {
      content = _recogChip('模型加载中...', AppColors.info, Icons.sync);
    } else if (result == null) {
      content = _recogChip('等待图传画面...', Colors.white38, Icons.videocam);
    } else {
      final idx = result.topIndex;
      final labels = _model.labels;
      final isProblem =
          idx >= 0 && idx < labels.length && !labels[idx].healthy;
      final color = isProblem ? AppColors.error : AppColors.success;
      final label = (idx >= 0 && idx < labels.length)
          ? labels[idx].zh
          : '未知';
      final conf = (result.topConfidence * 100).toStringAsFixed(1);
      content = _recogChip(
        '$label  $conf%',
        color,
        isProblem ? Icons.warning_amber_rounded : Icons.check_circle,
      );
    }
    return Positioned(
      top: 38,
      left: 0,
      right: 0,
      child: Center(child: content),
    );
  }

  Widget _recogChip(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 起飞：发送起飞指令并播报高度、气温、北斗卫星状态
  void _handleTakeoff() {
    if (!_udp.armed) {
      VoiceService.instance.speak(
        '请先解锁',
        priority: VoicePriority.status,
        dedup: const Duration(seconds: 2),
      );
      return;
    }

    final status = _udp.statusNotifier.value;
    if (status == DroneStatus.disconnected || status == DroneStatus.error) {
      VoiceService.instance.speak(
        '未连接无人机，无法起飞',
        priority: VoicePriority.alert,
        dedup: const Duration(seconds: 2),
      );
      return;
    }

    _udp.sendTakeoff();

    final String satelliteStatus;
    if (_beidouFound == 0) {
      satelliteStatus = '北斗卫星正在搜星';
    } else if (_beidouUsed == 0) {
      satelliteStatus = '北斗卫星已搜到$_beidouFound颗，正在定位';
    } else {
      satelliteStatus = '北斗卫星已搜到$_beidouFound颗，使用$_beidouUsed颗';
    }

    VoiceService.instance.speak(
      '起飞，当前高度1.5米，当前气温12度，$satelliteStatus，遥测信号正常，无人机飞行正常',
      priority: VoicePriority.status,
    );
    setState(() {});
  }

  void _onPhoto() {
    final jpg = _vision.photoNotifier.value;
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

  Future<void> _initUdp() async {
    try {
      await _udp.init();
      _udp.startSending();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('UDP初始化失败: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? AppColors.error : null,
      ),
    );
  }

  Future<void> _applyTrim({int dr = 0, int dp = 0, int dy = 0}) async {
    if (_trimBusy) return;
    final r = (_trimRoll + dr).clamp(-100, 100);
    final p = (_trimPitch + dp).clamp(-100, 100);
    final y = (_trimYaw + dy).clamp(-100, 100);
    // 先落界面再发请求：点击手感不再等一次 HTTP 往返
    setState(() {
      _trimBusy = true;
      _trimRoll = r;
      _trimPitch = p;
      _trimYaw = y;
    });
    final res = await _udp.setTrim(roll: r, pitch: p, yaw: y);
    if (!mounted) return;
    setState(() {
      _trimBusy = false;
      if (res != null) {
        _trimRoll = res['roll'] ?? _trimRoll;
        _trimPitch = res['pitch'] ?? _trimPitch;
        _trimYaw = res['yaw'] ?? _trimYaw;
      }
    });
    if (res == null) {
      _toast('微调设置失败，请确认手机已连接无人机 WiFi', error: true);
    }
  }

  Future<void> _calibrateGyro() async {
    if (_udp.armed) {
      _toast('请先上锁再校准陀螺仪', error: true);
      return;
    }
    final ok = await _udp.calibrateGyro();
    _toast(ok ? '已开始校准，请保持飞机静止约 2 秒' : '校准被拒绝：请上锁并确认已连接',
        error: !ok);
  }

  Future<void> _showTrimPanel() async {
    // 打开前先同步飞控里保存的值
    final t = await _udp.getTrim();
    if (!mounted) return;
    if (t != null) {
      setState(() {
        _trimRoll = t['roll'] ?? 0;
        _trimPitch = t['pitch'] ?? 0;
        _trimYaw = t['yaw'] ?? 0;
      });
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      // 横屏下默认弹窗最高只有屏幕的 9/16，微调面板会被裁掉；
      // 这里允许占满高度并支持滚动，小屏/横屏都能完整显示。
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setSheet) {
          final media = MediaQuery.of(ctx2);

          Widget trimCard({
            required String title,
            required String subtitle,
            required int value,
            String unit = '°',
            required VoidCallback onMinus,
            required VoidCallback onPlus,
          }) {
            return Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF2C2C2E),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(width: 4),
                        Text(subtitle,
                            style: const TextStyle(color: Colors.white38, fontSize: 9)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${value > 0 ? '+' : ''}${(value * 0.1).toStringAsFixed(1)}$unit',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(child: _trimStepButton(Icons.remove, onMinus)),
                        const SizedBox(width: 8),
                        Expanded(child: _trimStepButton(Icons.add, onPlus)),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }

          return Container(
            constraints: BoxConstraints(maxHeight: media.size.height * 0.94),
            decoration: const BoxDecoration(
              color: Color(0xFF1C1C1E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + media.padding.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('飞行微调',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                      ),
                      Text('永久保存到飞控',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.35),
                              fontSize: 10)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  const Text('机头偏向哪边，就往反方向微调',
                      style: TextStyle(color: Colors.white54, fontSize: 11)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      trimCard(
                        title: '前后',
                        subtitle: '俯仰',
                        value: _trimPitch,
                        onMinus: () async {
                          await _applyTrim(dp: -5);
                          setSheet(() {});
                        },
                        onPlus: () async {
                          await _applyTrim(dp: 5);
                          setSheet(() {});
                        },
                      ),
                      const SizedBox(width: 12),
                      trimCard(
                        title: '左右',
                        subtitle: '横滚',
                        value: _trimRoll,
                        onMinus: () async {
                          await _applyTrim(dr: -5);
                          setSheet(() {});
                        },
                        onPlus: () async {
                          await _applyTrim(dr: 5);
                          setSheet(() {});
                        },
                      ),
                      const SizedBox(width: 12),
                      trimCard(
                        title: '旋转',
                        subtitle: '航向',
                        value: _trimYaw,
                        unit: '°/s',
                        onMinus: () async {
                          await _applyTrim(dy: -5);
                          setSheet(() {});
                        },
                        onPlus: () async {
                          await _applyTrim(dy: 5);
                          setSheet(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('每步 0.5°，范围 ±10°；旋转 + 右旋、− 左旋（单位 °/s），用于修正缓慢自转',
                      style: TextStyle(color: Colors.white38, fontSize: 10)),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await _calibrateGyro();
                        setSheet(() {});
                      },
                      icon: const Icon(Icons.screen_rotation, size: 18),
                      label: const Text('陀螺仪校准（静止时按）'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 微调面板的大号加减按钮（横屏下更好点按）
  Widget _trimStepButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          height: 40,
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }

  void _showSettings() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('飞行设置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.wifi),
              title: const Text('WiFi: HuHuaShiZhe-Drone'),
              subtitle: const Text('IP: 192.168.4.1:8888'),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('通信协议: UDP'),
              subtitle: const Text('频率: 50Hz'),
            ),
            ListTile(
              leading: const Icon(Icons.security),
              title: const Text('安全机制'),
              subtitle: const Text('3秒无指令自动上锁'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showExitConfirm() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出遥控器'),
        content: const Text('退出后飞行器将自动上锁，确定退出吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _udp.setArmed(false);
              // 退出前把本次识别采集的数据同步到病虫害记录模块
              _syncSessionOnExit();
              Navigator.of(context).pop();
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }

  /// 喷洒力度选择 (6挡, 底部弹出列表)
  void _showSprayLevelPicker() {
    const levels = [
      (1, '1挡', '弱喷 · 45%'),
      (2, '2挡', '较弱 · 55%'),
      (3, '3挡', '中等 · 65%'),
      (4, '4挡', '较强 · 75%'),
      (5, '5挡', '强喷 · 88%'),
      (6, '6挡', '最强 · 100%'),
    ];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.grey[900],
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final current = _udp.sprayLevel;
        return SafeArea(
          child: ConstrainedBox(
            // 横屏高度有限，限制弹窗最大高度，超出可滚动
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '选择喷洒力度',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                const Divider(color: Colors.grey, height: 1),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: [
                      ...levels.map((lvl) {
                        final (level, title, desc) = lvl;
                        final selected = level == current;
                        return ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                          leading: Icon(
                            selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                            color: selected ? AppColors.warning : Colors.grey,
                            size: 20,
                          ),
                          // 单行紧凑显示，横屏下 6 挡可全部呈现，超出一屏仍可滚动
                          title: Text(
                            '$title  $desc',
                            style: TextStyle(
                              color: selected ? AppColors.warning : Colors.white,
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                              fontSize: 13,
                            ),
                          ),
                          trailing: selected
                              ? const Icon(Icons.check, color: AppColors.warning, size: 20)
                              : null,
                          onTap: () {
                            _udp.setSprayLevel(level); // 喷洒中实时切换力度
                            Navigator.pop(ctx);
                            setState(() {});
                            VoiceService.instance.speak(
                              '喷洒力度$level挡',
                              priority: VoicePriority.status,
                              dedup: const Duration(seconds: 1),
                            );
                          },
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final armed = _udp.armed;
    final spray = _udp.spray; // 0=关, 1~6=力度挡位
    final screenSize = MediaQuery.of(context).size;
    final joystickSize = (screenSize.height * 0.55).clamp(100.0, 160.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // 主体布局
            Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4, right: 4, top: 2, bottom: 2),
                    child: Row(
                      children: [
                        // 左摇杆：俯仰(前后) / 横滚(左右)，双轴回中
                        Expanded(
                          flex: 4,
                          child: _buildLeftJoystick(joystickSize),
                        ),
                        const SizedBox(width: 4),
                        // 监控画面（居中）
                        Expanded(
                          flex: 6,
                          child: _buildCameraView(),
                        ),
                        const SizedBox(width: 4),
                        // 右侧：偏航摇杆 + 竖向油门
                        Expanded(
                          flex: 5,
                          child: _buildRightControls(),
                        ),
                      ],
                    ),
                  ),
                ),
                // 底部控制栏
                _buildBottomBar(armed, spray),
              ],
            ),
            // 左上角：设置 + 退出图标
            Positioned(
              top: 4,
              left: 8,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildIconButton(Icons.tune, '微调', _showTrimPanel),
                  const SizedBox(width: 4),
                  _buildIconButton(Icons.settings, '设置', _showSettings),
                  const SizedBox(width: 4),
                  _buildIconButton(Icons.exit_to_app, '退出', _showExitConfirm),
                  const SizedBox(width: 6),
                  _buildSatelliteEntry(),
                ],
              ),
            ),
            // 右上角：连接状态
            Positioned(
              top: 4,
              right: 8,
              child: ValueListenableBuilder<DroneStatus>(
                valueListenable: _udp.statusNotifier,
                builder: (context, status, _) {
                  final (icon, color, label) = switch (status) {
                    DroneStatus.disconnected => (Icons.wifi_off, Colors.red, '未连接'),
                    DroneStatus.ready => (Icons.wifi_find, AppColors.accent, '就绪'),
                    DroneStatus.connected => (Icons.wifi, Colors.green, '已连接'),
                    DroneStatus.error => (Icons.wifi_lock, Colors.red, '错误'),
                  };
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, color: color, size: 12),
                        const SizedBox(width: 3),
                        Text(label, style: TextStyle(color: color, fontSize: 10)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ========== 左摇杆：俯仰(前后) / 横滚(左右)，双轴回中 ==========
  Widget _buildLeftJoystick(double size) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('前后 / 左右', style: TextStyle(fontSize: 11, color: Colors.white54)),
        const SizedBox(height: 4),
        DroneJoystick(
          size: size,
          color: AppColors.primary,
          stickyY: false, // 双轴回中
          onChanged: (x, y) {
            _udp.setRoll(x.round());   // X = 横滚 = 左右
            _udp.setPitch(y.round());  // Y = 俯仰 = 前后
          },
          onReleased: () {
            _udp.setRoll(0);
            _udp.setPitch(0);
          },
        ),
        const SizedBox(height: 4),
        Text(
          'P:${_udp.pitch.toString().padLeft(3)} R:${_udp.roll.toString().padLeft(3)}',
          style: const TextStyle(fontSize: 10, color: Colors.white38, fontFamily: 'monospace'),
        ),
      ],
    );
  }

  // ========== 右侧：独立偏航摇杆(只左右, 回中) + 竖向油门滑杆 ==========
  Widget _buildRightControls() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('左旋 / 右旋', style: TextStyle(fontSize: 11, color: Colors.white54)),
        const SizedBox(height: 4),
        YawJoystick(
          width: 150,
          height: 64,
          onChanged: (v) => _udp.setYaw(v),
          onReleased: () => _udp.setYaw(0),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: VerticalThrottle(
            value: _throttleValue,
            onChanged: (v) {
              setState(() => _throttleValue = v);
              _udp.setThrottle(v);
            },
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Y:${_udp.yaw.toString().padLeft(3)} T:${_throttleValue.toString().padLeft(3)}',
          style: const TextStyle(fontSize: 10, color: Colors.white38, fontFamily: 'monospace'),
        ),
      ],
    );
  }

  /// 中央监控画面：视觉板实时图传（未出画面时显示占位提示）
  Widget _buildCameraView() {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[800]!, width: 1),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 实时画面 / 占位提示
          _useH264
              ? _buildH264View()
              : ValueListenableBuilder<Uint8List?>(
            valueListenable: _vision.frameNotifier,
            builder: (context, frame, _) {
              if (frame == null) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.videocam_off_outlined, size: 40, color: Colors.grey[700]),
                      const SizedBox(height: 8),
                      ValueListenableBuilder<String>(
                        valueListenable: _vision.statusNotifier,
                        builder: (context, status, _) {
                          return Text(
                            status,
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                            textAlign: TextAlign.center,
                          );
                        },
                      ),
                      const SizedBox(height: 4),
                      Text('请确认飞控与视觉板均已上电\n手机已连接 HuHuaShiZhe-Drone 热点',
                          style: TextStyle(color: Colors.grey[800], fontSize: 10, height: 1.5),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      ValueListenableBuilder<String>(
                        valueListenable: _udp.debugNotifier,
                        builder: (context, debug, _) {
                          return Text(
                            debug,
                            style: TextStyle(color: Colors.green[700], fontSize: 9, fontFamily: 'monospace'),
                            textAlign: TextAlign.center,
                          );
                        },
                      ),
                    ],
                  ),
                );
              }
              // 翻转由摄像头侧完成（固件 VFLIP/VMIR），保证图传画面与拍照结果一致。
              // 这里只做解码降采样：720p全尺寸解码每帧20-30ms，降采样后帧率明显提升
              return LayoutBuilder(
                builder: (context, constraints) {
                  final dpr = MediaQuery.of(context).devicePixelRatio;
                  final targetW =
                      (constraints.maxWidth * dpr).round().clamp(320, 1920);
                  return Image.memory(
                    frame,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    cacheWidth: targetW,
                  );
                },
              );
            },
          ),
          // 病虫害识别实时标注叠加条
          _buildRecogOverlay(),
          // 左上角：FPS/码率 + 水平/垂直翻转
          Positioned(
            top: 4,
            left: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_useH264)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.videocam, size: 12, color: AppColors.primary),
                        const SizedBox(width: 3),
                        Text(
                          'H.264 实时',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ValueListenableBuilder<int>(
                  valueListenable: _vision.fpsNotifier,
                  builder: (context, fps, _) {
                    return ValueListenableBuilder<int>(
                      valueListenable: _vision.kbpsNotifier,
                      builder: (context, kbps, _) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.videocam, size: 12, color: AppColors.primary),
                              const SizedBox(width: 3),
                              Text(
                                fps > 0 ? '$fps fps · ${kbps}K/s' : '0 fps',
                                style: TextStyle(
                                  color: fps > 0 ? AppColors.primary : Colors.white38,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
                const SizedBox(width: 4),
                _buildIconButton(
                  Icons.swap_horiz,
                  '水平翻转',
                  () {
                    final v = !_flipH;
                    setState(() => _flipH = v);
                    _vision.setFlip(hmirror: v, vflip: _flipV);
                  },
                  active: _flipH,
                ),
                const SizedBox(width: 4),
                _buildIconButton(
                  Icons.swap_vert,
                  '垂直翻转',
                  () {
                    final v = !_flipV;
                    setState(() => _flipV = v);
                    _vision.setFlip(hmirror: _flipH, vflip: v);
                  },
                  active: _flipV,
                ),
              ],
            ),
          ),
          // 右上角：识别开关 + 模型选择 + 画质切换 + 暂停/恢复图传
          Positioned(
            top: 4,
            right: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildIconButton(
                  _recogOn ? Icons.psychology : Icons.psychology_alt,
                  _recogOn ? '关闭病虫害识别' : '开启病虫害识别',
                  _toggleRecognition,
                  active: _recogOn,
                ),
                const SizedBox(width: 4),
                _buildModelChip(),
                const SizedBox(width: 4),
                _buildIconButton(
                  Icons.switch_video,
                  _useH264 ? '切到 JPEG 图传' : '切到 H.264 图传',
                  () => _setVideoMode(!_useH264),
                ),
                const SizedBox(width: 4),
                if (!_useH264) ...[
                  _buildProfileButton(),
                  const SizedBox(width: 4),
                  ValueListenableBuilder<bool>(
                    valueListenable: _vision.streamingNotifier,
                    builder: (context, streaming, _) {
                      return _buildIconButton(
                        streaming ? Icons.pause_circle_outline : Icons.play_circle_outline,
                        streaming ? '暂停图传' : '恢复图传',
                        () => streaming ? _vision.stop() : _vision.start(),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          // 左下角：实时预警列表入口（角标显示本次识别命中分类数）
          Positioned(
            bottom: 6,
            left: 8,
            child: _buildWarningEntry(),
          ),
          // 右下角：高清拍照（仅旧视觉板 JPEG 链路）
          if (!_useH264)
            Positioned(
              bottom: 6,
              right: 8,
              child: _buildIconButton(
                Icons.photo_camera_outlined,
                '高清拍照',
                () => _vision.requestSnapshot(),
              ),
            ),
        ],
      ),
    );
  }

  /// 识别模型选择入口（显示当前模型名，过长截断）
  Widget _buildModelChip() {
    var name = _model.name;
    if (name.length > 8) name = '${name.substring(0, 8)}…';
    return Material(
      color: _recogOn
          ? AppColors.primary.withValues(alpha: 0.3)
          : Colors.black45,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: _showModelPicker,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Icon(Icons.arrow_drop_down, size: 16, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }

  /// 实时预警列表入口：带命中分类数角标
  Widget _buildWarningEntry() {
    final count = _sessionGroups.length;
    return Material(
      color: count > 0
          ? AppColors.error.withValues(alpha: 0.55)
          : Colors.black45,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: _showWarningSheet,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.notifications_active,
                size: 16,
                color: count > 0 ? Colors.white : Colors.white70,
              ),
              const SizedBox(width: 4),
              Text(
                '预警 $count',
                style: TextStyle(
                  color: count > 0 ? Colors.white : Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 右上角画质档位按钮（显示当前档位名）
  Widget _buildProfileButton() {
    return Material(
      color: Colors.black45,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: _showProfilePicker,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(
            _vision.profileLabel,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  String _resLabel(int idx) {
    const names = ['VGA', 'SVGA', 'XGA', 'HD', 'SXGA', 'UXGA', 'QXGA', 'QSXGA'];
    return (idx >= 0 && idx < names.length) ? names[idx] : '?';
  }

  /// 画质档位选择（清晰度与帧率此消彼长，受WiFi带宽限制）
  void _showProfilePicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.grey[900],
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text(
                    '画面画质（分辨率越高越清晰，帧率相应降低）',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                ),
                const Divider(color: Colors.grey, height: 1),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: List.generate(VisionStreamService.profiles.length, (i) {
                      final p = VisionStreamService.profiles[i];
                      final selected = i == _vision.profileIndex;
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                          color: selected ? AppColors.primary : Colors.grey,
                          size: 20,
                        ),
                        title: Text(
                          '${p.$1}   ${_resLabel(p.$2)} · ${p.$3}fps',
                          style: TextStyle(
                            color: selected ? AppColors.primary : Colors.white,
                            fontSize: 13,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                        onTap: () {
                          _vision.setProfile(i);
                          setState(() {});
                          Navigator.pop(ctx);
                        },
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 北斗/GPS 入口：进入卫星地图 / 罗盘（机载 GPS 未接入，先用手机定位）
  Widget _buildSatelliteEntry() {
    return Material(
      color: Colors.black45,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () async {
          await context.push('/speedometer');
          // 卫星页退出时会恢复全部方向，这里重新锁定横屏
          if (!mounted) return;
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        },
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.satellite_alt, size: 14, color: AppColors.primaryLight),
              SizedBox(width: 4),
              Text(
                '北斗/GPS',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton(IconData icon, String tooltip, VoidCallback onTap,
      {bool active = false}) {
    return Material(
      color: active ? AppColors.primary.withValues(alpha: 0.45) : Colors.black45,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: active ? Colors.white : Colors.white70, size: 18),
        ),
      ),
    );
  }

  /// 底部中间遥测：高度、气温、湿度、北斗卫星状态
  Widget _buildTelemetryStrip() {
    final satelliteText = _beidouFound == 0
        ? '搜星中'
        : '$_beidouFound搜$_beidouUsed用';
    final satelliteColor = _beidouUsed > 0
        ? AppColors.success
        : (_beidouFound > 0 ? AppColors.warning : Colors.white54);

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _telemetryItem('高度', '1.5 m'),
            _telemetryDivider(),
            _telemetryItem('气温', '12°C'),
            _telemetryDivider(),
            _telemetryItem('湿度', '--'),
            _telemetryDivider(),
            _telemetryItem('北斗', satelliteText, valueColor: satelliteColor),
          ],
        ),
      ),
    );
  }

  Widget _telemetryItem(
    String label,
    String value, {
    Color valueColor = Colors.white,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label ',
          style: const TextStyle(fontSize: 9, color: Colors.white54),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  Widget _telemetryDivider() {
    return Container(
      width: 1,
      height: 14,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Colors.white.withValues(alpha: 0.12),
    );
  }

  Widget _buildBottomBar(bool armed, int spray) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        border: Border(top: BorderSide(color: Colors.grey[800]!, width: 1)),
      ),
      child: Row(
        children: [
          // 解锁/上锁按钮
          SizedBox(
            width: 64,
            height: 36,
            child: ElevatedButton(
              onPressed: () {
                final wasArmed = _udp.armed;
                _udp.toggleArmed();
                _udp.setThrottle(0);
                _throttleValue = 0;
                setState(() {});
                VoiceService.instance.speak(
                  wasArmed ? '已上锁' : '已解锁',
                  priority: VoicePriority.status,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: armed ? AppColors.accent : AppColors.primary,
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(
                armed ? '上锁' : '解锁',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // 缩短后的解锁状态框
          SizedBox(
            width: 54,
            height: 36,
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              decoration: BoxDecoration(
                color: (armed ? AppColors.success : Colors.grey).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: (armed ? AppColors.success : Colors.grey).withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
              child: Text(
                armed ? '已解锁' : '已上锁',
                maxLines: 1,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  color: armed ? AppColors.success : Colors.grey,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // 起飞
          SizedBox(
            width: 56,
            height: 36,
            child: ElevatedButton(
              onPressed: _handleTakeoff,
              style: ElevatedButton.styleFrom(
                backgroundColor: armed ? AppColors.info : Colors.grey[700],
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text(
                '起飞',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 中间遥测数据
          Expanded(child: _buildTelemetryStrip()),
          const SizedBox(width: 8),
          // 急停：立即上锁并收油
          SizedBox(
            width: 64,
            height: 36,
            child: ElevatedButton(
              onPressed: armed
                  ? () {
                      _udp.setArmed(false);
                      _udp.setThrottle(0);
                      _throttleValue = 0;
                      setState(() {});
                      VoiceService.instance.speak(
                        '急停，已上锁',
                        priority: VoicePriority.alert,
                      );
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                disabledBackgroundColor: Colors.grey[800],
              ),
              child: const Text(
                '急停',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 喷洒力度按钮 (6挡)
          SizedBox(
            width: 56,
            height: 36,
            child: ElevatedButton(
              onPressed: () {
                VoiceService.instance.speak(
                  '当前喷洒力度${_udp.sprayLevel}挡',
                  priority: VoicePriority.status,
                );
                _showSprayLevelPicker();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning.withValues(alpha: 0.25),
                foregroundColor: AppColors.warning,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: AppColors.warning.withValues(alpha: 0.5)),
                ),
              ),
              child: Text(
                '力度${_udp.sprayLevel}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 喷洒按钮
          SizedBox(
            width: 56,
            height: 36,
            child: ElevatedButton(
              onPressed: () {
                final wasSpraying = spray > 0;
                _udp.toggleSpray();
                setState(() {});
                VoiceService.instance.speak(
                  wasSpraying
                      ? '停止喷洒'
                      : '开始喷洒，当前力度${_udp.sprayLevel}挡',
                  priority: VoicePriority.status,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: spray > 0 ? AppColors.info : Colors.grey[700],
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(
                spray > 0 ? '停喷' : '喷洒',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 状态指示灯
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: armed ? AppColors.success : AppColors.error,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            armed ? '解锁' : '锁定',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: armed ? AppColors.success : AppColors.error,
            ),
          ),
        ],
      ),
    );
  }
}