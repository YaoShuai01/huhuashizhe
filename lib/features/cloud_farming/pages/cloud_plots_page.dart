import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../models/cloud_models.dart';
import '../services/cloud_farm_controller.dart';
import '../widgets/cloud_map.dart';
import '../widgets/cloud_widgets.dart';

class CloudPlotsTab extends ConsumerStatefulWidget {
  const CloudPlotsTab({super.key});

  @override
  ConsumerState<CloudPlotsTab> createState() => _CloudPlotsTabState();
}

class _CloudPlotsTabState extends ConsumerState<CloudPlotsTab> {
  final MapController _map = MapController();
  final ValueNotifier<double> _zoom = ValueNotifier<double>(16);

  String? _selectedId;
  bool _legend = true;
  bool _showAnnotations = true;
  bool _layerPanel = false;
  bool _mapReady = false;
  bool _locating = false;
  String _plotSignature = '';

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  /// 选中项失效时回落到第一块田（与网页版一致）
  String? _effectiveId(CloudFarmController c) {
    if (_selectedId != null && c.plotById(_selectedId) != null) {
      return _selectedId;
    }
    return c.plots.isEmpty ? null : c.plots.first.id;
  }

  List<LatLng> _allPlotPoints(List<CloudPlot> plots) {
    final points = <LatLng>[];
    for (final plot in plots) {
      if (plot.polygon.length >= 3) {
        points.addAll(displayLatLngsOf(plot.polygon));
      }
    }
    return points;
  }

  void _handleMapReady() {
    _mapReady = true;
    if (mounted) _zoom.value = _map.camera.zoom;
  }

  /// 自动框住全部田块（padding 40）
  void _fitAllPlots(CloudFarmController c) {
    if (!_mapReady) return;
    final points = _allPlotPoints(c.plots);
    if (points.length < 2) return;
    _map.fitCamera(CameraFit.coordinates(
      coordinates: points,
      padding: const EdgeInsets.all(40),
      maxZoom: 18,
    ));
    _zoom.value = _map.camera.zoom;
  }

  void _focusPlot(CloudPlot plot) {
    setState(() => _selectedId = plot.id);
    if (!_mapReady || plot.polygon.length < 3) return;
    _map.fitCamera(CameraFit.coordinates(
      coordinates: displayLatLngsOf(plot.polygon),
      padding: const EdgeInsets.all(48),
      maxZoom: 18,
    ));
    _zoom.value = _map.camera.zoom;
  }

  Future<void> _locate() async {
    if (_locating) return;
    setState(() => _locating = true);
    final c = ref.read(cloudFarmProvider);
    final result = await c.locate();
    if (!mounted) return;
    setState(() => _locating = false);
    if (result.ok && _mapReady) {
      final loc = c.location;
      _map.move(LatLng(loc.lat, loc.lng), 17);
      _zoom.value = _map.camera.zoom;
    }
    _toast(result.message ??
        (result.ok ? '已定位到当前位置' : '定位失败，请检查定位权限后重试'));
  }

  void _zoomBy(double delta) {
    if (!_mapReady) return;
    final camera = _map.camera;
    final zoom = (camera.zoom + delta).clamp(3.0, 19.0);
    _map.move(camera.center, zoom);
    _zoom.value = _map.camera.zoom;
  }

  Future<void> _confirmDelete(CloudPlot plot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除田块'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${plot.name} · ${plot.area.toStringAsFixed(1)} 亩',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            const Text(
              '删除后 GPS 边界、作物档案与生长记录都会移除，且无法恢复。',
              style: TextStyle(fontSize: 12, height: 1.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD84343),
              foregroundColor: Colors.white,
            ),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final name = plot.name;
    ref.read(cloudFarmProvider).deletePlot(plot.id);
    if (!mounted) return;
    setState(() => _selectedId = null);
    _toast('已删除「$name」');
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 2),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(cloudFarmProvider);
    final selectedId = _effectiveId(c);
    final selected = c.plotById(selectedId);

