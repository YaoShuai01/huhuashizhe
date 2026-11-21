import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/cloud_models.dart';
import '../services/cloud_engine.dart';
import '../services/cloud_farm_controller.dart';
import '../widgets/cloud_widgets.dart';

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
  String _cropId = 'rapeseed';
  String? _plotId;
  DateTime _sow = DateTime.now();
  String _soil = 'loam';
  String _irrigation = 'drip';
  String _fertAge = '30d';

  @override
  void initState() {
    super.initState();
    final c = ref.read(cloudFarmProvider);
    final empty = c.plots.where((p) => p.cropId == null).toList();
    _plotId = widget.initialPlotId ??
        (empty.isNotEmpty ? empty.first.id : (c.plots.isNotEmpty ? c.plots.first.id : null));
    if (_plotId != null) {
      final plot = c.plotById(_plotId);
      if (plot != null) {
        _soil = plot.soil;
        _irrigation = plot.irrigation;
      }
    }
  }

  CropInfo get _crop => CloudSeed.crops[_cropId]!;

  PlantingPlan _plan() => CloudEngine.inferPlan(
        crop: _crop,
        plot: ref.read(cloudFarmProvider).plotById(_plotId),
        soil: _soil,
        irrigation: _irrigation,
        sow: _sow,
        fertAge: _fertAge,
      );

  bool get _canNext {
    if (_step == 0) return _cropId.isNotEmpty;
    if (_step == 1) return _plotId != null;
    return true;
  }

  void _next() {
    if (_step < 2) {
      setState(() => _step++);
    } else {
      _showPlan();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(cloudFarmProvider);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('云种植向导'),
            const SizedBox(height: 2),
            Text('第 ${_step + 1}/3 步 · ${['选择作物', '确认田块', '土壤问卷'][_step]}',
                style: const TextStyle(fontSize: 10, color: Colors.white70)),
          ],
        ),
      ),
      body: Column(
        children: [
          _stepHeader(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: IndexedStack(
                index: _step,
                children: [
                  _cropStep(c),
                  _plotStep(c),
                  _soilStep(),
                ],
              ),
            ),
          ),
          _bottomBar(),
        ],
      ),
    );
  }

  Widget _stepHeader() {
    final primary = Theme.of(context).colorScheme.primary;
    const labels = ['选作物', '定田块', '土壤问卷'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
      child: Row(
        children: [
          for (var i = 0; i < 3; i++) ...[
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
            if (i < 2)
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

  Widget _cropStep(CloudFarmController c) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      children: [
        Row(
          children: [
            const Text('根据立地条件推荐',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const Spacer(),
            CloudTag('${CloudSeed.region.short} 适宜度排序',
                color: Theme.of(context).colorScheme.primary),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${CloudSeed.region.climate.zone} · ${CloudSeed.region.climate.pattern}',
          style: TextStyle(fontSize: 10.5, color: cloudHint(context)),
        ),
        const SizedBox(height: 10),
        for (final id in CloudSeed.cropIds) _cropCard(CloudSeed.crops[id]!),
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
          onTap: () => setState(() => _cropId = crop.id),
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
        Row(
          children: [
            const Text('选择已有田块',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const Spacer(),
            CloudLinkButton(
              '去圈地',
              icon: Icons.add,
              onTap: () => context.push('/cloud-farm/create'),
            ),
          ],
        ),
        const SizedBox(height: 8),
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
                  onTap: () => setState(() {
                    _plotId = plot.id;
                    _soil = plot.soil;
                    _irrigation = plot.irrigation;
                  }),
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
        const CloudSectionHead(title: '播种日期'),
        CloudCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.event_outlined,
                      size: 15, color: Theme.of(context).colorScheme.primary),
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
              const SizedBox(height: 6),
              Text('推荐播期 ${_crop.sowWindow}',
                  style: TextStyle(fontSize: 10.5, color: cloudHint(context))),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (selected != null)
          CloudCard(
            child: Row(
              children: [
                PlotThumb(cropId: selected.cropId, width: 46, height: 46),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(selected.name,
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        '${selected.area.toStringAsFixed(1)} 亩 · ${CloudSeed.soilOf(selected.soil).name} · ${CloudSeed.irrigationOf(selected.irrigation).name}',
                        style:
                            TextStyle(fontSize: 10, color: cloudHint(context)),
                      ),
                    ],
                  ),
                ),
                CloudTag('1:1 建模',
                    color: Theme.of(context).colorScheme.primary),
              ],
            ),
          ),
      ],
    );
  }

  Widget _soilStep() {
    final plan = _plan();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      children: [
        const Text('土壤与灌溉条件',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
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
              _planItem('播种', CloudEngine.fmtDate(plan.sow)),
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
                child: Text(_step == 2 ? '生成种植方案' : '下一步'),
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
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (picked != null) setState(() => _sow = picked);
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
                    label: Text('确认种植 · 生成云田'),
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
