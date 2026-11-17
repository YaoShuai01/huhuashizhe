import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/preset_provider.dart';

class PresetTuningPage extends ConsumerStatefulWidget {
  final Map<String, dynamic> preset;

  const PresetTuningPage({super.key, required this.preset});

  @override
  ConsumerState<PresetTuningPage> createState() => _PresetTuningPageState();
}

class _PresetTuningPageState extends ConsumerState<PresetTuningPage> {
  late double _flightHeight;
  late double _flightSpeed;
  late double _sprayVolume;
  late double _sprayWidth;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    final p = widget.preset;
    _flightHeight = (p['flightHeight'] ?? 2.5).toDouble();
    _flightSpeed = (p['flightSpeed'] ?? 5.0).toDouble();
    _sprayVolume = (p['sprayVolume'] ?? 1.5).toDouble();
    _sprayWidth = (p['sprayWidth'] ?? 6.0).toDouble();
  }

  void _markChanged(double _) {
    if (!_hasChanges) setState(() => _hasChanges = true);
  }

  void _saveTuning() {
    final updated = Map<String, dynamic>.from(widget.preset);
    updated['flightHeight'] = _flightHeight;
    updated['flightSpeed'] = _flightSpeed;
    updated['sprayVolume'] = _sprayVolume;
    updated['sprayWidth'] = _sprayWidth;
    updated['updatedAt'] = DateTime.now().toIso8601String();

    ref.read(presetsProvider.notifier).updatePreset(widget.preset['id'], updated);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('微调参数已保存')),
    );
    setState(() => _hasChanges = false);
  }

  void _usePreset() {
    // 保存当前微调（如有修改），然后跳转到地图选择
    if (_hasChanges) {
      final updated = Map<String, dynamic>.from(widget.preset);
      updated['flightHeight'] = _flightHeight;
      updated['flightSpeed'] = _flightSpeed;
      updated['sprayVolume'] = _sprayVolume;
      updated['sprayWidth'] = _sprayWidth;
      updated['updatedAt'] = DateTime.now().toIso8601String();
      ref.read(presetsProvider.notifier).updatePreset(widget.preset['id'], updated);
    }
    context.push('/mission/map', extra: {
      'flightHeight': _flightHeight,
      'flightSpeed': _flightSpeed,
      'sprayVolume': _sprayVolume,
      'sprayWidth': _sprayWidth,
      'cropType': widget.preset['cropType'] ?? '水稻',
      'operationType': widget.preset['operationType'] ?? '杀虫',
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.preset['name'] ?? '未命名预设';
    final cropType = widget.preset['cropType'] ?? '-';
    final operationType = widget.preset['operationType'] ?? '-';

    return Scaffold(
      appBar: AppBar(
        title: const Text('微调参数'),
        actions: [
          if (_hasChanges)
            TextButton(
              onPressed: _saveTuning,
              child: const Text('保存', style: TextStyle(color: Colors.white, fontSize: 16)),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 预设信息卡片
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.tune, color: AppColors.primary, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _infoChip(cropType),
                        const SizedBox(width: 8),
                        _infoChip(operationType),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text('拖动滑块微调参数', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
            ),
            const SizedBox(height: 8),
            _buildSliderCard('飞行高度', _flightHeight, 1.0, 10.0, 'm', (v) { setState(() => _flightHeight = v); _markChanged(v); }),
            const SizedBox(height: 12),
            _buildSliderCard('飞行速度', _flightSpeed, 1.0, 15.0, 'm/s', (v) { setState(() => _flightSpeed = v); _markChanged(v); }),
            const SizedBox(height: 12),
            _buildSliderCard('喷洒量', _sprayVolume, 0.5, 5.0, 'L/亩', (v) { setState(() => _sprayVolume = v); _markChanged(v); }),
            const SizedBox(height: 12),
            _buildSliderCard('喷幅', _sprayWidth, 2.0, 10.0, 'm', (v) { setState(() => _sprayWidth = v); _markChanged(v); }),
            const SizedBox(height: 24),
            // 使用此预设按钮
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _usePreset,
                icon: const Icon(Icons.flight_takeoff),
                label: const Text('使用此预设', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryDark,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildSliderCard(
      String label, double value, double min, double max, String unit, ValueChanged<double> onChange) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
                Text('${value.toStringAsFixed(1)} $unit',
                    style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.primary, fontSize: 16)),
              ],
            ),
            Slider(
              value: value,
              min: min,
              max: max,
              divisions: ((max - min) * 10).toInt(),
              activeColor: AppColors.primary,
              onChanged: onChange,
            ),
          ],
        ),
      ),
    );
  }
}