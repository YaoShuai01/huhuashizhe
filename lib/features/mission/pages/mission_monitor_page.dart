import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/device_provider.dart';

class MissionMonitorPage extends ConsumerStatefulWidget {
  final String missionId;
  final String missionName;
  final List<Map<String, double>> waypoints;

  const MissionMonitorPage({
    super.key,
    required this.missionId,
    required this.missionName,
    required this.waypoints,
  });

  @override
  ConsumerState<MissionMonitorPage> createState() => _MissionMonitorPageState();
}

class _MissionMonitorPageState extends ConsumerState<MissionMonitorPage> {
  bool _isFlying = false;
  bool _isSpraying = false;

  @override
  Widget build(BuildContext context) {
    final deviceStatus = ref.watch(deviceStatusProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.missionName),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // 地图占位
          Expanded(
            flex: 3,
            child: Container(
              color: AppColors.background,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.videocam_outlined, size: 64, color: AppColors.textDisabled.withValues(alpha: 0.3)),
                    const SizedBox(height: 16),
                    Text(
                      '实时监控画面',
                      style: TextStyle(fontSize: 18, color: AppColors.textHint, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '航点数量: ${widget.waypoints.length}',
                      style: TextStyle(fontSize: 13, color: AppColors.textDisabled),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 状态面板
          Expanded(
            flex: 2,
            child: Container(
              color: AppColors.surface,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildStatusBar(deviceStatus),
                    const SizedBox(height: 12),
                    _buildInfoGrid(deviceStatus),
                    const SizedBox(height: 16),
                    _buildControlButtons(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(DeviceStatus? status) {
    final isConnected = status?.isConnected ?? false;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isConnected ? AppColors.primary.withValues(alpha: 0.1) : AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            isConnected ? Icons.check_circle : Icons.error_outline,
            color: isConnected ? AppColors.primary : AppColors.error,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            isConnected ? '设备已连接: ${status!.deviceName}' : '未连接设备',
            style: TextStyle(
              color: isConnected ? AppColors.primary : AppColors.error,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          Text(
            '信号: ${status?.signalStrength ?? 0}%',
            style: TextStyle(
              color: (status?.signalStrength ?? 0) > 30 ? AppColors.primary : AppColors.warning,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoGrid(DeviceStatus? status) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.3,
      children: [
        _infoTile('电量', '${status?.batteryLevel ?? 0}%', Icons.battery_5_bar),
        _infoTile('高度', '2.5 m', Icons.height),
        _infoTile('速度', '5.0 m/s', Icons.speed),
        _infoTile('喷洒量', '1.5 L/亩', Icons.water_drop),
        _infoTile('剩余药量', '20 L', Icons.water),
        _infoTile('GPS', '12颗', Icons.satellite),
      ],
    );
  }

  Widget _infoTile(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
        ],
      ),
    );
  }

  Widget _buildControlButtons() {
    return Row(
      children: [
        Expanded(
          child: _controlButton(
            _isFlying ? '暂停' : '起飞',
            _isFlying ? Icons.pause : Icons.flight_takeoff,
            _isFlying ? AppColors.warning : AppColors.primary,
            () => setState(() => _isFlying = !_isFlying),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _controlButton(
            _isSpraying ? '停止喷洒' : '开始喷洒',
            Icons.water_drop,
            _isSpraying ? AppColors.warning : AppColors.info,
            () => setState(() => _isSpraying = !_isSpraying),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _controlButton(
            '返航',
            Icons.flight_land,
            AppColors.accent,
            () {},
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.error,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            onPressed: () {
              setState(() {
                _isFlying = false;
                _isSpraying = false;
              });
            },
            icon: const Icon(Icons.stop, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _controlButton(String label, IconData icon, Color color, VoidCallback onPressed) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
