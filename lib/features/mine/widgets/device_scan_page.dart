import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class DeviceScanPage extends StatefulWidget {
  const DeviceScanPage({super.key});

  @override
  State<DeviceScanPage> createState() => _DeviceScanPageState();
}

class _DeviceScanPageState extends State<DeviceScanPage> {
  bool _isScanning = false;
  final List<Map<String, String>> _devices = [];

  void _startScan() {
    setState(() => _isScanning = true);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _devices.addAll([
            {'name': '护花使者-遥控器-001', 'id': 'AA:BB:CC:DD:EE:01', 'rssi': '-45'},
            {'name': '护花使者-遥控器-002', 'id': 'AA:BB:CC:DD:EE:02', 'rssi': '-62'},
          ]);
        });
      }
    });
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
          if (_isScanning)
            const LinearProgressIndicator(),
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
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _devices.length,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemBuilder: (context, index) {
                      final d = _devices[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: ListTile(
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.bluetooth, color: AppColors.primary),
                          ),
                          title: Text(d['name']!,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                          subtitle: Text('${d['id']}  信号: ${d['rssi']} dBm',
                              style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
                          trailing: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context, d);
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
}