    // 新建 / 删除田块后自动重新框选，避免田块落在视野外
    final signature =
        '${c.plots.length}:${c.plots.isEmpty ? '-' : c.plots.last.id}';
    if (_plotSignature.isNotEmpty && _plotSignature != signature) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _mapReady) {
          _fitAllPlots(ref.read(cloudFarmProvider));
        }
      });
    }
    _plotSignature = signature;

    final fitPoints = _allPlotPoints(c.plots);
    final location = LatLng(c.location.lat, c.location.lng);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.home_outlined),
          tooltip: '返回 App 首页',
          onPressed: () => context.go('/home'),
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text('田块地图'),
            SizedBox(height: 2),
            Text('1:1 建模 · GPS 边界与实体一致',
                style: TextStyle(fontSize: 10, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '新建田块',
            onPressed: () => context.push('/cloud-farm/create'),
            icon: const Icon(Icons.add),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: CloudFarmMap(
              plots: c.plots,
              selectedId: selectedId,
              mapController: _map,
              center: location,
              zoom: 16,
              cameraFit: fitPoints.length >= 2
                  ? CameraFit.coordinates(
                      coordinates: fitPoints,
                      padding: const EdgeInsets.all(40),
                      maxZoom: 18,
                    )
                  : null,
              onMapReady: _handleMapReady,
              onZoomChanged: (zoom) => _zoom.value = zoom,
              onSelectPlot: (id) => setState(() => _selectedId = id),
              showLabels: _showAnnotations,
            ),
          ),
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Row(
              children: [
                Expanded(child: _gpsChip(c)),
                const SizedBox(width: 6),
                _mapButton(
                  icon: _locating ? Icons.gps_not_fixed : Icons.my_location,
                  tooltip: '定位',
                  active: _locating,
                  onTap: _locate,
                ),
                if (c.plots.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  _mapButton(
                    icon: Icons.center_focus_strong,
                    tooltip: '回到田块',
                    onTap: () => _fitAllPlots(c),
                  ),
                ],
              ],
            ),
          ),
          if (_legend && c.plots.isNotEmpty)
            Positioned(
              top: 64,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _legendRow(const Color(0xFF6ED37C), '已种植'),
                    const SizedBox(height: 4),
                    _legendRow(const Color(0xFFFFD166), '当前选中'),
                    const SizedBox(height: 4),
                    _legendRow(const Color(0xFF9E9E9E), '待种植'),
                    if (_showAnnotations) ...[
                      const SizedBox(height: 4),
                      const Text('含道路与地名注记',
                          style:
                              TextStyle(fontSize: 9, color: Colors.white70)),
                    ],
                  ],
                ),
              ),
            ),
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_layerPanel) ...[
                    Align(
                      alignment: Alignment.centerRight,
                      child: _layerPanelWidget(),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _MapScaleBar(zoom: _zoom, latitude: c.location.lat),
                      const Spacer(),
                      _mapControls(),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (c.plots.isNotEmpty) ...[
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final plot in c.plots) ...[
                            CloudPillButton(
                              text:
                                  '${plot.name} · ${plot.area.toStringAsFixed(1)}亩',
                              active: plot.id == selectedId,
                              onTap: () => _focusPlot(plot),
                            ),
                            const SizedBox(width: 6),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (selected == null)
                    _emptyCard(context)
                  else
                    _plotSheet(context, c, selected),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gpsChip(CloudFarmController c) {
    final loc = c.location;
    final failed = c.lastLocateError != null;
    final title = loc.isSeed
        ? (failed ? '未定位 · 定位失败' : '未定位 · 点击定位')
        : (loc.name.isEmpty ? '已定位' : loc.name);
    final accuracy = loc.isSeed || loc.accuracy == null
        ? '精度未知'
        : '±${loc.accuracy!.round()}m';
    final subtitle =
        '${loc.lat.toStringAsFixed(4)}°N ${loc.lng.toStringAsFixed(4)}°E · $accuracy';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            failed ? Icons.gps_off : Icons.gps_fixed,
            size: 13,
            color: const Color(0xFF9BE7A4),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 10.5,
                      color: Colors.white,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color:
            active ? const Color(0xFF2E7D32) : Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(icon, size: 17, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _mapControls() {
    return Material(
      color: Colors.black.withValues(alpha: 0.58),
      borderRadius: BorderRadius.circular(18),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _controlButton(
            icon: Icons.layers_outlined,
            tooltip: '图层',
            active: _layerPanel,
            onTap: () => setState(() => _layerPanel = !_layerPanel),
          ),
          _controlDivider(),
          _controlButton(
            icon: Icons.add,
            tooltip: '放大',
            onTap: () => _zoomBy(1),
          ),
          _controlDivider(),
          _controlButton(
            icon: Icons.remove,
            tooltip: '缩小',
            onTap: () => _zoomBy(-1),
          ),
        ],
      ),
    );
  }

  Widget _layerPanelWidget() {
    return Material(
      color: Colors.black.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '地图图层',
              style: TextStyle(
                  fontSize: 9.5,
                  color: Colors.white70,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            _layerToggleRow(
              label: '地点注记',
              value: _showAnnotations,
              onTap: () =>
                  setState(() => _showAnnotations = !_showAnnotations),
            ),
            const SizedBox(height: 2),
            _layerToggleRow(
              label: '图例',
              value: _legend,
              onTap: () => setState(() => _legend = !_legend),
            ),
          ],
        ),
      ),
    );
  }

  Widget _layerToggleRow({
    required String label,
    required bool value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 15,
              height: 15,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: value ? const Color(0xFF2E7D32) : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: value ? const Color(0xFF9BE7A4) : Colors.white54,
                  width: 1.2,
                ),
              ),
              child: value
                  ? const Icon(Icons.check, size: 11, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 7),
            Text(label,
                style: const TextStyle(fontSize: 10.5, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 18,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(
            icon,
            size: 17,
            color: active ? const Color(0xFF9BE7A4) : Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _controlDivider() {
    return Container(
      width: 1,
      height: 16,
      color: Colors.white.withValues(alpha: 0.22),
    );
  }

  Widget _legendRow(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(fontSize: 9.5, color: Colors.white)),
      ],
    );
  }

  Widget _emptyCard(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return CloudCard(
      padding: const EdgeInsets.fromLTRB(16, 26, 16, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.map_outlined, size: 32, color: primary),
          const SizedBox(height: 8),
          const Text('还没有田块',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            '圈出第一块田，即可开始云种植',
            style: TextStyle(fontSize: 10.5, color: cloudHint(context)),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => context.push('/cloud-farm/create'),
            icon: const Icon(Icons.add, size: 17),
            label: const Text('新建田块'),
          ),
        ],
      ),
    );
  }

  Widget _plotSheet(
      BuildContext context, CloudFarmController c, CloudPlot plot) {
    final growth = c.growth(plot);
    final moisture = c.moisture(plot);
    final crop = CloudSeed.cropOf(plot.cropId);
    final stage = growth != null ? '${growth.stage.name}期' : '待种植';
    return CloudCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PlotThumb(cropId: plot.cropId, width: 50, height: 50),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(plot.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 6),
                        CloudTag('${plot.area.toStringAsFixed(1)}亩',
                            color: Theme.of(context).colorScheme.primary),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      crop != null ? '${crop.name} · $stage' : '空闲田块 · 待种植',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 11, color: cloudSubtle(context)),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: [
                        CloudTag('墒情 ${moisture.value}%',
                            color: Theme.of(context).colorScheme.primary,
                            icon: Icons.water_drop_outlined),
                        CloudTag('播种 ${growth != null ? '第${growth.day}天' : '--'}',
                            color: cloudSubtle(context)),
                      ],
                    ),
                  ],
                ),
              ),
              CloudRing(pct: growth?.pct ?? 0, size: 46, stroke: 4.2),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      context.push('/cloud-farm/remote/${plot.id}'),
                  icon: const Icon(Icons.visibility_outlined, size: 15),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: EdgeInsets.zero,
                    textStyle: const TextStyle(fontSize: 11.5),
                  ),
                  label: const Text('异地查看'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => context.push('/cloud-farm/plot/${plot.id}'),
                  icon: const Icon(Icons.eco_outlined, size: 15),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: EdgeInsets.zero,
                    textStyle: const TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                  label: const Text('查看云田'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () => _confirmDelete(plot),
              icon: const Icon(Icons.delete_outline, size: 15),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFD84343),
                minimumSize: const Size(0, 34),
                padding: EdgeInsets.zero,
                textStyle: const TextStyle(fontSize: 11),
              ),
              label: const Text('删除此田块'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 随缩放变化的比例尺（约 90px 长，取 1/2/5 的整数档）
class _MapScaleBar extends StatelessWidget {
  final ValueListenable<double> zoom;
  final double latitude;

  const _MapScaleBar({required this.zoom, required this.latitude});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: zoom,
      builder: (context, z, _) {
        const earthCircumference = 40075016.686;
        final metersPerPixel = earthCircumference *
            math.cos(latitude * math.pi / 180) /
            (256 * math.pow(2, z));
        final meters = _niceDistance(90 * metersPerPixel);
        final width = (meters / metersPerPixel).clamp(24.0, 130.0);
        final label = meters >= 1000
            ? '${(meters / 1000).toStringAsFixed(meters % 1000 == 0 ? 0 : 1)} km'
            : '${meters.round()} m';
        return Container(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 9, color: Colors.white, height: 1.1)),
              const SizedBox(height: 4),
              SizedBox(
                width: width,
                height: 7,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(width: 1.5, height: 7, color: Colors.white),
                    Expanded(
                      child: Container(height: 1.2, color: Colors.white),
                    ),
                    Container(width: 1.5, height: 7, color: Colors.white),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  double _niceDistance(double target) {
    if (target <= 0) return 1;
    final exponent = (math.log(target) / math.ln10).floor();
    final base = math.pow(10, exponent).toDouble();
    for (final step in const [1.0, 2.0, 5.0]) {
      final candidate = base * step;
      if (candidate >= target) return candidate;
    }
    return base * 10;
  }
}
