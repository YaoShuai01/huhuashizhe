import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/weather_provider.dart';
import '../../../providers/device_provider.dart';
import '../../../services/bluetooth_service.dart';
import '../../../services/weather_service.dart';
import '../../mission/pages/map_select_page.dart';
import '../../mine/widgets/device_scan_page.dart';

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
            onPressed: () {},
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(weatherProvider.notifier).refresh();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
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
              _buildRecentMissions(),
              const SizedBox(height: 16),
              _buildStatsOverview(),
            ],
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

  Widget _buildDeviceCard(BuildContext context, DeviceStatus? status) {
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
                  isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                  color: isConnected ? AppColors.primary : AppColors.textHint,
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
                          isConnected ? '已连接: ${status!.deviceName}' : '未连接设备',
                          style: TextStyle(
                            color: isConnected ? AppColors.primary : AppColors.textHint,
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
                      isConnected ? '电量 ${status!.batteryLevel}% · 信号 ${status.signalStrength}%' : '请点击连接设备',
                      style: TextStyle(
                        color: isConnected ? AppColors.textSecondary : AppColors.textDisabled,
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
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.8,
      children: [
        _buildActionCard(
          icon: Icons.flight_takeoff,
          title: '创建飞行任务',
          subtitle: '新建植保作业任务',
          color: AppColors.primary,
          onTap: () {
            context.push('/mission/map');
          },
        ),
        _buildActionCard(
          icon: Icons.auto_awesome,
          title: 'AI建议',
          subtitle: '智能诊断与用药推荐',
          color: AppColors.accent,
          onTap: () {},
        ),
        _buildActionCard(
          icon: Icons.speed,
          title: '快速预设',
          subtitle: '从历史预设一键启动',
          color: const Color(0xFF1976D2),
          onTap: () {},
        ),
        _buildActionCard(
          icon: Icons.history,
          title: '作业记录',
          subtitle: '查看历史作业详情',
          color: const Color(0xFF7B1FA2),
          onTap: () {},
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.surface,
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
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 11, color: AppColors.textHint),
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

  Widget _buildRecentMissions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Text('最近作业', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
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
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.surfaceVariant),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.inbox_outlined, size: 40, color: AppColors.textDisabled),
                    SizedBox(height: 8),
                    Text('暂无作业记录', style: TextStyle(fontSize: 13, color: AppColors.textHint)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsOverview() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
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
            children: const [
              Text('作业统计', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              Icon(Icons.chevron_right, color: AppColors.textHint),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildStatItem(icon: Icons.map_outlined, label: '总作业面积', value: '0 亩'),
              _buildDivider(),
              _buildStatItem(icon: Icons.timer_outlined, label: '总飞行时长', value: '0 小时'),
              _buildDivider(),
              _buildStatItem(icon: Icons.task_alt_outlined, label: '任务次数', value: '0 次'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({required IconData icon, required String label, required String value}) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: AppColors.primary, size: 24),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(height: 40, width: 1, color: AppColors.surfaceVariant);
  }
}