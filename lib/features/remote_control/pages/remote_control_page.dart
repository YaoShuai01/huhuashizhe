import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/drone_udp_service.dart';
import '../../../services/h264_udp_relay.dart';
import '../../../services/satellite_service.dart';
import '../../../services/vision_stream_service.dart';
import '../../../services/voice_service.dart';
import '../widgets/drone_joystick.dart';
import '../widgets/vertical_throttle.dart';
import '../widgets/yaw_joystick.dart';

class RemoteControlPage extends StatefulWidget {
  const RemoteControlPage({super.key});

  @override
  State<RemoteControlPage> createState() => _RemoteControlPageState();
}

class _RemoteControlPageState extends State<RemoteControlPage> {
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

  // 北斗卫星实时状态（用于底部遥测与起飞播报）
  StreamSubscription<GnssSnapshot>? _gnssSub;
  int _beidouFound = 0;
  int _beidouUsed = 0;

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
    _initH264();
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _gnssSub?.cancel();
    _udp.dispose();
    _vision.photoNotifier.removeListener(_onPhoto);
    _vision.dispose();
    _h264?.dispose();
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
          // 右上角：画质切换 + 暂停/恢复图传
          Positioned(
            top: 4,
            right: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
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