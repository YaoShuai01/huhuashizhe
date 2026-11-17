import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/preset_provider.dart';

class PresetFormPage extends ConsumerStatefulWidget {
  final Map<String, dynamic>? existingPreset;

  const PresetFormPage({super.key, this.existingPreset});

  @override
  ConsumerState<PresetFormPage> createState() => _PresetFormPageState();
}

class _PresetFormPageState extends ConsumerState<PresetFormPage> {
  late TextEditingController _nameCtrl;
  late String _cropType;
  late String _operationType;
  late double _flightHeight;
  late double _flightSpeed;
  late double _sprayVolume;
  late double _sprayWidth;

  final _cropTypes = ['水稻', '小麦', '玉米', '棉花', '果树', '蔬菜', '茶叶', '油菜'];
  final _operationTypes = ['杀虫', '除草', '施肥', '播种', '调节'];

  bool get isEditing => widget.existingPreset != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existingPreset;
    _nameCtrl = TextEditingController(text: p?['name'] ?? '');
    _cropType = p?['cropType'] ?? '水稻';
    _operationType = p?['operationType'] ?? '杀虫';
    _flightHeight = (p?['flightHeight'] ?? 2.5).toDouble();
    _flightSpeed = (p?['flightSpeed'] ?? 5.0).toDouble();
    _sprayVolume = (p?['sprayVolume'] ?? 1.5).toDouble();
    _sprayWidth = (p?['sprayWidth'] ?? 6.0).toDouble();
  }

  void _save() {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入预设名称')),
      );
      return;
    }

    final preset = {
      'name': _nameCtrl.text.trim(),
      'cropType': _cropType,
      'operationType': _operationType,
      'flightHeight': _flightHeight,
      'flightSpeed': _flightSpeed,
      'sprayVolume': _sprayVolume,
      'sprayWidth': _sprayWidth,
      'isAiGenerated': false,
      'updatedAt': DateTime.now().toIso8601String(),
    };

    if (isEditing) {
      ref.read(presetsProvider.notifier).updatePreset(
            widget.existingPreset!['id'],
            preset,
          );
    } else {
      ref.read(presetsProvider.notifier).addPreset(preset);
    }

    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? '编辑预设' : '新建预设'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('保存', style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildTextField('预设名称', _nameCtrl, '例如：水稻除草方案'),
            const SizedBox(height: 16),
            _buildSelector('作物类型', _cropType, _cropTypes, (v) => setState(() => _cropType = v!)),
            const SizedBox(height: 16),
            _buildSelector('作业类型', _operationType, _operationTypes, (v) => setState(() => _operationType = v!)),
            const SizedBox(height: 24),
            _buildSliderCard('飞行高度', _flightHeight, 1.0, 10.0, 'm', (v) => setState(() => _flightHeight = v)),
            const SizedBox(height: 12),
            _buildSliderCard('飞行速度', _flightSpeed, 1.0, 15.0, 'm/s', (v) => setState(() => _flightSpeed = v)),
            const SizedBox(height: 12),
            _buildSliderCard('喷洒量', _sprayVolume, 0.5, 5.0, 'L/亩', (v) => setState(() => _sprayVolume = v)),
            const SizedBox(height: 12),
            _buildSliderCard('喷幅', _sprayWidth, 2.0, 10.0, 'm', (v) => setState(() => _sprayWidth = v)),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
      ),
    );
  }

  Widget _buildSelector(String label, String value, List<String> items, ValueChanged<String?> onChange) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(labelText: label),
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 15)))).toList(),
      onChanged: onChange,
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
                    style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.primary)),
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

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }
}