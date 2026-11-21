import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/cloud_models.dart';
import '../services/cloud_engine.dart';
import '../services/cloud_farm_controller.dart';
import '../widgets/cloud_widgets.dart';
import 'cloud_alerts_page.dart';
import 'cloud_assistant_page.dart';
import 'cloud_plots_page.dart';

class CloudFarmPage extends ConsumerStatefulWidget {
  const CloudFarmPage({super.key});

  @override
  ConsumerState<CloudFarmPage> createState() => _CloudFarmPageState();
}

class _CloudFarmPageState extends ConsumerState<CloudFarmPage> {
  int _index = 0;

  void _switchTab(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(cloudFarmProvider);
    final highCount =
        controller.alerts.where((a) => a.urgency == CloudUrgency.high).length;

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          CloudFarmHomeTab(onSwitchTab: _switchTab),
          const CloudPlotsTab(),
          const CloudAlertsTab(),
          const CloudAssistantTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: _switchTab,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.eco_outlined),
            activeIcon: Icon(Icons.eco),
            label: '农场',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            activeIcon: Icon(Icons.map),
            label: '田块',
          ),
          BottomNavigationBarItem(
            icon: _BadgeIcon(
              icon: Icons.notifications_none,
              count: highCount,
            ),
            activeIcon: _BadgeIcon(
              icon: Icons.notifications,
              count: highCount,
            ),
            label: '提醒',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.auto_awesome_outlined),
            activeIcon: Icon(Icons.auto_awesome),
            label: 'AI',
          ),
        ],
      ),
    );
  }
}

class _BadgeIcon extends StatelessWidget {
  final IconData icon;
  final int count;

  const _BadgeIcon({required this.icon, required this.count});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (count > 0)
          Positioned(
            right: -7,
            top: -5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFD84343),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: const TextStyle(fontSize: 9, color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }
}

class CloudFarmHomeTab extends ConsumerWidget {
  final ValueChanged<int> onSwitchTab;

  const CloudFarmHomeTab({super.key, required this.onSwitchTab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(cloudFarmProvider);
    final alerts = c.alerts;
    final plots = c.plots;
    final totalArea = c.totalArea;
    final highCount = alerts.where((a) => a.urgency == CloudUrgency.high).length;
    final first = alerts.isEmpty ? null : alerts.first;
    final brief = first == null
        ? '今日墒情与长势平稳，保持巡田频次即可。'
        : '${first.title}。${first.window == '雨后再评估' ? '48 小时内有降雨，可暂缓操作并复测墒情。' : '按建议执行，完成后再校准一次云田长势。'}';
    final climate = CloudSeed.region.climate;

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
            const Text('云种植'),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.gps_fixed, size: 10, color: Colors.white70),
                const SizedBox(width: 3),
                Text(
                  '${CloudSeed.region.short} · 已定位',
                  style: const TextStyle(fontSize: 10, color: Colors.white70),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '农事提醒',
            onPressed: () => onSwitchTab(2),
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_outlined),
                if (highCount > 0)
                  Positioned(
                    right: -5,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD84343),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('$highCount',
                          style: const TextStyle(fontSize: 9, color: Colors.white)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          c.refresh();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
          children: [
            _weatherHero(context),
            const SizedBox(height: 12),
            _climateCard(context, climate),
            const SizedBox(height: 12),
            _aiBrief(context, brief, alerts.length, onSwitchTab),
            CloudSectionHead(
              title: '我的田块',
              sub: '${plots.length} 块 · ${totalArea.toStringAsFixed(1)} 亩',
              action: CloudLinkButton(
                '新种植',
                icon: Icons.add,
                onTap: () => _openWizard(context, c),
              ),
            ),
            for (final plot in plots)
              CloudPlotCard(
                plot: plot,
                growth: c.growth(plot),
                moisture: c.moisture(plot),
                onTap: () => context.push('/cloud-farm/plot/${plot.id}'),
              ),
            CloudSectionHead(
              title: '今日农事',
              action: CloudLinkButton(
                '全部',
                icon: Icons.chevron_right,
                onTap: () => onSwitchTab(2),
              ),
            ),
            if (alerts.isEmpty)
              CloudCard(
                child: Center(
                  child: Text(
                    '今日暂无农事待办，AI 会持续监测墒情与天气。',
                    style: TextStyle(fontSize: 11, color: cloudHint(context)),
                  ),
                ),
              )
            else
              for (final alert in alerts.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: cloudCardColor(context),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onSwitchTab(2),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: cloudSoft(alert.color, context),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Icon(alert.icon, size: 16, color: alert.color),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(alert.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${alert.window} · ${alert.actionText}',
                                    style: TextStyle(
                                        fontSize: 10, color: cloudHint(context)),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right,
                                size: 16, color: cloudHint(context)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            const CloudSectionHead(title: '云种植概览'),
            CloudCard(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  _stat(context, totalArea.toStringAsFixed(1), '亩', '1:1 建模面积'),
                  _statDivider(context),
                  _stat(context, '${c.plantedCount}', '种', '在线作物'),
                  _statDivider(context),
                  _stat(context, '${alerts.length}', '项', '今日待办'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '数据来源：GPS 定位 + 区域气候 + AI 墒情模型\n云田进度与实体种植同步，偏差可在田块详情中校准',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, height: 1.6, color: cloudHint(context)),
            ),
          ],
        ),
      ),
    );
  }

