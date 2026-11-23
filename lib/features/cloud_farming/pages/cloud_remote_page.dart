import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/tablet_layout.dart';
import '../models/cloud_models.dart';
import '../services/cloud_engine.dart';
import '../services/cloud_farm_controller.dart';
import '../widgets/cloud_map.dart';
import '../widgets/cloud_widgets.dart';

class CloudRemotePage extends ConsumerStatefulWidget {
  final String plotId;

  const CloudRemotePage({super.key, required this.plotId});

  @override
  ConsumerState<CloudRemotePage> createState() => _CloudRemotePageState();
}

class _CloudRemotePageState extends ConsumerState<CloudRemotePage>
    with SingleTickerProviderStateMixin {
  int _filter = 0;
  bool _busy = false;
  bool _autoSync = true;
  late final AnimationController _scan;

  static const _filters = ['可见光', '多光谱', '热成像'];

  @override
  void initState() {
    super.initState();
    _scan = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(cloudFarmProvider);
    final plot = c.plotById(widget.plotId);
    if (plot == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('异地查看')),
        body: const Center(child: Text('田块不存在')),
      );
    }
    final g = c.growth(plot);
    final moisture = c.moisture(plot);
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(plot.name),
            const SizedBox(height: 2),
            const Text('异地查看 · 实时画面',
                style: TextStyle(fontSize: 10, color: Colors.white70)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: CloudTag(
                _autoSync ? '已同步' : '手动',
                color: _autoSync ? const Color(0xFF2E7D32) : Colors.grey,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 26),
        children: [
          _liveView(c, plot, g, timeStr, moisture),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () {
                          c.recordRemoteShot(plot);
                          _toast('已保存异地拍照记录');
                        },
                  icon: const Icon(Icons.camera_alt_outlined, size: 16),
                  label: const Text('拍照', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          await Future.delayed(const Duration(milliseconds: 1800));
                          if (!mounted) return;
                          c.completePatrol(plot);
                          setState(() => _busy = false);
                          _toast('无人机巡田完成，长势已同步');
                        },
                  icon: _busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.flight_takeoff, size: 16),
                  label: Text(_busy ? '巡田执行中…' : '无人机巡田',
                      style: const TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40)),
                ),
              ),
            ],
          ),
          const CloudSectionHead(title: '田块传感器', sub: '最近同步 2 分钟内'),
          GridView(
            gridDelegate: adaptiveGridDelegate(
              context,
              childAspectRatio: 2.5,
              maxCrossAxisExtent: 420,
              spacing: 8,
            ),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              CloudMetricItem(
                icon: Icons.water_drop_outlined,
                label: '土壤墒情',
                value: '${moisture.value}',
                unit: '%',
                sub: '阈值 ${c.state.settings.moistureThreshold}%',
              ),
              CloudMetricItem(
                icon: Icons.thermostat,
                label: '土壤温度',
                value: '${CloudSeed.weather.soilTemp}',
                unit: '℃',
                sub: '10cm 深度',
              ),
              CloudMetricItem(
                icon: Icons.water_outlined,
                label: '空气湿度',
                value: '${CloudSeed.weather.humidity}',
                unit: '%',
                sub: CloudSeed.weather.desc,
              ),
              CloudMetricItem(
                icon: Icons.wb_sunny_outlined,
                label: '光照强度',
                value: '38',
                unit: 'klx',
                sub: '当前瞬时值',
              ),
            ],
          ),
          const CloudSectionHead(title: '同步状态'),
          CloudCard(
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.sync,
                        size: 15,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '云田与实体偏差 ${(plot.pctOffset).round()}% · ${g?.stage.name ?? '待种植'}期',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ),
                    Switch(
                      value: _autoSync,
                      onChanged: (v) => setState(() => _autoSync = v),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text('最近采集 ${CloudEngine.fmtAgo(plot.lastSensedAt)}',
                        style:
                            TextStyle(fontSize: 10, color: cloudHint(context))),
                    const Spacer(),
                    CloudTag('偏移 ${CloudSeed.region.accuracy}m',
                        color: cloudHint(context)),
                  ],
                ),
              ],
            ),
          ),
          const CloudSectionHead(title: '历史巡检', sub: '最近 3 次'),
          for (final item in _history(plot))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: CloudCard(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    PlotThumb(cropId: plot.cropId, width: 42, height: 42),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.$1,
                              style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(item.$2,
                              style: TextStyle(
                                  fontSize: 10, color: cloudHint(context))),
                        ],
                      ),
                    ),
                    CloudTag(item.$3,
                        color: Theme.of(context).colorScheme.primary),
                  ],
                ),
              ),
            ),
          const CloudSectionHead(title: '田块位置', sub: 'GPS 边界 1:1'),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 140,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: MiniPlotMap(polygon: plot.polygon, zoom: 17),
                  ),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${plot.area.toStringAsFixed(1)} 亩 · 周长 ${CloudEngine.perimeterM(plot.polygon)}m',
                        style:
                            const TextStyle(fontSize: 9.5, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '异地查看支持可见光、多光谱与热成像画面\n投资者/农户可远程确认长势，所有抓拍自动写入农事记录',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, height: 1.6, color: cloudHint(context)),
          ),
        ],
      ),
    );
  }

  Widget _liveView(
    CloudFarmController c,
    CloudPlot plot,
    GrowthInfo? g,
    String timeStr,
    MoistureInfo moisture,
  ) {
    Color? blend;
    if (_filter == 1) blend = const Color(0xFF6AB04C);
    if (_filter == 2) blend = const Color(0xFFD84343);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 212,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColorFiltered(
                colorFilter: ColorFilter.mode(
                  blend ?? Colors.transparent,
                  _filter == 0 ? BlendMode.dst : BlendMode.color,
                ),
                child: MiniPlotMap(polygon: plot.polygon, zoom: 17),
              ),
            ),
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _scan,
                builder: (context, _) => CustomPaint(
                  painter: _ScanPainter(progress: _scan.value),
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF6EE7A0),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text('LIVE · 摄像头 01 · $timeStr',
                        style:
                            const TextStyle(fontSize: 9.5, color: Colors.white)),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_filters[_filter],
                    style: const TextStyle(fontSize: 9.5, color: Colors.white)),
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 42,
              child: Center(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < _filters.length; i++) ...[
                        _filterBtn(i),
                        if (i < _filters.length - 1) const SizedBox(width: 5),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome,
                        size: 11, color: Color(0xFF9BE7A4)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'AI 识别：${g == null ? '待种植' : '长势均匀 · ${g.stage.name}期 · 墒情 ${moisture.value}%'}',
                        style:
                            const TextStyle(fontSize: 9.5, color: Colors.white),
                      ),
                    ),
                    const Icon(Icons.hd_outlined,
                        size: 11, color: Colors.white70),
                    const SizedBox(width: 3),
                    const Text('HD',
                        style:
                            TextStyle(fontSize: 9, color: Colors.white70)),
                  ],
                ),
              ),
            ),
            if (_busy)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.30),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 8),
                        Text('无人机巡田中…',
                            style:
                                TextStyle(fontSize: 11, color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _filterBtn(int index) {
    final active = _filter == index;
    return Material(
      color: active
          ? Colors.white
          : Colors.black.withValues(alpha: 0.50),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _filter = index),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(
            _filters[index],
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: active ? const Color(0xFF1B2A1E) : Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  List<(String, String, String)> _history(CloudPlot plot) {
    final now = DateTime.now();
    return [
      (
        '无人机巡田 · 5 点采样',
        '${CloudEngine.fmtDate(now.subtract(const Duration(days: 1)))} 09:20 · 已同步',
        '多光谱'
      ),
      (
        '农户远程拍照',
        '${CloudEngine.fmtDate(now.subtract(const Duration(days: 3)))} 16:05 · 已同步',
        '可见光'
      ),
      (
        '生长模型校准',
        '${CloudEngine.fmtDate(now.subtract(const Duration(days: 6)))} 08:40',
        '模型'
      ),
    ];
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }
}

class _ScanPainter extends CustomPainter {
  final double progress;

  _ScanPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * progress;
    final rect = Rect.fromLTWH(0, y - 18, size.width, 36);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.transparent,
            const Color(0xFF6EE7A0).withValues(alpha: 0.18),
            Colors.transparent,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(rect),
    );
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = const Color(0xFF9BE7A4).withValues(alpha: 0.55)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _ScanPainter old) => old.progress != progress;
}
