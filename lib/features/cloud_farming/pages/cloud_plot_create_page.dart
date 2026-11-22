import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../models/cloud_models.dart';
import '../services/cloud_engine.dart';
import '../services/cloud_farm_controller.dart';
import '../widgets/cloud_map.dart';
import '../widgets/cloud_widgets.dart';

class CloudPlotCreatePage extends ConsumerStatefulWidget {
  const CloudPlotCreatePage({super.key});

  @override
  ConsumerState<CloudPlotCreatePage> createState() => _CloudPlotCreatePageState();
}

class _CloudPlotCreatePageState extends ConsumerState<CloudPlotCreatePage> {
  final MapController _map = MapController();
  final TextEditingController _name = TextEditingController();
  final List<List<double>> _points = [];
  String _soil = 'loam';
  String _irrigation = 'drip';
  bool _locating = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  double get _area => CloudEngine.areaMu(_points);
  int get _perimeter => CloudEngine.perimeterM(_points);

  void _addPoint(List<double> point) {
    setState(() {
      _points.add(point);
      if (_points.length >= 3 && _name.text.isEmpty) {
        final n = ref.read(cloudFarmProvider).plots.length + 1;
        _name.text = '新田块 $n';
      }
    });
  }

  /// 按住顶点拖动：实时改坐标，面积/周长随 build 重算
  void _movePoint(int index, List<double> point) {
    if (index < 0 || index >= _points.length) return;
    setState(() => _points[index] = point);
  }

  void _autoDetect() {
    final c = ref.read(cloudFarmProvider);
    final pts = CloudEngine.autoDetectPoints(c.plots.length);
    setState(() {
      _points
        ..clear()
        ..addAll(pts);
      if (_name.text.isEmpty) _name.text = '新田块 ${c.plots.length + 1}';
    });
    final center = centroidOf(pts);
    _map.move(displayPoint(center.latitude, center.longitude), 17);
    _toast('已生成示例边界，请拖动或用定位校正');
  }

  Future<void> _locate() async {
    if (_locating) return;
    setState(() => _locating = true);
    final c = ref.read(cloudFarmProvider);
    final result = await c.locate();
    if (!mounted) return;
    setState(() => _locating = false);
    if (result.ok) {
      _map.move(LatLng(c.location.lat, c.location.lng), 16);
      _toast(result.message ?? '已回到当前位置');
    } else {
      _toast(result.message ?? '定位失败，可在农场页手动修改位置');
    }
  }

  void _save() {
    if (_points.length < 3 || _area <= 0) {
      _toast('请先在地图上圈出至少 3 个边界点');
      return;
    }
    final name = _name.text.trim().isEmpty
        ? '新田块 ${ref.read(cloudFarmProvider).plots.length + 1}'
        : _name.text.trim();
    final plot = ref.read(cloudFarmProvider).addPlot(
          name: name,
          polygon: List<List<double>>.from(_points),
          area: _area,
          soil: _soil,
          irrigation: _irrigation,
        );
    context.pushReplacement('/cloud-farm/plant', extra: {'plotId': plot.id});
  }

  @override
  Widget build(BuildContext context) {
    final hasArea = _points.length >= 3;
    final location = ref.watch(cloudFarmProvider).location;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('圈地建模'),
            const SizedBox(height: 2),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 210),
              child: Text(
                _locationStatus(location),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: Colors.white70),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _autoDetect,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text('自动识别', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: CloudFarmMap(
                    plots: ref.watch(cloudFarmProvider).plots,
                    drawPoints: _points,
                    mapController: _map,
                    center: LatLng(location.lat, location.lng),
                    zoom: 16,
                    onAddPoint: _addPoint,
                    onMovePoint: _movePoint,
                  ),
                ),
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.58),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.touch_app_outlined,
                            size: 12, color: Color(0xFF9BE7A4)),
                        const SizedBox(width: 4),
                        Text(
                          hasArea
                              ? '${_points.length} 个边界点 · 点击加点，按住顶点可拖动微调'
                              : '点击地图添加边界点，按住顶点可拖动微调',
                          style: const TextStyle(fontSize: 10, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.58),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          hasArea ? '${_area.toStringAsFixed(1)} 亩' : '-- 亩',
                          style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white,
                              fontWeight: FontWeight.w700),
                        ),
                        Text(
                          hasArea ? '周长 ${_perimeter}m' : '等待圈定',
                          style: const TextStyle(fontSize: 9.5, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  bottom: 10,
                  child: Row(
                    children: [
                      _toolBtn(
                        icon: Icons.undo,
                        label: '撤销',
                        enabled: _points.isNotEmpty,
                        onTap: () => setState(() => _points.removeLast()),
                      ),
                      const SizedBox(width: 6),
                      _toolBtn(
                        icon: Icons.delete_outline,
                        label: '清空',
                        enabled: _points.isNotEmpty,
                        onTap: () => setState(() => _points.clear()),
                      ),
                      const SizedBox(width: 6),
                      _toolBtn(
                        icon: Icons.my_location,
                        label: _locating ? '定位中' : '定位',
                        enabled: !_locating,
                        onTap: _locate,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              border: Border(
                top: BorderSide(
                    color:
                        Theme.of(context).dividerColor.withValues(alpha: 0.5)),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('田块名称',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text(
                        hasArea
                            ? '${_points.length} 点 · ${_area.toStringAsFixed(2)} 亩 · 边界 ${_perimeter}m'
                            : '至少 3 个点',
                        style: TextStyle(
                            fontSize: 10, color: cloudHint(context)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _name,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: '如：东坡油菜田',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const SizedBox(
                        width: 42,
                        child: Text('土壤', style: TextStyle(fontSize: 11.5)),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final s in CloudSeed.soils.values) ...[
                                CloudPillButton(
                                  text: s.name,
                                  active: _soil == s.key,
                                  onTap: () => setState(() => _soil = s.key),
                                ),
                                const SizedBox(width: 5),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      const SizedBox(
                        width: 42,
                        child: Text('灌溉', style: TextStyle(fontSize: 11.5)),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final i in CloudSeed.irrigations.values) ...[
                                CloudPillButton(
                                  text: i.name,
                                  active: _irrigation == i.key,
                                  onTap: () =>
                                      setState(() => _irrigation = i.key),
                                ),
                                const SizedBox(width: 5),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: hasArea ? _save : null,
                      icon: const Icon(Icons.check, size: 17),
                      label: const Text('保存边界，下一步选择作物'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _locationStatus(CloudLocation loc) {
    if (loc.isSeed) return '未定位 · 点击下方定位';
    final name = loc.name.isEmpty ? '未定位' : loc.name;
    return '$name · ${loc.fromGps ? '已定位' : '手动位置'}';
  }

  Widget _toolBtn({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.black.withValues(alpha: enabled ? 0.58 : 0.28),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 13, color: Colors.white),
              const SizedBox(width: 3),
              Text(label,
                  style: const TextStyle(fontSize: 10, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }
}
