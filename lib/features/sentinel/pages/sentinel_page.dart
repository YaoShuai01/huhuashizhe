import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../providers/sentinel_provider.dart';
import '../../../providers/weather_provider.dart';
import '../models/sentinel_models.dart';

/// 田哨中心（云端田哨 · 哨兵值守）。
///
/// 排版遵循项目惯例：AppBar 绿底白字（主题统一）、surface 卡片圆角 12、
/// 预警级别色块（紧急红 / 警告橙 / 提示蓝）。
///
/// 功能结构：
/// - 顶部"云田同步"卡：实地种植 ↔ 云种植游戏的同步状态总览；
/// - 哨兵预警区：寒潮/大风/降雨/打药提醒/病虫害风险，按级别着色，
///   每条预警给出可执行农事建议（该打什么药、怎么防寒）；
/// - 我的田块区：生长进度条 + 云游戏田块编号，演示实地与云端同步。
class SentinelPage extends ConsumerStatefulWidget {
  const SentinelPage({super.key});

  @override
  ConsumerState<SentinelPage> createState() => _SentinelPageState();
}

class _SentinelPageState extends ConsumerState<SentinelPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final service = ref.read(sentinelServiceProvider);
      service.loadData();
      // 天气哨：天气数据已就绪则立即评估一次
      service.evaluateWeather(ref.read(weatherProvider).valueOrNull);
    });
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(sentinelServiceProvider);
    final weather = ref.watch(weatherProvider).valueOrNull;
    if (weather != null) {
      // 天气哨：天气数据到达后帧外评估（build 内不能 notifyListeners）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(sentinelServiceProvider).evaluateWeather(weather);
      });
    }
    final alerts = service.alerts;
    final plantings = service.plantings;
    final unhandled = service.unhandledAlertCount;

    return Scaffold(
      appBar: AppBar(
        title: Text('田哨预警'),
        actions: [
          IconButton(
            icon: Icon(Icons.bolt),
            tooltip: '演示：寒潮来袭',
            onPressed: () {
              ref.read(sentinelServiceProvider).triggerDemoColdWave();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showRegisterSheet,
        icon: Icon(Icons.grass),
        label: Text('登记种植'),
      ),
      body: ListView(
        physics: AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 12, 16, 88),
        children: [
          _buildSyncCard(plantings.length, unhandled),
          SizedBox(height: 16),
          _buildSectionHeader('哨兵预警', unhandled > 0 ? '$unhandled 条待处理' : '全部已处理'),
          if (alerts.isEmpty)
            _buildEmptyAlerts()
          else
            for (final alert in alerts) ...[
              SizedBox(height: 8),
              _buildAlertCard(alert),
            ],
          SizedBox(height: 16),
          _buildSectionHeader('我的田块 · 云端同步', '${plantings.length} 块田'),
          if (plantings.isEmpty)
            _buildEmptyPlantings()
          else
            for (final planting in plantings) ...[
              SizedBox(height: 8),
              _buildPlantingCard(planting),
            ],
        ],
      ),
    );
  }

  Widget _buildSyncCard(int plotCount, int unhandled) {
    return GestureDetector(
      onTap: () => context.push('/sentinel/farm'),
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: Offset(0, 4),
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
                      Icon(Icons.cloud_sync, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text(
                        '云端田哨 · 值守中',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 6),
                  Text(
                    '$plotCount 块实地田已同步至云种植游戏',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  SizedBox(height: 2),
                  Text(
                    '天气哨 + 农事哨 24 小时自动值守',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.videogame_asset, color: Colors.white, size: 14),
                      SizedBox(width: 5),
                      Text(
                        '点按进入田哨农场 ›',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: unhandled > 0
                    ? Colors.red.shade600
                    : Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                unhandled > 0 ? '预警 $unhandled' : '平安',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String tail) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.palette.textPrimary,
            ),
          ),
          Text(
            tail,
            style: TextStyle(fontSize: 12, color: context.palette.textHint),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertCard(SentinelAlert alert) {
    final color = _severityColor(alert.severity);
    return Material(
      color: context.palette.surface,
      borderRadius: BorderRadius.circular(12),
      elevation: 1,
      child: Opacity(
        opacity: alert.handled ? 0.55 : 1,
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(_alertIcon(alert.type), color: color, size: 20),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      alert.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: alert.handled
                            ? context.palette.textSecondary
                            : context.palette.textPrimary,
                      ),
                    ),
                  ),
                  _buildSeverityChip(alert),
                ],
              ),
              SizedBox(height: 8),
              Text(
                alert.message,
                style: TextStyle(
                    fontSize: 13, color: context.palette.textSecondary),
              ),
              SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '哨兵建议',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      alert.recommendation,
                      style: TextStyle(
                          fontSize: 12, color: context.palette.textSecondary),
                    ),
                  ],
                ),
              ),
              if (!alert.handled)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // 打药提醒/病虫害风险可一键转预约飞防（专业飞手上门作业）
                    if (alert.type == SentinelAlertType.sprayReminder ||
                        alert.type == SentinelAlertType.pestRisk)
                      TextButton(
                        onPressed: () => _bookFlyingService(alert),
                        child: Text('预约飞防'),
                      ),
                    TextButton(
                      onPressed: () => ref
                          .read(sentinelServiceProvider)
                          .handleAlert(alert.id),
                      child: Text('知道了'),
                    ),
                  ],
                )
              else
                Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 14, color: AppColors.success),
                      SizedBox(width: 4),
                      Text(
                        '已处理',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.success),
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

  Widget _buildSeverityChip(SentinelAlert alert) {
    final color = _severityColor(alert.severity);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        alert.severity.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Color _severityColor(SentinelSeverity severity) {
    switch (severity) {
      case SentinelSeverity.urgent:
        return Color(0xFFC62828);
      case SentinelSeverity.warning:
        return AppColors.accent;
      case SentinelSeverity.info:
        return AppColors.info;
    }
  }

  IconData _alertIcon(SentinelAlertType type) {
    switch (type) {
      case SentinelAlertType.coldWave:
        return Icons.ac_unit;
      case SentinelAlertType.highWind:
        return Icons.air;
      case SentinelAlertType.heavyRain:
        return Icons.umbrella;
      case SentinelAlertType.sprayReminder:
        return Icons.science;
      case SentinelAlertType.pestRisk:
        return Icons.pest_control;
    }
  }

  Widget _buildPlantingCard(FieldPlanting planting) {
    final now = DateTime.now();
    final progress = planting.progressAt(now);
    final stage = planting.stageAt(now);
    final days = planting.daysElapsedAt(now);
    return Material(
      color: context.palette.surface,
      borderRadius: BorderRadius.circular(12),
      elevation: 1,
      child: Padding(
        padding: EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.agriculture,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${planting.crop.label} · ${planting.location}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: context.palette.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 2),
                      Text(
                        '${_formatArea(planting.areaMu)} 亩 · 已种植 $days 天 · 云游戏 ${planting.gamePlot} 号田',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.palette.textHint,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    stage.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.info,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: context.palette.surfaceVariant,
                      valueColor:
                          AlwaysStoppedAnimation(AppColors.primary),
                    ),
                  ),
                ),
                SizedBox(width: 10),
                Text(
                  '${(progress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.cloud_done_outlined,
                    size: 14, color: AppColors.info),
                SizedBox(width: 4),
                Text(
                  '生长进度已同步至云种植游戏',
                  style: TextStyle(fontSize: 11, color: context.palette.textHint),
                ),
                Spacer(),
                // 一键预约飞防：专业飞手上门作业（作物/亩数在飞防表单中填写）
                TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => context.push('/services/booking/farmer'),
                  child: Text(
                    '预约飞防',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 预警卡"预约飞防"：跳转预约飞防表单，并预填关联田块的作物/亩数/地点
  void _bookFlyingService(SentinelAlert alert) {
    FieldPlanting? planting;
    for (final p in ref.read(sentinelServiceProvider).plantings) {
      if (p.id == alert.fieldId) {
        planting = p;
        break;
      }
    }
    final params = <String, String>{};
    if (planting != null) {
      params['crop'] = planting.crop.label;
      params['area'] = _formatArea(planting.areaMu);
      params['location'] = planting.location;
    }
    final uri = Uri(
      path: '/services/booking/farmer',
      queryParameters: params.isEmpty ? null : params,
    );
    context.push(uri.toString());
  }

  String _formatArea(double v) =>
      v.truncateToDouble() == v ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  Widget _buildEmptyAlerts() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.palette.surfaceVariant),
      ),
      child: Column(
        children: [
          Icon(Icons.verified_user_outlined,
              size: 36, color: AppColors.success),
          SizedBox(height: 8),
          Text(
            '哨兵一切正常，暂无预警',
            style: TextStyle(fontSize: 13, color: context.palette.textHint),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyPlantings() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.palette.surfaceVariant),
      ),
      child: Column(
        children: [
          Icon(Icons.grass_outlined, size: 36, color: context.palette.textDisabled),
          SizedBox(height: 8),
          Text(
            '还没有登记实地种植',
            style: TextStyle(fontSize: 13, color: context.palette.textHint),
          ),
          SizedBox(height: 4),
          Text(
            '点击右下角按钮，登记后自动同步云种植游戏',
            style: TextStyle(fontSize: 12, color: context.palette.textDisabled),
          ),
        ],
      ),
    );
  }

  /// 登记实地种植（底部弹层）：作物 chips + 亩数 + 地块位置。
  void _showRegisterSheet() {
    SentinelCrop selected = SentinelCrop.cabbage;
    final areaCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                20 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.grass, color: AppColors.primary),
                        SizedBox(width: 8),
                        Text(
                          '登记实地种植',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: context.palette.textPrimary,
                          ),
                        ),
                        Spacer(),
                        IconButton(
                          icon: Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.of(sheetContext).pop(),
                        ),
                      ],
                    ),
                    Text(
                      '登记后自动同步至云种植游戏，田哨开始为这块田值守',
                      style: TextStyle(fontSize: 12, color: context.palette.textHint),
                    ),
                    SizedBox(height: 14),
                    Text('作物',
                        style: TextStyle(
                            fontSize: 13, color: context.palette.textSecondary)),
                    SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final crop in SentinelCrop.values)
                          ChoiceChip(
                            label: Text(crop.label),
                            selected: selected == crop,
                            labelStyle: TextStyle(
                              fontSize: 13,
                              color: selected == crop
                                  ? AppColors.textOnPrimary
                                  : context.palette.textSecondary,
                            ),
                            selectedColor: AppColors.primary,
                            onSelected: (_) => setSheetState(() => selected = crop),
                          ),
                      ],
                    ),
                    SizedBox(height: 14),
                    TextFormField(
                      controller: areaCtrl,
                      keyboardType:
                          TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: '种植亩数',
                        hintText: '例如 5 或 12.5',
                        suffixText: '亩',
                      ),
                      validator: (v) {
                        final value = double.tryParse(v?.trim() ?? '');
                        if (value == null || value <= 0) {
                          return '请输入有效的亩数';
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: 12),
                    TextFormField(
                      controller: locationCtrl,
                      decoration: InputDecoration(
                        labelText: '地块位置',
                        hintText: '例如 朋兴乡丹阳村 2 号地',
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? '请填写地块位置' : null,
                    ),
                    SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          if (!(formKey.currentState?.validate() ?? false)) {
                            return;
                          }
                          final service =
                              ref.read(sentinelServiceProvider);
                          final planting = service.registerPlanting(
                            crop: selected,
                            areaMu: double.parse(areaCtrl.text.trim()),
                            location: locationCtrl.text.trim(),
                          );
                          Navigator.of(sheetContext).pop();
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  '已登记并同步云种植游戏 ${planting.gamePlot} 号田，田哨开始值守'),
                              backgroundColor: AppColors.primary,
                            ),
                          );
                        },
                        child: Text('登记并同步云种植'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
