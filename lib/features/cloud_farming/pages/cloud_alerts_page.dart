import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/cloud_engine.dart';
import '../services/cloud_farm_controller.dart';
import '../widgets/cloud_widgets.dart';

class CloudAlertsTab extends ConsumerStatefulWidget {
  const CloudAlertsTab({super.key});

  @override
  ConsumerState<CloudAlertsTab> createState() => _CloudAlertsTabState();
}

class _CloudAlertsTabState extends ConsumerState<CloudAlertsTab> {
  CloudUrgency? _filter;

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(cloudFarmProvider);
    final all = c.alerts;
    final list = _filter == null
        ? all
        : all.where((a) => a.urgency == _filter).toList();
    final high = all.where((a) => a.urgency == CloudUrgency.high).length;

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
          children: [
            const Text('农事提醒'),
            const SizedBox(height: 2),
            Text(
              all.isEmpty ? '暂无待处理提醒' : '${all.length} 项待处理 · 优先 $high 项',
              style: const TextStyle(fontSize: 10, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '提醒设置',
            onPressed: () => _openSettings(c),
            icon: const Icon(Icons.tune),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                CloudPillButton(
                  text: '全部 ${all.length}',
                  active: _filter == null,
                  onTap: () => setState(() => _filter = null),
                ),
                const SizedBox(width: 6),
                CloudPillButton(
                  text: '优先 ${all.where((a) => a.urgency == CloudUrgency.high).length}',
                  active: _filter == CloudUrgency.high,
                  onTap: () => setState(() => _filter = CloudUrgency.high),
                ),
                const SizedBox(width: 6),
                CloudPillButton(
                  text: '建议 ${all.where((a) => a.urgency == CloudUrgency.medium).length}',
                  active: _filter == CloudUrgency.medium,
                  onTap: () => setState(() => _filter = CloudUrgency.medium),
                ),
                const SizedBox(width: 6),
                CloudPillButton(
                  text: '待办 ${all.where((a) => a.urgency == CloudUrgency.low).length}',
                  active: _filter == CloudUrgency.low,
                  onTap: () => setState(() => _filter = CloudUrgency.low),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 60),
              child: Column(
                children: [
                  Icon(Icons.task_alt,
                      size: 46, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 12),
                  const Text('暂无农事提醒',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    'AI 会依据天气、墒情与长势变化自动生成提醒',
                    style: TextStyle(fontSize: 11, color: cloudHint(context)),
                  ),
                ],
              ),
            )
          else
            for (final alert in list)
              CloudAlertCard(
                alert: alert,
                plotName: c.plotById(alert.plotId)?.name ?? '',
                onDone: () => _done(c, alert),
                onSnooze: () {
                  c.snooze(alert.id);
                  _toast('已稍后提醒，24 小时内不再提示');
                },
              ),
          const SizedBox(height: 8),
          Text(
            '提醒依据：GPS 天气 · 土壤墒情模型 · 作物生育期\n完成操作后自动写入田块农事记录',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, height: 1.6, color: cloudHint(context)),
          ),
        ],
      ),
    );
  }

  void _done(CloudFarmController c, CloudAlert alert) {
    if (alert.type == 'calibrate') {
      context.push('/cloud-farm/plot/${alert.plotId}');
      return;
    }
    c.handleAlert(alert);
    _toast('${alert.actionText}已记录');
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }

  void _openSettings(CloudFarmController c) {
    final s = c.state.settings;
    var threshold = s.moistureThreshold.toDouble();
    var calib = s.calibrateDays.toDouble();
    var hour = s.remindHour;
    var auto = s.autoSync;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 18,
            right: 18,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('提醒设置',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Text('灌溉墒情阈值',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text('${threshold.round()}%',
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700)),
                ],
              ),
              Slider(
                value: threshold,
                min: 35,
                max: 80,
                divisions: 9,
                label: '${threshold.round()}%',
                onChanged: (v) => setSheet(() => threshold = v),
              ),
              Row(
                children: [
                  const Text('长势校准周期',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text('每 ${calib.round()} 天',
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700)),
                ],
              ),
              Slider(
                value: calib,
                min: 3,
                max: 21,
                divisions: 6,
                label: '${calib.round()} 天',
                onChanged: (v) => setSheet(() => calib = v),
              ),
              const SizedBox(height: 4),
              const Text('提醒时间',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final h in [7, 8, 12, 18])
                    ChoiceChip(
                      label: Text('$h:00'),
                      selected: hour == h,
                      onSelected: (_) => setSheet(() => hour = h),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('自动同步天气与传感器',
                    style: TextStyle(fontSize: 12.5)),
                subtitle: Text('关闭后仅使用最近一次同步数据',
                    style: TextStyle(fontSize: 10, color: cloudHint(ctx))),
                value: auto,
                onChanged: (v) => setSheet(() => auto = v),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    c.saveSettings(
                      threshold: threshold.round(),
                      calibrateDays: calib.round(),
                      remindHour: hour,
                    );
                    Navigator.pop(ctx);
                    _toast('提醒设置已保存');
                  },
                  child: const Text('保存设置'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
