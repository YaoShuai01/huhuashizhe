import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
            tooltip: '田块地图',
            onPressed: () => widget.onSwitchTab(1),
            icon: const Icon(Icons.map_outlined),
          ),
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
                  const Spacer(),
                  Text('详细步骤',
                      style: TextStyle(fontSize: 11, color: primary)),
                  const SizedBox(width: 2),
                  Icon(
                    _guideOpen ? Icons.expand_less : Icons.chevron_right,
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
    final temp = w?.temp ?? CloudSeed.weather.temp.toDouble();
    final desc = w?.desc ?? CloudSeed.weather.desc;
    final humidity = w?.humidity ?? CloudSeed.weather.humidity;
    final wind = w?.wind ?? CloudSeed.weather.wind;
    final windDir = w?.windDir ?? CloudSeed.weather.windDir;
    final rainProb = w?.rainProb ?? CloudSeed.weather.rainProb;
    // 与网页一致：土壤温度按气温推算，并明确标注“推算”
    final soilTemp =
        w == null ? CloudSeed.weather.soilTemp : _round1(w.temp - 3.5);
    final days =
        w?.forecast.take(4).toList() ?? const <CloudForecastDay>[];
    final offline = w?.offline ?? false;
    final locName = loc.name.isEmpty ? '未定位' : loc.name;
    final badgeLabel = loc.fromGps
        ? 'GPS 高精度定位'
        : loc.isManual
            ? '手动定位'
            : '示例位置';
    final updateSource = w == null
        ? '示例天气'
        : (offline
            ? '离线缓存'
            : (w.source.isEmpty ? '中国天气网' : w.source));
    final updateNote = StringBuffer(updateSource);
    if (w?.updatedAt != null) {
      updateNote.write(' · ${_hhmm(w!.updatedAt)} 更新');
    }
    updateNote.write(days.length > 1
        ? ' · 实况 + 未来 ${days.length - 1} 天预报'
        : ' · 今日实况，未来为预测');

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2E7D32), Color(0xFF3F8F43), Color(0xFF63AD63)],
          stops: [0, 0.48, 1],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2E7D32).withValues(alpha: 0.24),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -52,
            top: -84,
            child: Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.09),
              ),
            ),
          ),
          Positioned(
            right: 34,
            bottom: -70,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.09),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _openLocationSheet(context),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Icon(
                            loc.isSeed ? Icons.gps_off : Icons.gps_fixed,
                            size: 14,
                            color: Colors.white.withValues(alpha: 0.82),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              '$locName · ${cloudAccuracyText(loc.accuracy)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.white.withValues(alpha: 0.82),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              badgeLabel,
                              style: const TextStyle(
                                  fontSize: 9, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${temp.round()}',
                                style: const TextStyle(
                                  fontSize: 52,
                                  height: 1,
                                  letterSpacing: -2,
                                  fontWeight: FontWeight.w300,
                                  color: white,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 6, left: 3),
                                child: Text(
                                  '℃',
                                  style: TextStyle(
                                    fontSize: 17,
                                    color:
                                        Colors.white.withValues(alpha: 0.8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '$desc · 土壤温度 ${_decimalText(soilTemp)}℃（推算）',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: Colors.white.withValues(alpha: 0.82),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          desc,
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                            color: white,
                          ),
                        ),
                        Text(
                          '湿度 $humidity%',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.6,
                            color: Colors.white.withValues(alpha: 0.88),
                          ),
                        ),
                        Text(
                          '$windDir ${_windText(wind)}m/s',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.6,
                            color: Colors.white.withValues(alpha: 0.88),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _wxMetricBox(
                        Icons.water_drop_outlined, '空气湿度', '$humidity%'),
                    const SizedBox(width: 6),
                    _wxMetricBox(
                        Icons.umbrella_outlined, '降水概率', '$rainProb%'),
                    const SizedBox(width: 6),
                    _wxMetricBox(Icons.air, '风速', '${_windText(wind)}m/s'),
                  ],
                ),
                const SizedBox(height: 12),
                if (days.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '暂无预报数据',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.white.withValues(alpha: 0.76),
                      ),
                    ),
                  )
                else
                  Row(
                    children: [
                      for (var i = 0; i < days.length; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        Expanded(child: _wxDayCard(days[i], today: i == 0)),
                      ],
                    ],
                  ),
                const SizedBox(height: 8),
                Text(
                  updateNote.toString(),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 8.5,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _wxMetricBox(IconData icon, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: Colors.white.withValues(alpha: 0.9)),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.2,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wxDayCard(CloudForecastDay day, {required bool today}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: today ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        children: [
          Text(
            day.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9.5,
              color: Colors.white.withValues(alpha: 0.78),
            ),
          ),
          const SizedBox(height: 2),
          Icon(_weatherIcon(day.icon), size: 17, color: Colors.white),
          const SizedBox(height: 2),
          Text(
            '${day.high}°',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          Text(
            '${day.rain}%',
            style: const TextStyle(fontSize: 8.5, color: Color(0xFFBFE4FF)),
          ),
        ],
      ),
    );
  }

  double _round1(double value) => (value * 10).round() / 10;

  String _decimalText(double value) => value == value.roundToDouble()
      ? '${value.round()}'
      : value.toStringAsFixed(1);

  String _windText(double value) =>
      value == value.roundToDouble() ? '${value.round()}' : value.toStringAsFixed(1);

  String _hhmm(DateTime? t) {
    if (t == null) return '--:--';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
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
              CloudTag('区域气候参考值', color: cloudSubtle(context)),
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
  final TextEditingController _cityQuery = TextEditingController();
  bool _manualOpen = false;
  bool _cityOpen = false;
  bool _cityBusy = false;
  bool _autoBusy = false;
  String? _cityError;
  Future<List<MapEntry<String, String>>>? _citiesFuture;

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
    _cityQuery.dispose();
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

  Future<List<MapEntry<String, String>>> _loadCities() async {
    final raw = await rootBundle.loadString('assets/city_codes.json');
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return const [];
    return decoded.entries
        .map((e) => MapEntry(e.key, e.value.toString()))
        .toList();
  }

  void _toggleCityList() {
    setState(() {
      _cityOpen = !_cityOpen;
      if (_cityOpen) _citiesFuture ??= _loadCities();
    });
  }

  List<MapEntry<String, String>> _filterCities(
    List<MapEntry<String, String>> all,
  ) {
    final query = _cityQuery.text.trim().toLowerCase();
    final matched = query.isEmpty
        ? all
        : all.where((e) => e.key.toLowerCase().contains(query));
    return matched.take(80).toList();
  }

  Future<void> _selectCity(String name, String code) async {
    if (_cityBusy) return;
    setState(() {
      _cityBusy = true;
      _cityError = null;
    });
    final c = ref.read(cloudFarmProvider);
    final ok = await c.setWeatherCity(name, code);
    if (!mounted) return;
    final error = c.weatherError;
    setState(() {
      _cityBusy = false;
      if (!ok) _cityError = error ?? '切换城市失败，请检查网络';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '已切换为 $name 的天气' : (error ?? '切换城市失败，请检查网络')),
      ),
    );
  }

  Future<void> _restoreAuto() async {
    if (_autoBusy) return;
    setState(() {
      _autoBusy = true;
      _cityError = null;
    });
    final c = ref.read(cloudFarmProvider);
    await c.restoreAutoWeather();
    if (!mounted) return;
    final error = c.weatherError;
    setState(() => _autoBusy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? '已恢复为按定位获取天气'),
      ),
    );
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
              const SizedBox(height: 12),
              _weatherCitySection(context, c),
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

  Widget _weatherCitySection(BuildContext context, CloudFarmController c) {
    final primary = Theme.of(context).colorScheme.primary;
    final cityName = c.weatherCityName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (cityName != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: cloudSoft(primary, context, light: 0.06, dark: 0.14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: primary.withValues(alpha: 0.22)),
            ),
            child: Row(
              children: [
                Icon(Icons.location_city, size: 16, color: primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '天气城市：$cityName'
                    '${c.weatherCityCode == null ? '' : '（${c.weatherCityCode}）'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: _autoBusy ? null : _restoreAuto,
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    _autoBusy ? '切换中…' : '恢复自动（按定位）',
                    style: const TextStyle(fontSize: 10.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          '选择城市仅影响天气与气候展示；地图定位仍以 GPS 或手动经纬度为准',
          style: TextStyle(fontSize: 10, height: 1.45, color: cloudHint(context)),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _toggleCityList,
            icon: Icon(
              _cityOpen ? Icons.expand_less : Icons.travel_explore,
              size: 17,
            ),
            label: Text(_cityOpen ? '收起城市列表' : '手动选择城市'),
          ),
        ),
        if (_cityOpen) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _cityQuery,
            style: const TextStyle(fontSize: 12),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: '搜索城市名，如：北京、海淀',
              prefixIcon: Icon(Icons.search, size: 18),
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          if (_cityBusy) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 2),
          ],
          const SizedBox(height: 8),
          _cityList(context),
          if (_cityError != null) ...[
            const SizedBox(height: 8),
            _errorTip(context, _cityError!),
          ],
        ],
      ],
    );
  }

  Widget _cityList(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final selectedName = ref.watch(cloudFarmProvider).weatherCityName;
    return Container(
      height: 240,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
        ),
      ),
      child: FutureBuilder<List<MapEntry<String, String>>>(
        future: _citiesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '城市列表加载失败，请稍后重试',
                  style: TextStyle(fontSize: 11, color: cloudHint(context)),
                ),
              ),
            );
          }
          final cities = _filterCities(snapshot.data ?? const []);
          if (cities.isEmpty) {
            return Center(
              child: Text(
                '未找到匹配的城市',
                style: TextStyle(fontSize: 11, color: cloudHint(context)),
              ),
            );
          }
          return ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: cities.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
            ),
            itemBuilder: (context, index) {
              final city = cities[index];
              final selected = city.key == selectedName;
              return ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                enabled: !_cityBusy,
                title: Text(city.key, style: const TextStyle(fontSize: 12)),
                subtitle: Text(
                  city.value,
                  style: TextStyle(fontSize: 10, color: cloudHint(context)),
                ),
                trailing: selected
                    ? Icon(Icons.check, size: 16, color: primary)
                    : null,
                onTap: () => _selectCity(city.key, city.value),
              );
            },
          );
        },
      ),
    );
  }
}
