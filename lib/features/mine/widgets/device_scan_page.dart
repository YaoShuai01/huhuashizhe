import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/bluetooth_service.dart';

class DeviceScanPage extends StatefulWidget {
  const DeviceScanPage({super.key});

  @override
  State<DeviceScanPage> createState() => _DeviceScanPageState();
}

class _DeviceScanPageState extends State<DeviceScanPage> {
  final BluetoothService _bluetoothService = BluetoothService();
  bool _isScanning = false;
  bool _bluetoothEnabled = true;
  String _errorMessage = '';
  final List<DiscoveredDevice> _devices = [];
  StreamSubscription<DiscoveredDevice>? _deviceSub;
  StreamSubscription? _scanCompleteSub;
  Timer? _errorTimer;

  @override
  void initState() {
    super.initState();
    _bluetoothService.init();
    _deviceSub = _bluetoothService.deviceStream.listen(_onDeviceFound);
    _scanCompleteSub = _bluetoothService.scanCompleteStream.listen((_) {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    });
    _checkBluetooth();
  }

  Future<void> _checkBluetooth() async {
    final enabled = await _bluetoothService.isBluetoothEnabled();
    if (mounted) {
      setState(() => _bluetoothEnabled = enabled);
    }
  }

  void _onDeviceFound(DiscoveredDevice device) {
    if (!mounted) return;
    setState(() {
      // 避免重复添加同一设备
      final exists = _devices.any((d) => d.address == device.address);
      if (!exists) {
        _devices.add(device);
        // 按信号强度排序
        _devices.sort((a, b) => b.rssi.compareTo(a.rssi));
      }
    });
  }

  void _showError(String message) {
    _errorTimer?.cancel();
    setState(() => _errorMessage = message);
    _errorTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _errorMessage = '');
      }
    });
  }

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _devices.clear();
      _errorMessage = '';
    });

    try {
      final success = await _bluetoothService.startScan();
      if (!success && mounted) {
        setState(() => _isScanning = false);
        _showError('扫描启动失败，请检查蓝牙权限');
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => _isScanning = false);
        if (e.code == 'BT_DISABLED') {
          _bluetoothEnabled = false;
          _showError('蓝牙未开启，请先打开蓝牙');
        } else {
          _showError('扫描失败: ${e.message}');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isScanning = false);
        _showError('扫描失败: $e');
      }
    }
  }

  @override
  void dispose() {
    _deviceSub?.cancel();
    _scanCompleteSub?.cancel();
    _errorTimer?.cancel();
    _bluetoothService.stopScan();
    _bluetoothService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设备连接')),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: AppColors.surface,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _isScanning ? '正在扫描蓝牙设备...' : '${_devices.length} 个设备已发现',
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _isScanning ? null : _startScan,
                  icon: Icon(_isScanning ? Icons.hourglass_empty : Icons.bluetooth_searching),
                  label: Text(_isScanning ? '扫描中...' : '扫描设备'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    minimumSize: Size.zero,
                  ),
                ),
              ],
            ),
          ),
          if (!_bluetoothEnabled)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '蓝牙未开启，请在系统设置中打开蓝牙后重试',
                      style: TextStyle(fontSize: 13, color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),
          if (_errorMessage.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_errorMessage, style: const TextStyle(fontSize: 13, color: Colors.red)),
                  ),
                ],
              ),
            ),
          if (_isScanning) const LinearProgressIndicator(),
          Expanded(
            child: _devices.isEmpty && !_isScanning
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bluetooth_disabled, size: 64, color: AppColors.textDisabled.withValues(alpha: 0.5)),
                        const SizedBox(height: 16),
                        const Text('未发现设备', style: TextStyle(fontSize: 16, color: AppColors.textHint)),
                        const SizedBox(height: 8),
                        const Text('请确保遥控器已开机且蓝牙可见',
                            style: TextStyle(fontSize: 13, color: AppColors.textDisabled)),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _startScan,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('重新扫描'),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _devices.length,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemBuilder: (context, index) {
                      final d = _devices[index];
                      final signalIcon = _getSignalIcon(d.rssi);
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: ListTile(
                          leading: Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              d.isBonded ? Icons.bluetooth_connected : Icons.bluetooth,
                              color: d.isBonded ? AppColors.primary : AppColors.textSecondary,
                            ),
                          ),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(d.name,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                    overflow: TextOverflow.ellipsis),
                              ),
                              if (d.isBonded) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('已配对', style: TextStyle(fontSize: 10, color: AppColors.primary)),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Row(
                            children: [
                              Flexible(
                                child: Text(d.address,
                                    style: const TextStyle(fontSize: 12, color: AppColors.textHint),
                                    overflow: TextOverflow.ellipsis),
                              ),
                              const SizedBox(width: 6),
                              signalIcon,
                              const SizedBox(width: 3),
                              Text(d.signalStrengthDisplay,
                                  style: TextStyle(fontSize: 12, color: _getSignalColor(d.rssi))),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceVariant,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(d.type, style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
                              ),
                            ],
                          ),
                          trailing: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context, d.toJson());
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              minimumSize: Size.zero,
                            ),
                            child: const Text('连接', style: TextStyle(fontSize: 13)),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _getSignalIcon(int rssi) {
    if (rssi >= -50) return const Icon(Icons.signal_cellular_alt, size: 14, color: Colors.green);
    if (rssi >= -70) return const Icon(Icons.signal_cellular_alt_2_bar, size: 14, color: Colors.orange);
    return const Icon(Icons.signal_cellular_alt_1_bar, size: 14, color: Colors.red);
  }

  Color _getSignalColor(int rssi) {
    if (rssi >= -50) return Colors.green;
    if (rssi >= -70) return Colors.orange;
    return Colors.red;
  }
}