  void _openWizard(BuildContext context, CloudFarmController c) {
    final empty = c.plots.where((p) => p.cropId == null).toList();
    context.push(
      '/cloud-farm/plant',
      extra: {'plotId': empty.isNotEmpty ? empty.first.id : null},
    );
  }

  Widget _weatherHero(BuildContext context) {
    final w = CloudSeed.weather;
    const white = Colors.white;
    final days = w.forecast.take(4).toList();
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2E7D32).withValues(alpha: 0.28),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.gps_fixed, size: 13, color: Colors.white70),
              const SizedBox(width: 4),
              Text(
                '${CloudSeed.region.short} · 定位精度 ±${CloudSeed.region.accuracy}m',
                style: const TextStyle(fontSize: 10.5, color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${w.temp}',
                      style: const TextStyle(
                          fontSize: 42, color: white, fontWeight: FontWeight.w300)),
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Text('℃', style: TextStyle(fontSize: 14, color: Colors.white70)),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${w.desc} · 土壤温度 ${w.soilTemp}℃',
                    style: const TextStyle(fontSize: 10.5, color: white, height: 1.4),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(w.desc,
                      style: const TextStyle(
                          fontSize: 12, color: white, fontWeight: FontWeight.w600)),
                  Text('湿度 ${w.humidity}%',
                      style: const TextStyle(fontSize: 10.5, color: Colors.white70)),
                  Text('${w.windDir} ${w.wind}m/s',
                      style: const TextStyle(fontSize: 10.5, color: Colors.white70)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _wxMetric(Icons.water_drop_outlined, '空气湿度', '${w.humidity}%'),
              _wxMetric(Icons.umbrella_outlined, '降水概率', '${w.rainProb}%'),
              _wxMetric(Icons.air, '风速', '${w.wind}m/s'),
            ],
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.18)),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < days.length; i++)
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    decoration: BoxDecoration(
                      color: i == 0
                          ? Colors.white.withValues(alpha: 0.16)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Column(
                      children: [
                        Text(days[i].label,
                            style: const TextStyle(fontSize: 10, color: Colors.white70)),
                        const SizedBox(height: 3),
                        Icon(_weatherIcon(days[i].icon),
                            size: 15, color: Colors.white),
                        const SizedBox(height: 2),
                        Text('${days[i].hi}°',
                            style: const TextStyle(fontSize: 11, color: white)),
                        Text('${days[i].rain}%',
                            style: const TextStyle(fontSize: 9, color: Colors.white70)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _wxMetric(IconData icon, String label, String value) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Row(
          children: [
            Icon(icon, size: 15, color: Colors.white70),
            const SizedBox(width: 5),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 9.5, color: Colors.white70)),
                Text(value,
                    style: const TextStyle(
                        fontSize: 11.5,
                        color: Colors.white,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _climateCard(BuildContext context, CloudClimate cl) {
    return CloudCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.eco, size: 15, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 5),
              const Text('本地立地条件',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const Spacer(),
              CloudTag('GPS 自动获取', color: cloudSubtle(context)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _climateItem('${cl.annualTemp}℃', '年均温'),
              _climateItem('${cl.rainfall}mm', '年降水'),
              _climateItem('${cl.frostFree}天', '无霜期'),
              _climateItem('${cl.accumTemp}℃', '≥10℃积温'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.gps_fixed, size: 11, color: cloudHint(context)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${cl.zone} · ${cl.pattern} · 土壤 ${cl.soil}',
                  style: TextStyle(fontSize: 10, color: cloudSubtle(context)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _climateItem(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 9.5, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _aiBrief(BuildContext context, String brief, int count,
      ValueChanged<int> onSwitchTab) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cloudSoft(primary, context, light: 0.10, dark: 0.18),
            cloudSoft(primary, context, light: 0.02, dark: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: primary.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: cloudSoft(primary, context),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(Icons.auto_awesome, size: 17, color: primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('AI 农事简报',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 6),
                    CloudTag('今日', color: primary),
                  ],
                ),
                const SizedBox(height: 4),
                Text(brief,
                    style: TextStyle(
                        fontSize: 11, height: 1.5, color: cloudSubtle(context))),
                const SizedBox(height: 2),
                CloudLinkButton(
                  '查看 $count 项建议',
                  icon: Icons.chevron_right,
                  onTap: () => onSwitchTab(2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String value, String unit, String label) {
    return Expanded(
      child: Column(
        children: [
          Text.rich(
            TextSpan(
              text: value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              children: [
                TextSpan(
                  text: unit,
                  style: TextStyle(fontSize: 10, color: cloudHint(context)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10, color: cloudHint(context))),
        ],
      ),
    );
  }

  Widget _statDivider(BuildContext context) {
    return Container(
      height: 28,
      width: 1,
      color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
    );
  }

  IconData _weatherIcon(String name) {
    switch (name) {
      case 'sun':
        return Icons.wb_sunny_outlined;
      case 'rain':
      case 'storm':
        return Icons.water_drop_outlined;
      case 'partly':
      case 'cloud':
      default:
        return Icons.cloud_outlined;
    }
  }
}
