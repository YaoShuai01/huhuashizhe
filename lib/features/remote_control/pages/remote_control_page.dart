import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/drone_udp_service.dart';
import '../widgets/drone_joystick.dart';

class RemoteControlPage extends StatefulWidget {
  const RemoteControlPage({super.key});

  @override
  State<RemoteControlPage> createState() => _RemoteControlPageState();
}

class _RemoteControlPageState extends State<RemoteControlPage> {
  final DroneUdpService _udp = DroneUdpService();

  @override
  void initState() {
    super.initState();
    // 强制横屏
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initUdp();
  }

  @override
  void dispose() {
    // 恢复默认方向
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _udp.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final armed = _udp.armed;
    final spray = _udp.spray;
    final screenSize = MediaQuery.of(context).size;
    // 横屏下以高度为基准计算摇杆大小（高度是限制因素）
    final joystickSize = (screenSize.height * 0.55).clamp(100.0, 160.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // 主体布局：左摇杆 | 监控画面 | 右摇杆
            Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4, right: 4, top: 2, bottom: 2),
                    child: Row(
                      children: [
                        // 左摇杆（油门/偏航）
                        Expanded(
                          flex: 4,
                          child: _buildLeftJoystick(joystickSize),
                        ),
                        const SizedBox(width: 4),
                        // 监控画面（居中）
                        Expanded(
                          flex: 7,
                          child: _buildCameraView(),
                        ),
                        const SizedBox(width: 4),
                        // 右摇杆（俯仰/横滚）
                        Expanded(
                          flex: 4,
                          child: _buildRightJoystick(joystickSize),
                        ),
                      ],
                    ),
                  ),
                ),
                // 底部控制栏
                _buildBottomBar(armed, spray),
              ],
            ),
            // 左上角：设置 + 退出图标（悬浮在最上层）
            Positioned(
              top: 4,
              left: 8,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildIconButton(Icons.settings, '设置', _showSettings),
                  const SizedBox(width: 4),
                  _buildIconButton(Icons.exit_to_app, '退出', _showExitConfirm),
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

  Widget _buildLeftJoystick(double size) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('油门 / 偏航', style: TextStyle(fontSize: 11, color: Colors.white54)),
        const SizedBox(height: 4),
        DroneJoystick(
          labelX: '偏航',
          labelY: '油门',
          size: size,
          color: AppColors.primary,
          onChanged: (x, y) {
            _udp.setYaw(x.round());
            _udp.setThrottle(y.round());
          },
          onReleased: () {
            _udp.setYaw(0);
            _udp.setThrottle(0);
          },
        ),
        const SizedBox(height: 4),
        Text(
          'T:${_udp.throttle.toString().padLeft(3)} Y:${_udp.yaw.toString().padLeft(3)}',
          style: const TextStyle(fontSize: 10, color: Colors.white38, fontFamily: 'monospace'),
        ),
      ],
    );
  }

  Widget _buildRightJoystick(double size) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('俯仰 / 横滚', style: TextStyle(fontSize: 11, color: Colors.white54)),
        const SizedBox(height: 4),
        DroneJoystick(
          labelX: '横滚',
          labelY: '俯仰',
          size: size,
          color: AppColors.accent,
          onChanged: (x, y) {
            _udp.setRoll(x.round());
            _udp.setPitch(y.round());
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

  Widget _buildCameraView() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[800]!, width: 1),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_outlined, size: 40, color: Colors.grey[700]),
            const SizedBox(height: 8),
            Text('摄像头未连接', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            const SizedBox(height: 4),
            Text('FPV画面将在此显示', style: TextStyle(color: Colors.grey[800], fontSize: 10)),
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
      ),
    );
  }

  Widget _buildIconButton(IconData icon, String tooltip, VoidCallback onTap) {
    return Material(
      color: Colors.black45,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: Colors.white70, size: 18),
        ),
      ),
    );
  }

  Widget _buildBottomBar(bool armed, bool spray) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        border: Border(top: BorderSide(color: Colors.grey[800]!, width: 1)),
      ),
      child: Row(
        children: [
          // 解锁/上锁按钮
          Expanded(
            child: SizedBox(
              height: 36,
              child: ElevatedButton.icon(
                onPressed: () {
                  _udp.toggleArmed();
                  setState(() {});
                },
                icon: Icon(armed ? Icons.lock_open : Icons.lock_outline, size: 16),
                label: Text(
                  armed ? '上锁' : '解锁',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: armed ? AppColors.accent : AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 喷洒按钮
          Expanded(
            child: SizedBox(
              height: 36,
              child: ElevatedButton.icon(
                onPressed: () {
                  _udp.toggleSpray();
                  setState(() {});
                },
                icon: Icon(spray ? Icons.water_drop : Icons.water_drop_outlined, size: 16),
                label: Text(
                  spray ? '停止喷洒' : '喷洒',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: spray ? AppColors.info : Colors.grey[700],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 状态指示灯
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: armed ? AppColors.success : AppColors.error,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            armed ? '已解锁' : '已上锁',
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