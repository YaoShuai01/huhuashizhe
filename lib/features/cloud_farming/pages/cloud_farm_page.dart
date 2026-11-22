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

class CloudFarmHomeTab extends ConsumerStatefulWidget {
  final ValueChanged<int> onSwitchTab;

  const CloudFarmHomeTab({super.key, required this.onSwitchTab});

  @override
  ConsumerState<CloudFarmHomeTab> createState() => _CloudFarmHomeTabState();
}

class _CloudFarmHomeTabState extends ConsumerState<CloudFarmHomeTab> {
  late bool _guideOpen;

  @override
  void initState() {
    super.initState();
    final c = ref.read(cloudFarmProvider);
    _guideOpen = !c.guideSeen;
    if (_guideOpen) c.markGuideSeen();
  }

  @override
  Widget build(BuildContext context) {
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
        title: InkWell(
          onTap: () => _openLocationSheet(context),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('云种植'),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      c.lastLocateError == null
                          ? Icons.gps_fixed
                          : Icons.gps_off,
                      size: 10,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 3),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 190),
                      child: Text(
                        _locationBarText(c),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: Colors.white70),
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.expand_more,
                        size: 12, color: Colors.white70),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: '农事提醒',
            onPressed: () => widget.onSwitchTab(2),
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
          await c.refresh();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
          children: [
            _weatherHero(context, c),
            const SizedBox(height: 12),
            _guideCard(context),
            const SizedBox(height: 12),
            _climateCard(context, climate),
            const SizedBox(height: 12),
            _aiBrief(context, brief, alerts.length, widget.onSwitchTab),
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
                onTap: () => widget.onSwitchTab(2),
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
                      onTap: () => widget.onSwitchTab(2),
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

  String _locationBarText(CloudFarmController c) {
    final loc = c.location;
    final failed = c.lastLocateError != null;
    if (loc.isSeed) {
      return failed ? '未定位 · 定位失败' : '未定位 · 示例位置';
    }
    final name = loc.name.isEmpty ? '未定位' : loc.name;
    if (failed) return '$name · 定位失败';
    final status = loc.fromGps
        ? '已定位'
        : loc.isManual
            ? '手动位置'
            : '示例位置';
    return '$name · $status';
  }

  Future<void> _openLocationSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CloudLocationSheet(),
    );
  }

  void _toggleGuide() {
    setState(() => _guideOpen = !_guideOpen);
  }

  Widget _guideCard(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return CloudCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: _toggleGuide,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(Icons.menu_book_outlined, size: 15, color: primary),
                  const SizedBox(width: 5),
                  const Text('云种植怎么用',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 6),
                  CloudTag('4 步上手', color: cloudSubtle(context)),
                  const Spacer(),
                  Text(_guideOpen ? '收起' : '展开',
                      style: TextStyle(fontSize: 11, color: primary)),
                  Icon(
                    _guideOpen ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: primary,
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: _guideOpen
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 10),
                      _guideStep(
                        context,
                        '1',
                        '定位 / 修正位置',
                        '点顶部定位栏，重新获取 GPS 或手动填写经纬度。',
                      ),
                      _guideStep(
                        context,
                        '2',
                        '圈一块田',
                        '去「田块」页 → 圈地，沿田埂至少点 3 个边界点，可拖动调整。',
                      ),
                      _guideStep(
                        context,
                        '3',
                        '选作物 + 种植日期',
                        '向导会按实际播种日推算当前生长阶段与剩余天数。',
                      ),
                      _guideStep(
                        context,
                        '4',
                        '日常跟着提醒做',
                        '灌溉 / 施肥 / 校准完成后记录，云田进度自动同步。',
                      ),
                    ],
                  )
                : const SizedBox(width: double.infinity, height: 0),
          ),
        ],
      ),
    );
  }

  Widget _guideStep(
    BuildContext context,
    String index,
    String title,
    String desc,
  ) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cloudSoft(primary, context),
              shape: BoxShape.circle,
            ),
            child: Text(
              index,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: TextStyle(
                      fontSize: 10.5,
                      height: 1.45,
                      color: cloudSubtle(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _weatherHero(BuildContext context, CloudFarmController c) {
    final w = c.weather;
    final loc = c.location;
    const white = Colors.white;
    final temp = w != null ? '${w.temp.round()}' : '${CloudSeed.weather.temp}';
    final desc = w != null ? w.desc : CloudSeed.weather.desc;
    final humidity = w != null ? w.humidity : CloudSeed.weather.humidity;
    final wind = w != null ? w.wind : CloudSeed.weather.wind;
    final windDir = w != null ? w.windDir : CloudSeed.weather.windDir;
    final rainProb = w != null ? w.rainProb : CloudSeed.weather.rainProb;
    final days =
        w?.forecast.take(4).toList() ?? const <CloudForecastDay>[];
    final offline = w?.offline ?? false;
    final locName = loc.name.isEmpty ? '未定位' : loc.name;
    final accuracy = loc.isSeed ? '示例位置' : cloudAccuracyText(loc.accuracy);
    final sourceLabel =
        w == null ? '示例天气' : (offline ? '离线缓存' : '中国天气网');
    final sourceLine = w == null
        ? (c.weatherError ?? '尚未获取真实天气 · 下拉刷新')
        : '中国天气网 · ${_hhmm(w.updatedAt)} 更新'
            '${offline ? ' · 当前离线，显示上次数据' : ''}';

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
              Icon(
                loc.isSeed ? Icons.gps_off : Icons.gps_fixed,
                size: 13,
                color: Colors.white70,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '$locName · $accuracy',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, color: Colors.white70),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  sourceLabel,
                  style: const TextStyle(fontSize: 9, color: Colors.white70),
                ),
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
                  Text(temp,
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
                    w != null ? desc : '$desc（示例数据）',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, color: white, height: 1.4),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(desc,
                      style: const TextStyle(
                          fontSize: 12, color: white, fontWeight: FontWeight.w600)),
                  Text('湿度 $humidity%',
                      style: const TextStyle(fontSize: 10.5, color: Colors.white70)),
                  Text('$windDir ${_windText(wind)}m/s',
                      style: const TextStyle(fontSize: 10.5, color: Colors.white70)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _wxMetric(Icons.water_drop_outlined, '空气湿度', '$humidity%'),
              _wxMetric(Icons.umbrella_outlined, '降水概率', '$rainProb%'),
              _wxMetric(Icons.air, '风速', '${_windText(wind)}m/s'),
            ],
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.18)),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                w == null ? Icons.cloud_off_outlined : Icons.public,
                size: 11,
                color: Colors.white70,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  sourceLine,
                  style: const TextStyle(fontSize: 9.5, color: Colors.white70),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (days.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Text(
                '暂无预报数据',
                style: TextStyle(
                    fontSize: 10.5,
                    color: Colors.white.withValues(alpha: 0.76)),
              ),
            )
          else
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
                          Text('${days[i].high}°',
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

  String _windText(double value) =>
      value == value.roundToDouble() ? '${value.round()}' : value.toStringAsFixed(1);

  String _hhmm(DateTime? t) {
    if (t == null) return '--:--';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
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
                  onTap: () => widget.onSwitchTab(2),
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

/// 定位面板：查看当前坐标、重新定位、手动修改位置
class _CloudLocationSheet extends ConsumerStatefulWidget {
  const _CloudLocationSheet();

  @override
  ConsumerState<_CloudLocationSheet> createState() =>
      _CloudLocationSheetState();
}

class _CloudLocationSheetState extends ConsumerState<_CloudLocationSheet> {
  final TextEditingController _lat = TextEditingController();
  final TextEditingController _lng = TextEditingController();
  final TextEditingController _name = TextEditingController();
  bool _manualOpen = false;

  @override
  void initState() {
    super.initState();
    final loc = ref.read(cloudFarmProvider).location;
    _lat.text = loc.lat.toStringAsFixed(6);
    _lng.text = loc.lng.toStringAsFixed(6);
    _name.text = loc.isSeed ? '' : loc.name;
  }

  @override
  void dispose() {
    _lat.dispose();
    _lng.dispose();
    _name.dispose();
    super.dispose();
  }

  double? get _latValue => double.tryParse(_lat.text.trim());

  double? get _lngValue => double.tryParse(_lng.text.trim());

  bool get _latValid {
    final v = _latValue;
    return v != null && v >= -90 && v <= 90;
  }

  bool get _lngValid {
    final v = _lngValue;
    return v != null && v >= -180 && v <= 180;
  }

  Future<void> _relocate() async {
    final c = ref.read(cloudFarmProvider);
    final result = await c.locate();
    if (!mounted) return;
    if (result.ok) {
      setState(() {
        _lat.text = c.location.lat.toStringAsFixed(6);
        _lng.text = c.location.lng.toStringAsFixed(6);
        if (!c.location.isSeed) _name.text = c.location.name;
      });
    }
  }

  void _saveManual() {
    final lat = _latValue;
    final lng = _lngValue;
    if (lat == null || lng == null || !_latValid || !_lngValid) return;
    ref.read(cloudFarmProvider).setManualLocation(
          lat: lat,
          lng: lng,
          name: _name.text,
        );
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(const SnackBar(content: Text('位置已更新')));
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(cloudFarmProvider);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('定位与位置',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
              _currentLocationCard(context, c),
              if (c.lastLocateError != null) ...[
                const SizedBox(height: 10),
                _errorTip(context, c.lastLocateError!),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: c.locating ? null : _relocate,
                  icon: c.locating
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.my_location, size: 17),
                  label: Text(c.locating ? '正在定位…' : '重新定位'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      setState(() => _manualOpen = !_manualOpen),
                  icon: Icon(
                    _manualOpen
                        ? Icons.expand_less
                        : Icons.edit_location_alt_outlined,
                    size: 17,
                  ),
                  label: const Text('手动修改位置'),
                ),
              ),
              if (_manualOpen) ...[
                const SizedBox(height: 12),
                _manualEditor(context),
              ],
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _currentLocationCard(BuildContext context, CloudFarmController c) {
    final loc = c.location;
    final primary = Theme.of(context).colorScheme.primary;
    final updated = loc.updatedAt == null
        ? ''
        : ' · 更新于 ${_timeText(loc.updatedAt!)}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cloudSoft(primary, context, light: 0.06, dark: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primary.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.location_on_outlined, size: 18, color: primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        loc.name.isEmpty ? '未定位' : loc.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 6),
                    CloudTag(cloudSourceLabel(loc.source), color: primary),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${loc.lat.toStringAsFixed(6)}, ${loc.lng.toStringAsFixed(6)}',
                  style: TextStyle(fontSize: 10.5, color: cloudSubtle(context)),
                ),
                const SizedBox(height: 2),
                Text(
                  '${loc.isSeed ? '示例位置' : cloudAccuracyText(loc.accuracy)}$updated',
                  style: TextStyle(fontSize: 10, color: cloudHint(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorTip(BuildContext context, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFD84343).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD84343).withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 15, color: Color(0xFFD84343)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  fontSize: 10.5, height: 1.4, color: Color(0xFFD84343)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _manualEditor(BuildContext context) {
    final valid = _latValid && _lngValid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _numberField(
                controller: _lat,
                label: '纬度',
                hint: '-90 ~ 90',
                valid: _latValid,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _numberField(
                controller: _lng,
                label: '经度',
                hint: '-180 ~ 180',
                valid: _lngValid,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _name,
          style: const TextStyle(fontSize: 12),
          decoration: const InputDecoration(
            labelText: '名称（可选）',
            hintText: '如：东坡油菜田',
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: valid ? _saveManual : null,
            child: const Text('确认修改位置'),
          ),
        ),
        if (!valid)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '请输入有效范围：纬度 -90~90，经度 -180~180',
              style: TextStyle(fontSize: 10, color: cloudHint(context)),
            ),
          ),
      ],
    );
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool valid,
  }) {
    final showError = controller.text.trim().isNotEmpty && !valid;
    return TextField(
      controller: controller,
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true, signed: true),
      style: const TextStyle(fontSize: 12),
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        errorText: showError ? '超出范围' : null,
        errorStyle: const TextStyle(fontSize: 9.5),
      ),
    );
  }

  String _timeText(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}
