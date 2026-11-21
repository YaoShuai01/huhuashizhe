import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/accessibility/elder_care_reader.dart';
import '../../../core/theme/app_theme.dart';

/// 预约入口：先选择身份，再进入农户预约或飞手工作台
class BookingRolePage extends StatelessWidget {
  const BookingRolePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('预约飞防')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 560;
          final header = Text(
            '请选择你的身份',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: context.palette.textPrimary,
            ),
          );

          final farmerCard = _roleCard(
            context,
            icon: Icons.agriculture_outlined,
            title: '我是农户',
            desc: '预约飞手上门\n喷洒农药',
            color: AppColors.primary,
            onTap: () => context.push('/services/booking/farmer'),
          );
          final pilotCard = _roleCard(
            context,
            icon: Icons.flight_takeoff,
            title: '我是飞手',
            desc: '查看附近订单\n接单上门作业',
            color: AppColors.accent,
            onTap: () => context.push('/services/booking/pilot'),
          );

          final cards = Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: farmerCard),
              const SizedBox(width: 12),
              Expanded(child: pilotCard),
            ],
          );

          if (compact) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              children: [
                header,
                const SizedBox(height: 64),
                SizedBox(height: 260, child: cards),
              ],
            );
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: 64),
                SizedBox(
                  height: (constraints.maxHeight * 0.48).clamp(280.0, 400.0),
                  child: cards,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _roleCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String desc,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ElderCareBlock(
      readText: '$title。${desc.replaceAll('\n', '，')}',
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(icon, size: 36, color: color),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: context.palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  desc,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: context.palette.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '点击进入',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 16, color: color),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
