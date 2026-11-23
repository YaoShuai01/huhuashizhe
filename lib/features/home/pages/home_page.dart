import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/layout/tablet_layout.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/weather_provider.dart';
import '../../../providers/device_provider.dart';
import '../../../services/wifi_service.dart';
import '../../../services/weather_service.dart';
import '../../cloud_farming/services/cloud_farm_controller.dart';
import '../../mission/pages/map_select_page.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weatherAsync = ref.watch(weatherProvider);
    final deviceStatusAsync = ref.watch(deviceStatusProvider);

    final weather = weatherAsync.valueOrNull;
    final deviceStatus = deviceStatusAsync.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('护花使者'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.push('/notification'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(weatherProvider.notifier).refresh();
          await ref.read(wifiServiceProvider).refreshStatus();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: AdaptiveContent(
            maxWidth: 1100,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildWeatherBar(weather),
                const SizedBox(height: 16),
                _buildDeviceCard(context, deviceStatus),
                const SizedBox(height: 16),
                _buildQuickActions(context),
                const SizedBox(height: 16),
                const _CloudFarmEntryCard(),
                const SizedBox(height: 16),
                _buildRecentMissions(context),
                const SizedBox(height: 16),
                _buildStatsOverview(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWeatherBar(WeatherData? weather) {
    final temp = weather?.temperature;
    final location = weather?.locationName ?? '定位中...';
    final desc = weather?.weatherDescription ?? '获取天气中';
    final windSpeed = weather?.windSpeed;
    final humidity = weather?.humidity;
    final isWindWarning = weather?.isWindWarning ?? false;
    final showTemp = weather != null && weather.weatherDescription != '无法获取天气';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.white70, size: 16),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        location,
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      showTemp ? (temp?.toStringAsFixed(0) ?? '--') : '--',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    const Text(
                      '°C',
                      style: TextStyle(color: Colors.white70, fontSize: 20),
                    ),
                    const SizedBox(width: 8),
                    if (showTemp)
                      Text(
                        weather?.weatherIcon ?? '',
                        style: const TextStyle(fontSize: 28),
                      ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          desc,
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          showTemp ? '风速 ${windSpeed != null ? '${windSpeed.toStringAsFixed(1)} m/s' : '-- m/s'}' : '',
                          style: TextStyle(
                            color: isWindWarning ? AppColors.accent : Colors.white70,
                            fontSize: 12,
                            fontWeight: isWindWarning ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        if (showTemp)
                          Text(
                            '湿度 ${humidity != null ? '${humidity.toStringAsFixed(0)}%' : '--%'}',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(BuildContext context, WifiStatus? status) {
    final isConnected = status?.isConnected ?? false;

    return Card(
      child: InkWell(
        onTap: () {
          context.push('/mine/device');
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isConnected
                      ? AppColors.primaryLight.withValues(alpha: 0.15)
                      : AppColors.primaryLight.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isConnected ? Icons.wifi : Icons.wifi_off,
                  color: isConnected ? AppColors.primary : context.palette.textHint,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          isConnected ? '已连接: ${status!.displayName}' : '未连接设备',
                          style: TextStyle(
                            color: isConnected ? AppColors.primary : context.palette.textHint,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (isConnected) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isConnected ? 'WiFi 热点 · 信号 ${status!.signalDisplay}' : '请点击连接无人机 WiFi',
                      style: TextStyle(
                        color: isConnected ? context.palette.textSecondary : context.palette.textDisabled,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  context.push('/mine/device');
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  minimumSize: Size.zero,
                ),
                child: const Text('连接设备'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return GridView(
      gridDelegate: adaptiveGridDelegate(context, childAspectRatio: 1.8),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _buildActionCard(
          context,
          icon: Icons.flight_takeoff,
          title: '创建飞行任务',
          subtitle: '油菜植保作业规划',
          color: AppColors.primary,
          onTap: () {
            context.push('/mission/map');
          },
        ),
        _buildActionCard(
          context,
          icon: Icons.auto_awesome,
          title: 'AI助手',
          subtitle: '油菜病虫害智能诊断',
          color: AppColors.accent,
          onTap: () => context.push('/ai-chat'),
        ),
        _buildActionCard(
          context,
          icon: Icons.speed,
          title: '快速预设',
          subtitle: '油菜一键适配参数',
          color: const Color(0xFF1976D2),
          onTap: () => context.push('/presets'),
        ),
        _buildActionCard(
          context,
          icon: Icons.history,
          title: '作业记录',
          subtitle: '油菜植保历史作业',
          color: const Color(0xFF7B1FA2),
          onTap: () => context.push('/mission/history'),
        ),
        _buildActionCard(
          context,
          icon: Icons.gamepad,
          title: '快速遥控',
          subtitle: 'WiFi虚拟遥控器操控',
          color: const Color(0xFFE65100),
          onTap: () => context.push('/remote-control'),
        ),
        _buildActionCard(
          context,
          icon: Icons.center_focus_strong,
          title: '模型测试',
          subtitle: '摄像头实时作物问题识别',
          color: const Color(0xFF00897B),
          onTap: () => context.push('/model-test'),
        ),
        _buildActionCard(
          context,
          icon: Icons.add_alert,
          title: '田哨预警',
          subtitle: '云端田哨 · 寒潮打药提醒',
          color: const Color(0xFFC62828),
          onTap: () => context.push('/sentinel'),
        ),
        _buildActionCard(
          context,
          icon: Icons.agriculture,
          title: '田哨农场',
          subtitle: '云端种田小游戏 · 一键直达',
          color: const Color(0xFF2E7D32),
          onTap: () => context.push('/sentinel/farm'),
        ),
      ],
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: context.palette.surface,
      borderRadius: BorderRadius.circular(12),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style:  TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.palette.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style:  TextStyle(fontSize: 11, color: context.palette.textHint),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentMissions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
         Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Text('最近作业', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: context.palette.textPrimary)),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 120,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            children: [
              Container(
                width: 160,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.palette.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.palette.surfaceVariant),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children:  [
                    Icon(Icons.inbox_outlined, size: 40, color: context.palette.textDisabled),
                    SizedBox(height: 8),
                    Text('暂无作业记录', style: TextStyle(fontSize: 13, color: context.palette.textHint)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsOverview(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children:  [
              Text('作业统计', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: context.palette.textPrimary)),
              Icon(Icons.chevron_right, color: context.palette.textHint),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildStatItem(context, icon: Icons.map_outlined, label: '总作业面积', value: '0 亩'),
              _buildDivider(context),
              _buildStatItem(context, icon: Icons.timer_outlined, label: '总飞行时长', value: '0 小时'),
              _buildDivider(context),
              _buildStatItem(context, icon: Icons.task_alt_outlined, label: '任务次数', value: '0 次'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(BuildContext context, {required IconData icon, required String label, required String value}) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: AppColors.primary, size: 24),
          const SizedBox(height: 8),
          Text(value, style:  TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.palette.textPrimary)),
          const SizedBox(height: 4),
          Text(label, style:  TextStyle(fontSize: 12, color: context.palette.textHint)),
        ],
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Container(height: 40, width: 1, color: context.palette.surfaceVariant);
  }
}

/// 首页云种植入口（跟随系统深浅色）
class _CloudFarmEntryCard extends ConsumerWidget {
  const _CloudFarmEntryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(cloudFarmProvider);
    final alertCount = controller.alerts.length;
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF1F3A24), const Color(0xFF2B5133)]
                : [const Color(0xFFE8F5E9), const Color(0xFFD7EEDB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: primary.withValues(alpha: isDark ? 0.35 : 0.22)),
        ),
        child: InkWell(
          onTap: () => context.push('/cloud-farm'),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: isDark ? 0.28 : 0.15),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(Icons.eco, color: primary, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '云种植',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: primary.withValues(
                                  alpha: isDark ? 0.22 : 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'AI 农事',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: primary,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Icon(Icons.chevron_right, color: primary, size: 20),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${controller.plots.length} 块田 · '
                        '${controller.totalArea.toStringAsFixed(1)} 亩 · '
                        '$alertCount 项待办',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.62),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: [
                          _miniTag(context, 'GPS 圈地'),
                          _miniTag(context, '1:1 建模'),
                          _miniTag(context, '墒情推断'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniTag(BuildContext context, String text) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          color: onSurface.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}
