import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/cloud_models.dart';
import '../services/cloud_engine.dart';
import '../services/cloud_farm_controller.dart';
import '../widgets/cloud_widgets.dart';

/// 向导步骤 key 与步骤名
const Map<String, String> _wizardStepLabels = {
  'crop': '选作物',
  'plot': '定田块',
  'date': '种植日期',
  'soil': '土壤问卷',
};

class CloudPlantingWizardPage extends ConsumerStatefulWidget {
  final String? initialPlotId;

  const CloudPlantingWizardPage({super.key, this.initialPlotId});

  @override
  ConsumerState<CloudPlantingWizardPage> createState() =>
      _CloudPlantingWizardPageState();
}

class _CloudPlantingWizardPageState
    extends ConsumerState<CloudPlantingWizardPage> {
  int _step = 0;
  bool _pinned = false;
  String _cropId = 'rapeseed';
  String? _plotId;
  DateTime _sow = DateTime.now();
  String _soil = 'loam';
  String _irrigation = 'drip';
  String _fertAge = '30d';

  @override
  void initState() {
    super.initState();
    // 从圈地页 / 田块页带入田块时视为已指定田块，跳过「定田块」步骤
    _pinned = widget.initialPlotId != null;
    _sow = _dateOnly(DateTime.now());
    final c = ref.read(cloudFarmProvider);
    final empty = c.plots.where((p) => p.cropId == null).toList();
    _plotId = widget.initialPlotId ??
        (empty.isNotEmpty
            ? empty.first.id
            : (c.plots.isNotEmpty ? c.plots.first.id : null));
    final plot = c.plotById(_plotId);
    if (plot != null) {
      _soil = plot.soil;
      _irrigation = plot.irrigation;
    }
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime get _today => _dateOnly(DateTime.now());

  /// 已指定田块时 3 步，否则 4 步
  List<String> get _order =>
      _pinned ? const ['crop', 'date', 'soil'] : const ['crop', 'plot', 'date', 'soil'];

  String get _key => _order[_step.clamp(0, _order.length - 1)];

  CropInfo get _crop => CloudSeed.crops[_cropId]!;

  PlantingPlan _plan() => CloudEngine.inferPlan(
        crop: _crop,
        plot: ref.read(cloudFarmProvider).plotById(_plotId),
        soil: _soil,
        irrigation: _irrigation,
        sow: _sow,
        fertAge: _fertAge,
      );

  bool get _dateValid => !_sow.isAfter(_today);

  bool get _canNext {
    switch (_key) {
      case 'plot':
        return _plotId != null;
      case 'date':
        return _dateValid;
      default:
        return true;
    }
  }

  String get _nextLabel {
    switch (_key) {
      case 'crop':
        return _pinned ? '下一步 · 种植日期' : '下一步 · 定田块';
      case 'plot':
        return '下一步 · 种植日期';
      case 'date':
        return '下一步 · 土壤问卷';
      default:
        return '生成种植方案';
    }
  }

  void _next() {
    final key = _key;
    if (key == 'crop') {
      final plot = ref.read(cloudFarmProvider).plotById(_plotId);
      if (plot != null) {
        _soil = plot.soil;
        _irrigation = plot.irrigation;
      }
      _advance();
      return;
    }
    if (key == 'plot') {
      if (_plotId == null) {
        _toast('请选择一块田块');
        return;
      }
      final plot = ref.read(cloudFarmProvider).plotById(_plotId);
      if (plot != null) {
        _soil = plot.soil;
        _irrigation = plot.irrigation;
      }
      _advance();
      return;
    }
    if (key == 'date') {
      if (!_dateValid) {
        _toast('请选择不晚于今天的播种日期');
        return;
      }
      _advance();
      return;
    }
    _showPlan();
  }

  void _advance() {
    if (_step < _order.length - 1) setState(() => _step++);
  }

  /// 选中即前进：避免还要再点一次「下一步」
  void _autoNext(String fromKey) {
    Future.delayed(const Duration(milliseconds: 260), () {
      if (!mounted || _key != fromKey) return;
      _next();
    });
  }

  void _switchPlot() {
    setState(() {
      _pinned = false;
      _step = _order.indexOf('plot');
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(cloudFarmProvider);
    final key = _key;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('云种植向导'),
            const SizedBox(height: 2),
            Text(
              '第 ${_step + 1}/${_order.length} 步 · ${_wizardStepLabels[key]}',
              style: const TextStyle(fontSize: 10, color: Colors.white70),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          _stepHeader(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: KeyedSubtree(
                key: ValueKey<String>(key),
                child: _bodyFor(key, c),
              ),
            ),
          ),
          _bottomBar(),
        ],
      ),
    );
  }

  Widget _bodyFor(String key, CloudFarmController c) {
    switch (key) {
      case 'plot':
        return _plotStep(c);
      case 'date':
        return _dateStep();
      case 'soil':
        return _soilStep(c);
      default:
        return _cropStep(c);
    }
  }

  Widget _stepHeader() {
    final primary = Theme.of(context).colorScheme.primary;
    final labels = _order.map((k) => _wizardStepLabels[k]!).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= _step
                          ? primary
                          : Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 9.5,
                      color: i <= _step ? primary : cloudHint(context),
                      fontWeight:
                          i == _step ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            if (i < labels.length - 1)
              SizedBox(
                width: 10,
                child: Center(
                  child: Text('·',
                      style: TextStyle(fontSize: 10, color: cloudHint(context))),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// 示例指引卡（对应原网页 guide-card）
  Widget _guideCard(List<InlineSpan> spans) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cloudSoft(primary, context, light: 0.06, dark: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.menu_book_outlined, size: 13, color: primary),
              const SizedBox(width: 4),
              Text('示例指引',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: primary)),
            ],
          ),
          const SizedBox(height: 5),
          Text.rich(
            TextSpan(
              style: TextStyle(
                  fontSize: 10.5, height: 1.55, color: cloudSubtle(context)),
              children: spans,
            ),
          ),
        ],
      ),
    );
  }

  /// 定位 + 气候卡（地名取实时定位）
  Widget _climateCard(CloudLocation loc) {
    final cl = CloudSeed.region.climate;
    final name = loc.name.trim().isEmpty ? CloudSeed.region.short : loc.name.trim();
    final accuracy = loc.accuracy;
    final accuracyText = (accuracy == null || accuracy <= 0)
        ? '定位精度未知'
        : '定位精度 ±${accuracy >= 10 ? accuracy.round().toString() : accuracy.toStringAsFixed(1)}m';
    final primary = Theme.of(context).colorScheme.primary;
    return CloudCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.gps_fixed, size: 13, color: primary),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 6),
              CloudTag(accuracyText, color: primary),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _climateItem('${cl.annualTemp}℃', '年均温'),
              _climateItem('${cl.rainfall}mm', '年降水'),
              _climateItem('${cl.frostFree}天', '无霜期'),
              _climateItem(cl.pattern.replaceAll(' · ', '·'), '本地熟制'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _climateItem(String value, String label) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11.5, height: 1.2, fontWeight: FontWeight.w700)),
          const SizedBox(height: 1),
          Text(label,
              style: TextStyle(fontSize: 9.5, color: cloudHint(context))),
        ],
      ),
    );
  }

  Widget _cropStep(CloudFarmController c) {
    final plot = c.plotById(_plotId);
    final ids = [...CloudSeed.cropIds]
      ..sort((a, b) =>
          CloudSeed.crops[b]!.suitability.compareTo(CloudSeed.crops[a]!.suitability));
    final top = CloudSeed.crops[ids.first]!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      children: [
        _climateCard(c.location),
        if (_pinned && plot != null) ...[
          const SizedBox(height: 10),
          CloudCard(
            child: Row(
              children: [
                PlotThumb(cropId: plot.cropId, width: 38, height: 38),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('已选田块',
                          style:
                              TextStyle(fontSize: 9.5, color: cloudHint(context))),
                      const SizedBox(height: 1),
                      Text(
                        '${plot.name} · ${plot.area.toStringAsFixed(1)} 亩 · ${plot.buildSource}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                CloudLinkButton('换田块',
                    icon: Icons.swap_horiz, onTap: _switchPlot),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        _guideCard([
          TextSpan(
            text:
                '先选作物。带「本地主栽」标签的作物与当前气候最匹配，例如${top.name}适宜度最高；选错也没关系，下一步还能改。',
          ),
        ]),
        const CloudSectionHead(
          title: '选择作物',
          sub: '按本地气候与“几年几熟”推荐',
        ),
        for (final id in ids) _cropCard(CloudSeed.crops[id]!),
        Row(
          children: [
            Icon(Icons.auto_awesome,
                size: 12, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '适宜度由 AI 结合年均温、降水、无霜期、熟制与土壤条件计算，仅作种植决策参考。',
                style: TextStyle(
                    fontSize: 9.5, height: 1.45, color: cloudHint(context)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '当前选择：${_crop.name} · ${_crop.pattern}',
          style: TextStyle(fontSize: 10, color: cloudHint(context)),
        ),
      ],
    );
  }

  Widget _cropCard(CropInfo crop) {
    final selected = _cropId == crop.id;
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: selected
            ? cloudSoft(primary, context, light: 0.08, dark: 0.16)
            : cloudCardColor(context),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () {
            setState(() => _cropId = crop.id);
            _autoNext('crop');
          },
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? primary
                    : Theme.of(context).dividerColor.withValues(alpha: 0.45),
                width: selected ? 1.8 : 1,
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: cloudSoft(cropColor(crop.id), context),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(cropGlyph(crop.id),
                          size: 23, color: cropColor(crop.id)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(crop.name,
                                  style: const TextStyle(
                                      fontSize: 14, fontWeight: FontWeight.w700)),
                              const SizedBox(width: 6),
                              CloudTag(crop.suitable,
                                  color: cropColor(crop.id)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text('${crop.variety} · ${crop.season}',
                              style: TextStyle(
                                  fontSize: 10.5, color: cloudSubtle(context))),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${crop.suitability}',
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: primary)),
                        Text('适宜度',
                            style: TextStyle(
                                fontSize: 9, color: cloudHint(context))),
                      ],
                    ),
                    const SizedBox(width: 4),
                    if (selected)
                      Icon(Icons.check_circle, size: 18, color: primary),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _cropInfo('播期', crop.sowWindow),
                    _cropInfo('全周期', '${crop.cycle} 天'),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    _cropInfo('目标产量', '${crop.yield} kg/亩'),
                    _cropInfo('需水', crop.waterNeed),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  crop.reason,
                  style: TextStyle(
                      fontSize: 10, height: 1.45, color: cloudHint(context)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cropInfo(String label, String value) {
    return Expanded(
      child: RichText(
        text: TextSpan(
          style: TextStyle(fontSize: 10, color: cloudHint(context)),
          children: [
            TextSpan(text: '$label '),
            TextSpan(
              text: value,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _plotStep(CloudFarmController c) {
    final selected = c.plotById(_plotId);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      children: [
        _guideCard([
          const TextSpan(
            text:
                '选择一块标注「空闲可种植」的田块；已有作物的田块不能重复绑定，需要另圈新田。',
          ),
        ]),
        const CloudSectionHead(
          title: '选择田块',
          sub: 'GPS 边界已 1:1 建模',
        ),
        if (c.plots.isEmpty)
          CloudCard(
            child: Text('还没有田块，请先在地图上圈地建模。',
                style: TextStyle(fontSize: 11, color: cloudHint(context))),
          )
        else
          SizedBox(
            height: 118,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: c.plots.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final plot = c.plots[i];
                final active = plot.id == _plotId;
                return InkWell(
                  onTap: () {
                    setState(() {
                      _plotId = plot.id;
                      _soil = plot.soil;
                      _irrigation = plot.irrigation;
                    });
                    _autoNext('plot');
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: 148,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: active
                          ? cloudSoft(Theme.of(context).colorScheme.primary,
                              context,
                              light: 0.08, dark: 0.16)
                          : cloudCardColor(context),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: active
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context)
                                .dividerColor
                                .withValues(alpha: 0.45),
                        width: active ? 1.8 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            PlotThumb(cropId: plot.cropId, width: 34, height: 34),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(plot.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        Text('${plot.area.toStringAsFixed(1)} 亩',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.primary)),
                        Text(
                          plot.cropId == null
                              ? '未种植 · 可直接开工'
                              : '已有${CloudSeed.cropOf(plot.cropId)?.name}，将覆盖',
                          style: TextStyle(
                              fontSize: 9.5, color: cloudHint(context)),
                        ),
                        const Spacer(),
                        if (active)
                          Row(
                            children: [
                              Icon(Icons.check_circle,
                                  size: 12,
                                  color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 3),
                              Text('已选择',
                                  style: TextStyle(
                                      fontSize: 9.5,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary)),
                            ],
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 4),
        CloudLinkButton(
          '去圈一块新田',
          icon: Icons.add,
          onTap: () => context.push('/cloud-farm/create'),
        ),
        const SizedBox(height: 8),
        CloudCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('种植面积',
                      style: TextStyle(fontSize: 11, color: cloudHint(context))),
                  const SizedBox(width: 8),
                  Text(
                    selected == null ? '—' : selected.area.toStringAsFixed(1),
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        color: Theme.of(context).colorScheme.primary),
                  ),
                  const SizedBox(width: 2),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text('亩',
                        style:
                            TextStyle(fontSize: 10, color: cloudHint(context))),
                  ),
                  const Spacer(),
                  CloudTag(selected?.buildSource ?? '待选择田块',
                      color: Theme.of(context).colorScheme.primary),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.straighten,
                      size: 12, color: cloudHint(context)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text('面积由 GPS 边界计算，与实体田块保持 1:1。',
                        style: TextStyle(
                            fontSize: 9.5, color: cloudHint(context))),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dateStep() {
    final crop = _crop;
    final est = _sowEstimate(crop);
    final bad = !_dateValid;
    final primary = Theme.of(context).colorScheme.primary;
    const quicks = [
      ('今天', 0),
      ('7 天前', -7),
      ('15 天前', -15),
      ('30 天前', -30),
      ('60 天前', -60),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      children: [
        _guideCard([
          const TextSpan(text: '如果是之前已经种下的作物，把日期改成'),
          const TextSpan(
            text: '实际播种日',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const TextSpan(
            text:
                '（例如 10 月 8 日），云田会自动跳到当前应处的生长阶段；今天新种就保持默认。',
          ),
        ]),
        const CloudSectionHead(
          title: '种植日期',
          sub: '按实际播种日推算生长阶段',
        ),
        CloudCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('实际播种日期',
                  style: TextStyle(fontSize: 10.5, color: cloudHint(context))),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.event_outlined, size: 15, color: primary),
                  const SizedBox(width: 6),
                  Text('${CloudEngine.fmtFull(_sow)} ${CloudEngine.weekday(_sow)}',
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  CloudLinkButton(
                    '修改',
                    icon: Icons.edit_outlined,
                    onTap: _pickDate,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final q in quicks)
                    CloudPillButton(
                      text: q.$1,
                      active: _sow.isAtSameMomentAs(
                          _today.add(Duration(days: q.$2))),
                      onTap: () => setState(
                          () => _sow = _today.add(Duration(days: q.$2))),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              _datePreview(est, bad),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '全生育期 ${crop.cycle} 天 · 适宜播期 ${crop.sowWindow}',
          style: TextStyle(fontSize: 10, color: cloudHint(context)),
        ),
      ],
    );
  }

  Widget _datePreview(_SowEstimate? est, bool bad) {
    final errColor = Theme.of(context).colorScheme.error;
    if (est == null || bad) {
      return Row(
        children: [
          Icon(Icons.info_outline, size: 13, color: errColor),
          const SizedBox(width: 4),
          Expanded(
            child: Text('播种日期不能晚于今天',
                style: TextStyle(fontSize: 10.5, color: errColor)),
          ),
        ],
      );
    }
    if (est.over) {
      return Row(
        children: [
          Icon(Icons.info_outline, size: 13, color: cloudHint(context)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '已超过 ${_crop.cycle} 天全生育期，将按成熟期估算。',
              style: TextStyle(fontSize: 10.5, color: cloudHint(context)),
            ),
          ),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cloudSoft(Theme.of(context).colorScheme.primary, context,
            light: 0.05, dark: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _dateStat('第 ${est.day} 天', '已生长'),
          _dateStat('${est.stage.name}期', '当前阶段'),
          _dateStat('${est.left} 天', '距成熟'),
        ],
      ),
    );
  }

  Widget _dateStat(String value, String label) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 1),
          Text(label,
              style: TextStyle(fontSize: 9.5, color: cloudHint(context))),
        ],
      ),
    );
  }

  _SowEstimate _sowEstimate(CropInfo crop) {
    final raw = DateTime.now().difference(_sow).inDays;
    final day = raw < 0 ? 0 : raw;
    final at = day > crop.cycle ? crop.cycle : day;
    var idx = 0;
    for (var i = 0; i < crop.stages.length; i++) {
      if (at >= crop.stages[i].s) idx = i;
    }
    return _SowEstimate(
      day: day,
      stage: crop.stages[idx],
      over: raw > crop.cycle,
      left: crop.cycle - day < 0 ? 0 : crop.cycle - day,
    );
  }

  Widget _soilStep(CloudFarmController c) {
    final plan = _plan();
    final plot = c.plotById(_plotId);
    final primary = Theme.of(context).colorScheme.primary;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      children: [
        CloudCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_crop.name} · ${plot?.name ?? '未选择田块'}',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    if (plot != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${plot.area.toStringAsFixed(1)} 亩 · ${plot.buildSource}',
                        style: TextStyle(
                            fontSize: 9.5, color: cloudHint(context)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: () =>
                    setState(() => _step = _order.indexOf('date')),
                borderRadius: BorderRadius.circular(20),
                child: CloudTag(
                  '${_sow.month}月${_sow.day}日',
                  icon: Icons.calendar_today,
                  color: primary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _guideCard([
          const TextSpan(
            text:
                '按实际情况填写土壤、灌溉和最近施肥。墒情由天气 + 土壤 + 灌溉推算，问卷越准确，提醒越贴近田里真实情况。',
          ),
        ]),
        const CloudSectionHead(
          title: '土壤条件问卷',
          sub: 'AI 据此推断墒情',
        ),
        CloudCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('土壤质地',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 7),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in CloudSeed.soils.values)
                    CloudPillButton(
                      text: s.name,
                      active: _soil == s.key,
                      onTap: () => setState(() => _soil = s.key),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(CloudSeed.soilOf(_soil).desc,
                  style: TextStyle(fontSize: 10, color: cloudHint(context))),
              const SizedBox(height: 12),
              const Text('灌溉条件',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 7),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final i in CloudSeed.irrigations.values)
                    CloudPillButton(
                      text: i.name,
                      active: _irrigation == i.key,
                      onTap: () => setState(() => _irrigation = i.key),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('最近一次施肥',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 7),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final f in const [
                    ('7d', '一周内'),
                    ('15d', '半月前'),
                    ('30d', '1 个月前'),
                    ('none', '未施肥 / 更早'),
                  ])
                    CloudPillButton(
                      text: f.$2,
                      active: _fertAge == f.$1,
                      onTap: () => setState(() => _fertAge = f.$1),
                    ),
                ],
              ),
            ],
          ),
        ),
        const CloudSectionHead(
          title: 'AI 方案预判',
          sub: '土壤问卷 + 气候 + 作物模型',
        ),
        _planCard(plan, compact: true),
      ],
    );
  }

  Widget _planCard(PlantingPlan plan, {bool compact = false}) {
    final primary = Theme.of(context).colorScheme.primary;
    return CloudCard(
      border: Border.all(color: primary.withValues(alpha: 0.30)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: cloudSoft(primary, context),
                  borderRadius: BorderRadius.circular(23),
                ),
                child: Center(
                  child: Text('${plan.score}',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: primary)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${plan.crop.name} · 适宜度 ${plan.score} 分',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    Text(
                      '${plan.crop.variety} · ${CloudSeed.soilOf(_soil).name} · ${CloudSeed.irrigationOf(_irrigation).name}',
                      style: TextStyle(fontSize: 10, color: cloudHint(context)),
                    ),
                  ],
                ),
              ),
              CloudTag(plan.late ? '晚播' : '适期',
                  color: plan.late ? const Color(0xFFB96B00) : primary),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _planItem('播种日期', CloudEngine.fmtDate(plan.sow)),
              _planItem('预计采收', CloudEngine.fmtDate(plan.harvest)),
              _planItem('全周期', '${plan.crop.cycle} 天'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _planItem('建议密度', '${plan.density} 株/亩'),
              _planItem('目标产量', '${plan.crop.yield} kg/亩'),
              _planItem('当前墒情', '${plan.moisture.value}%'),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: cloudSoft(primary, context, light: 0.06, dark: 0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 12, color: primary),
                    const SizedBox(width: 4),
                    const Text('AI 风险提示',
                        style: TextStyle(
                            fontSize: 10.5, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(plan.risk,
                    style: TextStyle(
                        fontSize: 10, height: 1.5, color: cloudSubtle(context))),
              ],
            ),
          ),
          if (!compact) ...[
            const SizedBox(height: 10),
            Text(
              '关键节点：${plan.crop.stages.take(4).map((s) => s.name).join(' → ')} → 成熟',
              style: TextStyle(fontSize: 10, color: cloudHint(context)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _planItem(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 9.5, color: cloudHint(context))),
          const SizedBox(height: 1),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: cloudCardColor(context),
        border: Border(
          top: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.5)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (_step > 0)
              Expanded(
                flex: 1,
                child: OutlinedButton(
                  onPressed: () => setState(() => _step--),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 46),
                  ),
                  child: const Text('上一步'),
                ),
              ),
            if (_step > 0) const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: _canNext ? _next : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 46),
                ),
                child: Text(_nextLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _sow,
      firstDate: _today.subtract(const Duration(days: 730)),
      lastDate: _today,
    );
    if (picked != null) setState(() => _sow = _dateOnly(picked));
  }

  void _showPlan() {
    final c = ref.read(cloudFarmProvider);
    final plot = c.plotById(_plotId);
    if (plot == null) {
      _toast('请先选择田块');
      return;
    }
    final plan = _plan();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('种植方案确认',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Text('${plot.name} · ${plot.area.toStringAsFixed(1)} 亩',
                    style: TextStyle(fontSize: 11, color: cloudHint(ctx))),
                const SizedBox(height: 12),
                _planCard(plan),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      c.applyPlanting(
                        plot: plot,
                        crop: plan.crop,
                        soil: _soil,
                        irrigation: _irrigation,
                        fertilizer: _fertAge == 'none' ? '待施肥' : '复合肥（15-15-15）',
                        sow: _sow,
                        fertAge: _fertAge,
                        score: plan.score,
                      );
                      Navigator.pop(ctx);
                      _toast('云种植建档完成，开始逐日生长');
                      context.pushReplacement('/cloud-farm/plot/${plot.id}');
                    },
                    icon: const Icon(Icons.eco, size: 17),
                    label: const Text('确认种植 · 生成云田'),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '种植后可在田块详情查看动态长势、墒情推断与农事提醒',
                  style: TextStyle(fontSize: 10, color: cloudHint(ctx)),
                ),
              ],
            ),
          ),
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

/// 播种日期 -> 生长阶段预估（对齐原网页 dateEstimate）
class _SowEstimate {
  final int day;
  final CropStage stage;
  final bool over;
  final int left;

  const _SowEstimate({
    required this.day,
    required this.stage,
    required this.over,
    required this.left,
  });
}
