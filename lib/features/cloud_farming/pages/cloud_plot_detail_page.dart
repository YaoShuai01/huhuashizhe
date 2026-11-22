import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

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
  /// 模拟植株叠加比例：0 = 纯照片，100 = 完整模拟层（默认 42%，打开即可见生长层）
  int _simMix = 42;
  int? _simDay;
  bool _playing = false;
  Timer? _playTimer;

  @override
  void dispose() {
    _playTimer?.cancel();
    super.dispose();
  }

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
    final baseGrowth = c.growth(plot);
    final crop = CloudSeed.cropOf(plot.cropId);
    final simDay = _simDay;
    final g = (baseGrowth != null && crop != null && simDay != null)
        ? _growthAt(plot, crop, simDay)
        : baseGrowth;
    final preview =
        simDay != null && baseGrowth != null && simDay.round() != baseGrowth.day;
    final moisture = (g != null && preview)
        ? CloudEngine.moistureFor(
            soilKey: plot.soil,
            irrigationKey: plot.irrigation,
            lastWaterAt: plot.lastWaterAt,
            stageIdx: g.idx,
          )
        : c.moisture(plot);
    final advice = preview
        ? CloudEngine.waterAdvice(moisture, c.state.settings.moistureThreshold)
        : c.waterAdvice(plot);
    final alerts = c.alertsFor(plot.id);
    final hasPhoto = _hasPhoto(plot);

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
            tooltip: '返回 App 首页',
            onPressed: () => context.go('/home'),
            icon: const Icon(Icons.home_outlined),
          ),
          IconButton(
            tooltip: '拍照',
            onPressed: () => _pickPhoto(plot.id, ImageSource.camera),
            icon: const Icon(Icons.photo_camera_outlined),
          ),
          IconButton(
            tooltip: '地图',
            onPressed: () => context.go('/cloud-farm'),
            icon: const Icon(Icons.map_outlined),
          ),
          IconButton(
            tooltip: '删除田块',
            onPressed: () => _confirmDelete(plot),
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 26),
        children: [
          _scene(plot, g, crop, preview, hasPhoto),
          if (_photo) _photoToolbar(plot, hasPhoto),
          if (_photo && g != null) _simMixRow(),
          if (g != null) ...[
            const SizedBox(height: 10),
            _timelineCard(plot, g),
          ],
          const SizedBox(height: 12),
          if (g == null)
            _emptyPlanting(context, plot, c.location)
          else ...[
            _summaryCard(plot, g, preview),
            const SizedBox(height: 12),
            _metricsGrid(plot, g),
            const SizedBox(height: 12),
            _moistureCard(c, plot, moisture, advice, g, preview),
            const SizedBox(height: 12),
            _modelCard(plot, c.location),
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

  Widget _scene(
    CloudPlot plot,
    GrowthInfo? g,
    CropInfo? crop,
    bool preview,
    bool hasPhoto,
  ) {
    final stageIdx = g?.idx ?? 0;
    // 当前阶段对应的植株形态 + 阶段内进度（让叠层随日期逐日生长）
    final form = g == null ? 0 : _growthForm(g.stage.name);
    final inner = ((g?.stagePct ?? 0) / 100).clamp(0.0, 1.0);
    final photoPath = plot.photoPath;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 188,
        child: Stack(
          children: [
            Positioned.fill(
              child: !_photo
                  ? CropScene(stageIdx: stageIdx, height: 188)
                  : hasPhoto
                      ? Image.file(
                          File(photoPath!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => MiniPlotMap(
                            polygon: plot.polygon,
                            zoom: 18,
                          ),
                        )
                      : MiniPlotMap(polygon: plot.polygon, zoom: 18),
            ),
            if (_photo && g != null && _simMix > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: (_simMix / 100).clamp(0.0, 1.0),
                    child: CustomPaint(
                      painter: _SceneOverlayPainter(
                        stageIdx: form,
                        inner: inner,
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 10,
              left: 10,
              right: 118,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_photo ? Icons.layers_outlined : Icons.eco,
                          size: 12, color: Colors.white),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          g == null
                              ? '尚未选择作物'
                              : _photo
                                  ? '实景叠加 · 模拟${g.stage.name}期 · 第 ${g.day} 天'
                                  : '${g.stage.name}期 · 第 ${g.day} 天',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              const TextStyle(fontSize: 10, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_photo)
              Positioned(
                left: 10,
                bottom: 38,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.42),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    !hasPhoto
                        ? (_simMix > 0
                            ? '卫星底图 · 已叠加生长模拟，拍实景更直观'
                            : '卫星底图 · 拍照后在实景上叠加模拟')
                        : _simMix > 0
                            ? '我的实景照片 · 生长模拟已叠加'
                            : '我的实景照片 · 拖动滑杆叠加模拟',
                    style: const TextStyle(fontSize: 9, color: Colors.white),
                  ),
                ),
              ),
            if (preview || (_photo && g != null))
              Positioned(
                right: 10,
                bottom: 38,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    preview
                        ? '预览 · 第 ${g?.day ?? 0} 天'
                        : '生长 ${g?.pct.round() ?? 0}%',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
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

  /// 按指定天数推算阶段 / 进度 / 剩余天数（仅本页预览用）
  GrowthInfo _growthAt(CloudPlot plot, CropInfo crop, int day) {
    final d = day.clamp(0, crop.cycle).toInt();
    var idx = 0;
    for (var i = 0; i < crop.stages.length; i++) {
      if (d >= crop.stages[i].s) idx = i;
    }
    final stage = crop.stages[idx];
    final span = math.max(1, stage.e - stage.s);
    final inner = ((d - stage.s) / span).clamp(0.0, 1.0);
    final pct = plot.harvested
        ? 100.0
        : (stage.sp + (stage.ep - stage.sp) * inner + plot.pctOffset)
            .clamp(0.0, 100.0);
    final next = idx + 1 < crop.stages.length ? crop.stages[idx + 1] : null;
    return GrowthInfo(
      rawDay: d,
      day: d,
      cycle: crop.cycle,
      idx: idx,
      stage: stage,
      stages: crop.stages,
      crop: crop,
      pct: pct,
      next: next,
      daysLeft: math.max(0, crop.cycle - d),
      daysToNext: next == null ? 0 : math.max(0, next.s - d),
      stagePct: (inner * 100).round(),
    );
  }

  void _togglePlay(GrowthInfo g) {
    if (_playing) {
      _stopPlay();
      return;
    }
    var start = _simDay ?? g.day;
    if (start >= g.cycle) start = 0;
    setState(() {
      _simDay = start;
      _playing = true;
    });
    _playTimer = Timer.periodic(const Duration(milliseconds: 130), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final current = _simDay ?? 0;
      if (current >= g.cycle) {
        _stopPlay();
        return;
      }
      final next = current + 1;
      setState(() => _simDay = next);
      if (next >= g.cycle) _stopPlay();
    });
  }

  void _stopPlay() {
    _playTimer?.cancel();
    _playTimer = null;
    if (_playing) setState(() => _playing = false);
  }

  void _resetDay() {
    _stopPlay();
    setState(() => _simDay = null);
    _toast('已回到今天');
  }

  bool _hasPhoto(CloudPlot plot) {
    final path = plot.photoPath;
    if (path == null || path.isEmpty) return false;
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// 实景模式下的照片入口：无照片时拍照 / 相册，有照片时更换 / 移除
  Widget _photoToolbar(CloudPlot plot, bool hasPhoto) {
    final primary = Theme.of(context).colorScheme.primary;
    final style = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 34),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      foregroundColor: primary,
    );
    final buttons = hasPhoto
        ? [
            OutlinedButton.icon(
              onPressed: () => _openShot(plot),
              icon: const Icon(Icons.swap_horiz, size: 15),
              label: const Text('更换照片', style: TextStyle(fontSize: 11.5)),
              style: style,
            ),
            OutlinedButton.icon(
              onPressed: () => _removePhoto(plot),
              icon: const Icon(Icons.delete_outline, size: 15),
              label: const Text('移除照片', style: TextStyle(fontSize: 11.5)),
              style: style,
            ),
          ]
        : [
            OutlinedButton.icon(
              onPressed: () => _pickPhoto(plot.id, ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined, size: 15),
              label: const Text('拍照', style: TextStyle(fontSize: 11.5)),
              style: style,
            ),
            OutlinedButton.icon(
              onPressed: () => _pickPhoto(plot.id, ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined, size: 15),
              label: const Text('从相册选择', style: TextStyle(fontSize: 11.5)),
              style: style,
            ),
          ];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: buttons[i]),
          ],
        ],
      ),
    );
  }

  Future<void> _pickPhoto(String plotId, ImageSource source) async {
    final fromCamera = source == ImageSource.camera;
    final controller = ref.read(cloudFarmProvider);
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (file == null) return; // 用户取消
      controller.setPlotPhoto(plotId, file.path);
      if (!mounted) return;
      setState(() {
        _photo = true;
        if (_simMix == 0) _simMix = 42; // 拍完即可见模拟叠加
      });
      _toast('实景照片已保存，已叠加生长模拟，可拖动滑杆调节');
    } on PlatformException {
      _toast(fromCamera ? '未获得相机权限，可改用相册' : '相册暂不可用，请稍后重试');
    } catch (_) {
      _toast(fromCamera ? '未获得相机权限，可改用相册' : '照片读取失败，请重试');
    }
  }

  void _removePhoto(CloudPlot plot) {
    ref.read(cloudFarmProvider).setPlotPhoto(plot.id, null);
    _toast('已移除实景照片');
  }

  /// 删除田块（文案对齐网页版删除弹层）
  Future<void> _confirmDelete(CloudPlot plot) async {
    final crop = CloudSeed.cropOf(plot.cropId);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除田块'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${plot.name} · ${plot.area.toStringAsFixed(1)} 亩',
                style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline,
                    size: 15, color: Theme.of(ctx).colorScheme.error),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    '删除后 GPS 边界、作物档案与生长记录都会移除，且无法恢复。',
                    style: TextStyle(fontSize: 12, height: 1.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.eco_outlined,
                    size: 14, color: Theme.of(ctx).colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  crop != null ? '${crop.name} · ${crop.variety}' : '当前为空闲田块',
                  style: const TextStyle(fontSize: 11.5),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    ref.read(cloudFarmProvider).deletePlot(plot.id);
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/cloud-farm');
    }
  }

  Widget _simMixRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.layers_outlined,
                  size: 13, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 4),
              const Text('照片 ←→ 模拟',
                  style:
                      TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('叠加 $_simMix%',
                  style: TextStyle(fontSize: 10, color: cloudHint(context))),
            ],
          ),
          SizedBox(
            height: 26,
            child: Row(
              children: [
                Text('照片',
                    style: TextStyle(fontSize: 10, color: cloudHint(context))),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 7),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12),
                    ),
                    child: Slider(
                      value: _simMix.toDouble(),
                      min: 0,
                      max: 100,
                      onChanged: (v) => setState(() => _simMix = v.round()),
                    ),
                  ),
                ),
                Text('模拟',
                    style: TextStyle(fontSize: 10, color: cloudHint(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _timelineCard(CloudPlot plot, GrowthInfo g) {
    final day = g.day;
    final cycle = g.cycle;
    return CloudCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CloudPillButton(
                text: _playing ? '暂停' : '播放',
                active: _playing,
                icon: _playing ? Icons.pause : Icons.play_arrow,
                onTap: () => _togglePlay(g),
              ),
              const SizedBox(width: 10),
              Text('第 $day 天',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              Text(' / 共 $cycle 天',
                  style: TextStyle(fontSize: 10, color: cloudHint(context))),
              const Spacer(),
              CloudPillButton(
                text: '今天',
                active: _simDay == null,
                icon: Icons.today_outlined,
                onTap: _resetDay,
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: day.toDouble().clamp(0, cycle.toDouble()).toDouble(),
              min: 0,
              max: cycle.toDouble(),
              label: '第 $day 天',
              onChanged: (v) {
                _stopPlay();
                setState(() => _simDay = v.round());
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              children: [
                Text('播种 0 天',
                    style: TextStyle(fontSize: 9.5, color: cloudHint(context))),
                const Spacer(),
                Text('成熟 $cycle 天',
                    style: TextStyle(fontSize: 9.5, color: cloudHint(context))),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openCloseup(plot, g),
                  icon: const Icon(Icons.eco_outlined, size: 15),
                  label: const Text('幼苗特写', style: TextStyle(fontSize: 11.5)),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    foregroundColor: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openShot(plot),
                  icon: const Icon(Icons.photo_camera_outlined, size: 15),
                  label: const Text('拍实景', style: TextStyle(fontSize: 11.5)),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    foregroundColor: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 12, color: cloudHint(context)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '拖动时间轴可查看任意一天，场景、阶段、进度与墒情按该天重算',
                  style: TextStyle(
                      fontSize: 9.5, height: 1.45, color: cloudHint(context)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openShot(CloudPlot plot) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _Sheet(
        title: '拍一张田地实景',
        subtitle: '云田会把发芽、长叶、开花的过程直接叠加到你的照片上',
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cloudSoft(
                  Theme.of(ctx).colorScheme.primary, ctx,
                  light: 0.06, dark: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.photo_camera_outlined,
                    size: 20, color: Theme.of(ctx).colorScheme.primary),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('建议站在田边、顺垄拍摄',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700)),
                      SizedBox(height: 3),
                      Text(
                        '保持地平线在画面下三分之一，包含天空与土壤，叠加效果更自然。',
                        style: TextStyle(fontSize: 10.5, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 13, color: cloudHint(ctx)),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  '照片仅保存在本机，不会上传服务器，可随时更换或移除。',
                  style: TextStyle(
                      fontSize: 10.5, height: 1.5, color: cloudHint(ctx)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _pickPhoto(plot.id, ImageSource.camera);
                  },
                  icon: const Icon(Icons.photo_camera_outlined, size: 16),
                  label: const Text('拍照', style: TextStyle(fontSize: 12.5)),
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _pickPhoto(plot.id, ImageSource.gallery);
                  },
                  icon: const Icon(Icons.photo_library_outlined, size: 16),
                  label:
                      const Text('从相册选择', style: TextStyle(fontSize: 12.5)),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openCloseup(CloudPlot plot, GrowthInfo g) {
    final early = g.idx <= 2;
    final crop = g.crop;
    final labels = early
        ? const [
            ('子叶', '供幼苗初期光合，遇光后展开'),
            ('真叶', '带叶脉，决定后续长势'),
            ('根', '向下扎根吸收水分'),
            ('茎', '连接根与叶，逐日增高'),
          ]
        : [
            ('茎', '随生长加粗、拔高'),
            ('叶片', '叶脉清晰，叶色反映氮素'),
            (g.idx >= 5 ? '花果' : '新叶', g.idx >= 5 ? '进入生殖生长' : '持续分化'),
            ('根际', '土壤湿度影响吸收'),
          ];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _Sheet(
        title: '幼苗特写',
        subtitle: '${plot.name} · ${crop.name} · ${g.stage.name}期 · 第 ${g.day} 天',
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: LayoutBuilder(
                builder: (ctx, box) => Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _CloseupPainter(stageIdx: g.idx),
                      ),
                    ),
                    _closeupLabel(
                        ctx,
                        box,
                        early ? '子叶' : '叶片',
                        early ? 0.12 : 0.10,
                        early ? 0.52 : 0.30),
                    _closeupLabel(
                        ctx,
                        box,
                        early ? '真叶' : (g.idx >= 5 ? '花果' : '新叶'),
                        early ? 0.62 : 0.64,
                        early ? 0.44 : 0.18),
                    _closeupLabel(
                        ctx, box, '茎', 0.46, early ? 0.68 : 0.52),
                    _closeupLabel(
                        ctx, box, early ? '根' : '根际', 0.54, 0.86),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < labels.length; i += 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _closeupNote(ctx, labels[i])),
                  const SizedBox(width: 8),
                  Expanded(
                    child: i + 1 < labels.length
                        ? _closeupNote(ctx, labels[i + 1])
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _closeupLabel(
      BuildContext ctx, BoxConstraints box, String text, double dx, double dy) {
    return Positioned(
      left: box.maxWidth * dx,
      top: box.maxHeight * dy,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text,
            style: const TextStyle(fontSize: 9, color: Colors.white)),
      ),
    );
  }

  Widget _closeupNote(BuildContext ctx, (String, String) item) {
    final primary = Theme.of(ctx).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cloudSoft(primary, ctx, light: 0.05, dark: 0.12),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.$1,
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: primary)),
          const SizedBox(height: 2),
          Text(item.$2,
              style: TextStyle(
                  fontSize: 9.5, height: 1.45, color: cloudSubtle(ctx))),
        ],
      ),
    );
  }

  Widget _emptyPlanting(
      BuildContext context, CloudPlot plot, CloudLocation location) {
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
        _modelCard(plot, location),
        const SizedBox(height: 12),
        _logs(plot),
      ],
    );
  }

  Widget _summaryCard(CloudPlot plot, GrowthInfo g, bool preview) {
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
                      '播种 ${CloudEngine.fmtDate(plot.plantedAt ?? DateTime.now())} · 第 ${g.day} 天 / 共 ${g.cycle} 天${preview ? ' · 预览中' : ''}',
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
    GrowthInfo g,
    bool preview,
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
              if (preview) ...[
                Text('第 ${g.day} 天',
                    style:
                        TextStyle(fontSize: 10, color: cloudHint(context))),
                const SizedBox(width: 8),
              ],
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

  Widget _modelCard(CloudPlot plot, CloudLocation location) {
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
          const SizedBox(height: 7),
          Row(
            children: [
              Icon(Icons.place_outlined,
                  size: 12, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 3),
              Expanded(
                child: Text(
                  location.name.isEmpty ? '位置未设置' : location.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 10, color: cloudSubtle(context)),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                cloudAccuracyText(location.accuracy),
                style: TextStyle(fontSize: 9.5, color: cloudHint(context)),
              ),
              const SizedBox(width: 8),
              Text(
                '${CloudEngine.fmtAgo(plot.lastCalibratedAt)}校准',
                style: TextStyle(fontSize: 9.5, color: cloudHint(context)),
              ),
            ],
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

/// 把作物阶段名称映射到植株绘制形态（0 播种/发芽 … 7 成熟）
int _growthForm(String stageName) {
  if (stageName.contains('播种') || stageName.contains('发芽')) return 0;
  if (stageName.contains('出苗')) return 1;
  if (stageName.contains('幼苗')) return 2;
  if (stageName.contains('莲座') ||
      stageName.contains('分蘖') ||
      stageName.contains('分枝')) {
    return 3;
  }
  if (stageName.contains('拔节') ||
      stageName.contains('蕾薹') ||
      stageName.contains('抽雄') ||
      stageName.contains('抽穗')) {
    return 4;
  }
  if (stageName.contains('开花') || stageName.contains('吐丝')) return 5;
  if (stageName.contains('结荚') ||
      stageName.contains('灌浆') ||
      stageName.contains('鼓粒')) {
    return 6;
  }
  if (stageName.contains('成熟')) return 7;
  return 2;
}

/// 实景底图上的透明植株层（照片 ↔ 模拟混合）
class _SceneOverlayPainter extends CustomPainter {
  /// 植株形态（0 种子 … 7 成熟），由当前阶段名称映射
  final int stageIdx;
  /// 当前阶段内进度 0—1，让植株随天数逐日长高
  final double inner;

  _SceneOverlayPainter({required this.stageIdx, this.inner = 0.5});

  @override
  void paint(Canvas canvas, Size size) {
    final grow = 0.72 + 0.28 * inner.clamp(0.0, 1.0);
    // 地面一层极淡的绿色雾，照片上更容易分辨叠加上来的模拟层
    final ground =
        Rect.fromLTWH(0, size.height * 0.5, size.width, size.height * 0.5);
    canvas.drawRect(
      ground,
      Paint()
        ..shader = LinearGradient(
          colors: [
            const Color(0xFF4C9B45).withValues(alpha: 0),
            const Color(0xFF4C9B45).withValues(alpha: 0.18),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(ground),
    );
    for (var i = 0; i < 8; i++) {
      _paintPlant(
        canvas,
        Offset(size.width * (0.04 + i * 0.13), size.height * 0.86),
        size.height * (0.55 + (i % 3) * 0.025) * grow,
        stageIdx,
        (((i * 37) % 11) - 5) * 0.014,
      );
    }
    for (var i = 0; i < 6; i++) {
      _paintPlant(
        canvas,
        Offset(size.width * (0.10 + i * 0.16), size.height * 0.98),
        size.height * (0.82 + (i % 2) * 0.05) * grow,
        stageIdx,
        (((i * 53) % 11) - 5) * 0.012,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SceneOverlayPainter old) =>
      old.stageIdx != stageIdx || (old.inner - inner).abs() > 0.001;
}

/// 幼苗特写：单株放大 + 土壤剖面
class _CloseupPainter extends CustomPainter {
  final int stageIdx;

  _CloseupPainter({required this.stageIdx});

  @override
  void paint(Canvas canvas, Size size) {
    final soilTop = size.height * 0.80;
    final skyRect = Rect.fromLTWH(0, 0, size.width, soilTop);
    canvas.drawRect(
      skyRect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFEAF6EA), Color(0xFFF7FBF4)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(skyRect),
    );

    final soilRect =
        Rect.fromLTWH(0, soilTop, size.width, size.height - soilTop);
    canvas.drawRect(
      soilRect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF6B4D32), Color(0xFF4A3421)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(soilRect),
    );
    final furrow = Paint()
      ..color = const Color(0xFF3F2E1D).withValues(alpha: 0.30)
      ..strokeWidth = 1;
    for (var i = 1; i <= 2; i++) {
      final y = soilTop + soilRect.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), furrow);
    }

    final base = Offset(size.width * 0.5, soilTop + size.height * 0.04);
    final rootPaint = Paint()
      ..color = const Color(0xFF8A6A44).withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    for (final dx in [-14.0, -6.0, 6.0, 14.0]) {
      final path = Path()
        ..moveTo(base.dx, base.dy)
        ..quadraticBezierTo(
          base.dx + dx * 0.6,
          base.dy + size.height * 0.07,
          base.dx + dx,
          base.dy + size.height * 0.12,
        );
      canvas.drawPath(path, rootPaint);
    }

    _paintPlant(canvas, base, size.height * 1.10, stageIdx, 0);
  }

  @override
  bool shouldRepaint(covariant _CloseupPainter old) =>
      old.stageIdx != stageIdx;
}

void _paintPlant(
    Canvas canvas, Offset base, double unit, int stageIdx, double sway) {
  final gold = stageIdx >= 7;
  final stemColor = gold ? const Color(0xFFB3924F) : const Color(0xFF3F8F3F);
  final leafColor = gold ? const Color(0xFFC0A052) : const Color(0xFF4C9B45);
  final leafColor2 = gold ? const Color(0xFFB8974A) : const Color(0xFF5FAE52);

  canvas.save();
  canvas.translate(base.dx, base.dy);
  canvas.rotate(sway);

  if (stageIdx <= 0) {
    canvas.drawOval(
      Rect.fromCenter(
          center: const Offset(0, -1.5),
          width: unit * 0.11,
          height: unit * 0.06),
      Paint()..color = const Color(0xFF6B4D32),
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, -3)
        ..quadraticBezierTo(
            unit * 0.02, -unit * 0.10, unit * 0.10, -unit * 0.14),
      Paint()
        ..color = const Color(0xFF8BC34A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(unit * 0.11, -unit * 0.15),
          width: unit * 0.09,
          height: unit * 0.05),
      Paint()..color = const Color(0xFFA5D16A),
    );
  } else {
    final stemHeight = stageIdx == 1
        ? unit * 0.10
        : stageIdx == 2
            ? unit * 0.22
            : stageIdx == 3
                ? unit * 0.10
                : stageIdx == 4
                    ? unit * 0.52
                    : unit * 0.62;
    if (stageIdx != 3) {
      canvas.drawLine(
        Offset.zero,
        Offset(0, -stemHeight),
        Paint()
          ..color = stemColor
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round,
      );
    }
    if (stageIdx == 1 || stageIdx == 2) {
      _paintLeaf(canvas, Offset(0, -stemHeight * 0.9), -0.8, unit * 0.16,
          leafColor);
      _paintLeaf(canvas, Offset(0, -stemHeight * 0.9), 0.8, unit * 0.16,
          leafColor2);
      if (stageIdx == 2) {
        _paintLeaf(canvas, Offset(0, -stemHeight * 0.6), -0.35, unit * 0.13,
            leafColor2);
        _paintLeaf(canvas, Offset(0, -stemHeight * 0.6), 0.35, unit * 0.13,
            leafColor);
      }
    } else if (stageIdx == 3) {
      for (final a in [-1.2, -0.6, 0.0, 0.6, 1.2]) {
        _paintLeaf(
          canvas,
          const Offset(0, -2),
          a,
          unit * (a.abs() > 1 ? 0.20 : 0.25),
          a == 0 ? leafColor2 : leafColor,
        );
      }
    } else {
      _paintLeaf(canvas, Offset(0, -stemHeight * 0.25), -1.05, unit * 0.2,
          leafColor);
      _paintLeaf(canvas, Offset(0, -stemHeight * 0.5), 0.95, unit * 0.17,
          leafColor2);
      _paintLeaf(canvas, Offset(0, -stemHeight * 0.72), -0.8, unit * 0.13,
          leafColor);
      if (stageIdx == 4) {
        final budPaint = Paint()..color = const Color(0xFF8ECF72);
        canvas.drawOval(
          Rect.fromCenter(
              center: Offset(-unit * 0.03, -stemHeight - unit * 0.02),
              width: unit * 0.06,
              height: unit * 0.09),
          budPaint,
        );
        canvas.drawOval(
          Rect.fromCenter(
              center: Offset(unit * 0.02, -stemHeight - unit * 0.04),
              width: unit * 0.055,
              height: unit * 0.08),
          budPaint,
        );
      } else if (stageIdx == 5) {
        _paintFlower(canvas, Offset(-unit * 0.09, -stemHeight * 0.95),
            unit * 0.055);
        _paintFlower(canvas, Offset(unit * 0.08, -stemHeight * 1.05),
            unit * 0.05);
        _paintFlower(canvas, Offset(0, -stemHeight * 1.15), unit * 0.045);
      } else if (stageIdx >= 6) {
        final podColor =
            stageIdx >= 7 ? const Color(0xFFB3924F) : const Color(0xFF8BC34A);
        _paintPod(canvas, Offset(-unit * 0.05, -stemHeight * 0.85), -0.4,
            unit * 0.24, podColor);
        _paintPod(canvas, Offset(unit * 0.05, -stemHeight * 0.98), 0.35,
            unit * 0.26, podColor);
        _paintPod(canvas, Offset(-unit * 0.03, -stemHeight * 1.08), -0.3,
            unit * 0.23, podColor);
      }
    }
  }
  canvas.restore();
}

void _paintLeaf(
    Canvas canvas, Offset origin, double angle, double length, Color color) {
  canvas.save();
  canvas.translate(origin.dx, origin.dy);
  canvas.rotate(angle);
  final w = length * 0.46;
  final path = Path()
    ..moveTo(0, 0)
    ..cubicTo(-w, -length * 0.28, -w, -length * 0.92, 0, -length)
    ..cubicTo(w, -length * 0.92, w, -length * 0.28, 0, 0)
    ..close();
  canvas.drawPath(path, Paint()..color = color);
  canvas.restore();
}

void _paintFlower(Canvas canvas, Offset center, double radius) {
  canvas.save();
  canvas.translate(center.dx, center.dy);
  final petal = Paint()..color = const Color(0xFFFDD835).withValues(alpha: 0.96);
  for (var i = 0; i < 5; i++) {
    final angle = i * 72 * math.pi / 180;
    canvas.drawCircle(
      Offset(math.sin(angle) * radius, -math.cos(angle) * radius),
      radius * 0.62,
      petal,
    );
  }
  canvas.drawCircle(
      Offset.zero, radius * 0.4, Paint()..color = const Color(0xFFF7A600));
  canvas.restore();
}

void _paintPod(
    Canvas canvas, Offset center, double angle, double length, Color color) {
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.rotate(angle);
  canvas.drawOval(
    Rect.fromCenter(
      center: Offset(0, -length / 2),
      width: length * 0.30,
      height: length,
    ),
    Paint()..color = color,
  );
  canvas.restore();
}
