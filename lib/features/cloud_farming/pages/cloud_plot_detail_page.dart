import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/cloud_models.dart';
import '../services/cloud_engine.dart';
import '../services/cloud_farm_controller.dart';
import '../widgets/cloud_map.dart';
import '../widgets/cloud_widgets.dart';

class CloudPlotDetailPage extends ConsumerStatefulWidget {
  final String plotId;

  const CloudPlotDetailPage({super.key, required this.plotId});

  @override
  ConsumerState<CloudPlotDetailPage> createState() => _CloudPlotDetailPageState();
}

class _CloudPlotDetailPageState extends ConsumerState<CloudPlotDetailPage> {
  bool _photo = false;

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(cloudFarmProvider);
    final plot = c.plotById(widget.plotId);
    if (plot == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('田块详情')),
        body: const Center(child: Text('田块不存在')),
      );
    }
    final g = c.growth(plot);
    final crop = CloudSeed.cropOf(plot.cropId);
    final moisture = c.moisture(plot);
    final advice = c.waterAdvice(plot);
    final alerts = c.alertsFor(plot.id);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(plot.name),
            const SizedBox(height: 2),
            Text(
              crop != null
                  ? '${crop.name} · ${g?.stage.name ?? ''}期 · ${plot.area.toStringAsFixed(1)}亩'
                  : '${plot.area.toStringAsFixed(1)}亩 · 待种植',
              style: const TextStyle(fontSize: 10, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '异地查看',
            onPressed: () => context.push('/cloud-farm/remote/${plot.id}'),
            icon: const Icon(Icons.videocam_outlined),
          ),
          IconButton(
            tooltip: '边界地图',
            onPressed: () => _showMapSheet(plot),
            icon: const Icon(Icons.map_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 26),
        children: [
          _scene(plot, g, crop),
          const SizedBox(height: 12),
          if (g == null)
            _emptyPlanting(context, plot)
          else ...[
            _summaryCard(plot, g),
            const SizedBox(height: 12),
            _metricsGrid(plot, g),
            const SizedBox(height: 12),
            _moistureCard(c, plot, moisture, advice),
            const SizedBox(height: 12),
            _modelCard(plot),
            const SizedBox(height: 14),
            _actions(c, plot),
            if (alerts.isNotEmpty) ...[
              const CloudSectionHead(title: '田块提醒', sub: '按优先级排序'),
              for (final alert in alerts)
                CloudAlertCard(
                  alert: alert,
                  plotName: plot.name,
                  onDone: () {
                    if (alert.type == 'calibrate') {
                      _openCalibrate(c, plot);
                    } else {
                      c.handleAlert(alert);
                      _toast('${alert.actionText}已记录');
                    }
                  },
                  onSnooze: () {
                    c.snooze(alert.id);
                    _toast('已稍后提醒');
                  },
                ),
            ],
            CloudSectionHead(title: '农事记录', sub: '${plot.logs.length} 条'),
            _logs(plot),
          ],
        ],
      ),
    );
  }

  Widget _scene(CloudPlot plot, GrowthInfo? g, CropInfo? crop) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 188,
        child: Stack(
          children: [
            Positioned.fill(
              child: _photo
                  ? MiniPlotMap(polygon: plot.polygon, zoom: 17)
                  : CropScene(stageIdx: g?.idx ?? 0, height: 188),
            ),
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_photo ? Icons.photo_camera_outlined : Icons.animation,
                        size: 12, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      _photo
                          ? '实景卫星影像'
                          : '动态模拟 · 第 ${g?.day ?? 0} 天',
                      style: const TextStyle(fontSize: 10, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    _modeBtn('动态', !_photo, () => setState(() => _photo = false)),
                    _modeBtn('实景', _photo, () => setState(() => _photo = true)),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Row(
                children: [
                  CloudTag(
                    crop != null ? '${crop.name} ${crop.variety}' : '待种植',
                    color: Colors.white,
                  ),
                  const SizedBox(width: 6),
                  if (g != null)
                    CloudTag('${g.stage.name}期 · ${g.pct.round()}%',
                        color: Colors.white),
                  const Spacer(),
                  CloudTag('${plot.area.toStringAsFixed(1)} 亩', color: Colors.white),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeBtn(String text, bool active, VoidCallback onTap) {
    return Material(
      color: active ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: active ? const Color(0xFF1B2A1E) : Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyPlanting(BuildContext context, CloudPlot plot) {
    return Column(
      children: [
        CloudCard(
          child: Column(
            children: [
              Icon(Icons.check_circle_outline,
                  size: 34, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 8),
              const Text('田块已完成 1:1 建模',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                '${plot.area.toStringAsFixed(1)} 亩 · 周长 ${CloudEngine.perimeterM(plot.polygon)}m · ${plot.buildSource}',
                style: TextStyle(fontSize: 11, color: cloudHint(context)),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => context.push('/cloud-farm/plant',
                      extra: {'plotId': plot.id}),
                  child: const Text('选择作物，开始云种植'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _modelCard(plot),
        const SizedBox(height: 12),
        _logs(plot),
      ],
    );
  }

  Widget _summaryCard(CloudPlot plot, GrowthInfo g) {
    final stage = g.stage;
    return CloudCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CloudRing(pct: g.pct, size: 60, stroke: 5.5),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${g.crop.name} · ${g.crop.variety}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 6),
                        CloudTag(g.stage.name, color: const Color(0xFFF59100)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '播种 ${CloudEngine.fmtDate(plot.plantedAt ?? DateTime.now())} · 第 ${g.day} 天 / 共 ${g.cycle} 天',
                      style: TextStyle(fontSize: 10.5, color: cloudSubtle(context)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      stage.tip,
                      style: TextStyle(
                          fontSize: 10.5, height: 1.45, color: cloudHint(context)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _stageTrack(g),
          const SizedBox(height: 7),
          Row(
            children: [
              Text(g.stage.name,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary)),
              const Spacer(),
              Text('${g.stagePct}% / 本阶段',
                  style: TextStyle(fontSize: 9.5, color: cloudHint(context))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stageTrack(GrowthInfo g) {
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        for (var i = 0; i < g.stages.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == g.stages.length - 1 ? 0 : 2),
              child: Column(
                children: [
                  Container(
                    height: 5,
                    decoration: BoxDecoration(
                      color: i <= g.idx
                          ? primary
                          : Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    g.stages[i].name,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                      fontSize: 8,
                      color: i == g.idx ? primary : cloudHint(context),
                      fontWeight: i == g.idx ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _metricsGrid(CloudPlot plot, GrowthInfo g) {
    final harvestDate = (plot.plantedAt ?? DateTime.now()).add(Duration(days: g.cycle));
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.35,
      children: [
        CloudMetricItem(
          icon: Icons.timelapse,
          label: '播种天数',
          value: '${g.day}',
          unit: '天',
          sub: '全周期 ${g.cycle} 天',
        ),
        CloudMetricItem(
          icon: Icons.flag_outlined,
          label: '距下一阶段',
          value: '${g.daysToNext}',
          unit: '天',
          sub: g.next?.name ?? '已到成熟期',
        ),
        CloudMetricItem(
          icon: Icons.event_outlined,
          label: '预计采收',
          value: CloudEngine.fmtDate(harvestDate),
          sub: '${g.daysLeft} 天后',
        ),
        CloudMetricItem(
          icon: Icons.scale_outlined,
          label: '亩产预估',
          value: '${g.crop.yield}',
          unit: 'kg',
          sub: '按本地均值',
        ),
      ],
    );
  }

  Widget _moistureCard(
    CloudFarmController c,
    CloudPlot plot,
    MoistureInfo m,
    WaterAdvice advice,
  ) {
    final tone = CloudEngine.toneColor(advice.tone);
    return CloudCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.water_drop_outlined,
                  size: 16, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 5),
              const Text('墒情推断',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              const Spacer(),
              CloudTag('AI 模型', color: Theme.of(context).colorScheme.primary),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${m.value}',
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
              const Padding(
                padding: EdgeInsets.only(bottom: 5, left: 2),
                child: Text('%', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '阈值 ${c.state.settings.moistureThreshold}% · ${m.daysSince.floor()} 天未浇水',
                  style: TextStyle(fontSize: 10, color: cloudHint(context)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: cloudSoft(tone, context, light: 0.10, dark: 0.20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome, size: 13, color: tone),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(advice.text,
                      style: TextStyle(
                          fontSize: 10.5, height: 1.5, color: cloudSubtle(context))),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          for (final f in m.factors)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(f.label,
                        style:
                            TextStyle(fontSize: 10.5, color: cloudSubtle(context))),
                  ),
                  Expanded(
                    child: Text(f.note,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: cloudHint(context))),
                  ),
                  Text(
                    '${f.value >= 0 ? '+' : ''}${f.value.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: f.value >= 0
                          ? Theme.of(context).colorScheme.primary
                          : const Color(0xFFD84343),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _openWater(c, plot),
              icon: const Icon(Icons.water_drop_outlined, size: 15),
              label: const Text('记录灌溉', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 36),
                foregroundColor: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modelCard(CloudPlot plot) {
    final size = CloudEngine.sizeM(plot.polygon);
    return CloudCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.view_in_ar_outlined,
                  size: 15, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 5),
              const Text('1:1 云田建模',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              const Spacer(),
              CloudLinkButton(
                '地图',
                icon: Icons.map_outlined,
                onTap: () => _showMapSheet(plot),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _modelItem('${plot.area.toStringAsFixed(1)} 亩', '面积'),
              _modelItem('${CloudEngine.perimeterM(plot.polygon)} m', '周长'),
              _modelItem(
                  '${size.width.round()}×${size.height.round()} m', '外接尺寸'),
              _modelItem('${plot.polygon.length} 点', '边界'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${plot.buildSource} · 土壤 ${CloudSeed.soilOf(plot.soil).name} · ${CloudSeed.irrigationOf(plot.irrigation).name}',
            style: TextStyle(fontSize: 10, color: cloudHint(context)),
          ),
        ],
      ),
    );
  }

  Widget _modelItem(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 1),
          Text(label, style: const TextStyle(fontSize: 9.5, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _actions(CloudFarmController c, CloudPlot plot) {
    final actions = [
      (Icons.water_drop_outlined, '浇水', () => _openWater(c, plot)),
      (Icons.science_outlined, '施肥', () => _openFert(c, plot)),
      (Icons.edit_note, '记录', () => _openNote(c, plot)),
      (Icons.tune, '校准', () => _openCalibrate(c, plot)),
    ];
    return Row(
      children: [
        for (final a in actions)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: InkWell(
                onTap: a.$3,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: cloudCardColor(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Theme.of(context)
                            .dividerColor
                            .withValues(alpha: 0.45)),
                  ),
                  child: Column(
                    children: [
                      Icon(a.$1,
                          size: 20, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 4),
                      Text(a.$2,
                          style: const TextStyle(
                              fontSize: 10.5, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _logs(CloudPlot plot) {
    if (plot.logs.isEmpty) {
      return CloudCard(
        child: Text('暂无农事记录',
            style: TextStyle(fontSize: 11, color: cloudHint(context))),
      );
    }
    return CloudCard(
      child: Column(
        children: [
          for (var i = 0; i < plot.logs.length; i++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          color: i == 0
                              ? Theme.of(context).colorScheme.primary
                              : cloudHint(context).withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                      ),
                      if (i != plot.logs.length - 1)
                        Expanded(
                          child: Container(
                            width: 1,
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            color: Theme.of(context)
                                .dividerColor
                                .withValues(alpha: 0.6),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(plot.logs[i].title,
                                    style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600)),
                              ),
                              Text(
                                '${CloudEngine.fmtMd(plot.logs[i].t)} ${plot.logs[i].t.hour.toString().padLeft(2, '0')}:${plot.logs[i].t.minute.toString().padLeft(2, '0')}',
                                style: TextStyle(
                                    fontSize: 9, color: cloudHint(context)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(plot.logs[i].desc,
                              style: TextStyle(
                                  fontSize: 10,
                                  height: 1.45,
                                  color: cloudSubtle(context))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ---------- 弹层 ----------
  void _showMapSheet(CloudPlot plot) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.62,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                children: [
                  Text(plot.name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  CloudTag('${plot.area.toStringAsFixed(1)} 亩',
                      color: Theme.of(ctx).colorScheme.primary),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
                child: CloudFarmMap(
                  plots: [plot],
                  selectedId: plot.id,
                  zoom: 17,
                  center: centroidOf(plot.polygon),
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  '边界 ${plot.polygon.length} 点 · 周长 ${CloudEngine.perimeterM(plot.polygon)}m · ${plot.buildSource}',
                  style: TextStyle(fontSize: 10, color: cloudHint(ctx)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openWater(CloudFarmController c, CloudPlot plot) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => _Sheet(
        title: '记录灌溉',
        subtitle:
            '${CloudSeed.irrigationOf(plot.irrigation).name} · 建议 15—18m³/亩',
        children: [
          Text(
            c.waterAdvice(plot).text,
            style: TextStyle(fontSize: 11.5, height: 1.55, color: cloudSubtle(ctx)),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                c.waterPlot(plot);
                Navigator.pop(ctx);
                _toast('灌溉已记录，墒情将同步更新');
              },
              icon: const Icon(Icons.check, size: 17),
              label: const Text('确认已灌溉'),
            ),
          ),
        ],
      ),
    );
  }

  void _openFert(CloudFarmController c, CloudPlot plot) {
    final controller = TextEditingController(text: plot.fertilizer);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _Sheet(
          title: '记录施肥',
          subtitle: '填写肥料与用量，写入农事记录',
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(hintText: '如：复合肥 15kg/亩'),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  c.fertilizerPlot(plot, desc: controller.text);
                  Navigator.pop(ctx);
                  _toast('施肥已记录');
                },
                icon: const Icon(Icons.check, size: 17),
                label: const Text('确认已施肥'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openNote(CloudFarmController c, CloudPlot plot) {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _Sheet(
          title: '现场记录',
          subtitle: '记录长势、病虫害或农事操作',
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 3,
              maxLines: 5,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(hintText: '如：叶片浓绿，密度均匀…'),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  c.addNote(plot, controller.text);
                  Navigator.pop(ctx);
                  _toast('记录已保存');
                },
                icon: const Icon(Icons.check, size: 17),
                label: const Text('保存记录'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openCalibrate(CloudFarmController c, CloudPlot plot) {
    var value = 0;
    final g = c.growth(plot);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => _Sheet(
          title: '校准云田长势',
          subtitle: '拍照或巡田后，修正云田与实体的进度偏差',
          children: [
            Row(
              children: [
                Text('当前 ${g?.pct.round() ?? 0}%',
                    style: const TextStyle(fontSize: 12)),
                const Spacer(),
                Text(
                  '修正后 ${((g?.pct ?? 0) + value).clamp(0, 100).round()}%',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(ctx).colorScheme.primary),
                ),
              ],
            ),
            Slider(
              value: value.toDouble(),
              min: -10,
              max: 10,
              divisions: 10,
              label: '${value >= 0 ? '+' : ''}$value%',
              onChanged: (v) => setSheet(() => value = v.round()),
            ),
            Text(
              '拍照比对可自动识别株高、叶色与密度；当前演示使用手动修正值。',
              style: TextStyle(fontSize: 10.5, height: 1.5, color: cloudHint(ctx)),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  c.calibrate(plot, value);
                  Navigator.pop(ctx);
                  _toast('长势已校准');
                },
                icon: const Icon(Icons.sync, size: 17),
                label: const Text('确认校准'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }
}

class _Sheet extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;

  const _Sheet({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
            Text(subtitle,
                style: TextStyle(fontSize: 11, color: cloudHint(context))),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}
