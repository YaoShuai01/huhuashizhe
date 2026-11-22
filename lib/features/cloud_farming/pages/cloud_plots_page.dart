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
  String? _selectedId;
  bool _legend = true;

  CloudPlot? _selected(CloudFarmController c) {
    if (_selectedId == null) return null;
    return c.plotById(_selectedId);
  }

  void _select(CloudFarmController c, String? id) {
    setState(() => _selectedId = id);
    if (id != null) {
      final plot = c.plotById(id);
      if (plot != null && plot.polygon.length >= 3) {
        _map.move(centroidOf(plot.polygon), 17);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(cloudFarmProvider);
    final selected = _selected(c);

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
            tooltip: '圈地建模',
            onPressed: () => context.push('/cloud-farm/create'),
            icon: const Icon(Icons.add_circle_outline),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: CloudFarmMap(
              plots: c.plots,
              selectedId: _selectedId,
              mapController: _map,
              center: LatLng(c.location.lat, c.location.lng),
              zoom: 16,
              onSelectPlot: (id) => _select(c, id),
            ),
          ),
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Row(
              children: [
                Container(
                  constraints: const BoxConstraints(maxWidth: 230),
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.gps_fixed,
                          size: 12, color: Color(0xFF9BE7A4)),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _locationStatus(c),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 10, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                _mapButton(
                  icon: Icons.my_location,
                  onTap: () => _map.move(
                    LatLng(c.location.lat, c.location.lng),
                    16,
                  ),
                ),
                const SizedBox(width: 6),
                _mapButton(
                  icon: Icons.layers_outlined,
                  active: _legend,
                  onTap: () => setState(() => _legend = !_legend),
                ),
              ],
            ),
          ),
          if (_legend)
            Positioned(
              top: 56,
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
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final plot in c.plots) ...[
                          CloudPillButton(
                            text: '${plot.name} · ${plot.area.toStringAsFixed(1)}亩',
                            active: plot.id == _selectedId,
                            onTap: () => _select(c, plot.id),
                          ),
                          const SizedBox(width: 6),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _bottomPanel(context, c, selected),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _locationStatus(CloudFarmController c) {
    final loc = c.location;
    if (loc.isSeed) {
      return c.lastLocateError != null ? '未定位 · 定位失败' : '未定位 · 示例位置';
    }
    final name = loc.name.isEmpty ? '未定位' : loc.name;
    return '$name · ${cloudAccuracyText(loc.accuracy)}';
  }

  Widget _mapButton({
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return Material(
      color: active ? const Color(0xFF2E7D32) : Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(icon, size: 17, color: Colors.white),
        ),
      ),
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

  Widget _bottomPanel(
      BuildContext context, CloudFarmController c, CloudPlot? plot) {
    if (plot == null) {
      return CloudCard(
        padding: const EdgeInsets.all(13),
        child: Row(
          children: [
            Icon(Icons.touch_app_outlined,
                size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('点击地图田块查看详情',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    '已建模 ${c.plots.length} 块 · 合计 ${c.totalArea.toStringAsFixed(1)} 亩',
                    style: TextStyle(fontSize: 10, color: cloudHint(context)),
                  ),
                ],
              ),
            ),
            CloudLinkButton(
              '新圈地',
              icon: Icons.add,
              onTap: () => context.push('/cloud-farm/create'),
            ),
          ],
        ),
      );
    }

    final growth = c.growth(plot);
    final moisture = c.moisture(plot);
    final crop = CloudSeed.cropOf(plot.cropId);
    return CloudCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PlotThumb(cropId: plot.cropId, width: 48, height: 48),
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
                                  fontSize: 13.5, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 6),
                        CloudTag(
                          growth != null ? '${growth.stage.name}期' : '待种植',
                          color: growth != null
                              ? const Color(0xFFF59100)
                              : cloudHint(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      crop != null
                          ? '${crop.name} · ${crop.variety} · ${plot.area.toStringAsFixed(1)}亩'
                          : '${plot.area.toStringAsFixed(1)}亩 · 完成圈地，待选作物',
                      style: TextStyle(fontSize: 10.5, color: cloudSubtle(context)),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 5,
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
              CloudRing(pct: growth?.pct ?? 0, size: 44, stroke: 4),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _select(c, null),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text('取消选择', style: TextStyle(fontSize: 11)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => context.push('/cloud-farm/remote/${plot.id}'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text('异地查看', style: TextStyle(fontSize: 11)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: () {
                    if (plot.cropId == null) {
                      context.push('/cloud-farm/plant',
                          extra: {'plotId': plot.id});
                    } else {
                      context.push('/cloud-farm/plot/${plot.id}');
                    }
                  },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: EdgeInsets.zero,
                    textStyle: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  child: Text(plot.cropId == null ? '开始种植' : '查看云田'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
