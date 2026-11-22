import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../data/booking_role.dart';

/// 在农户 / 飞手页面右上角触发身份转换
Future<void> showBookingRoleSwitch(
  BuildContext context, {
  required String currentRole,
}) async {
  final target = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              '转换身份',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(
              Icons.agriculture_outlined,
              color: AppColors.primary,
            ),
            title: const Text(
              '我是农户',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            subtitle: const Text('预约飞手上门喷洒农药'),
            trailing: currentRole == bookingRoleFarmer
                ? const Icon(Icons.check_circle, color: AppColors.primary)
                : null,
            onTap: () => Navigator.pop(sheetContext, bookingRoleFarmer),
          ),
          ListTile(
            leading: const Icon(Icons.flight_takeoff, color: AppColors.accent),
            title: const Text(
              '我是飞手',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            subtitle: const Text('查看附近订单，接单上门作业'),
            trailing: currentRole == bookingRolePilot
                ? const Icon(Icons.check_circle, color: AppColors.primary)
                : null,
            onTap: () => Navigator.pop(sheetContext, bookingRolePilot),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  if (target == null || target == currentRole || !context.mounted) return;
  saveBookingRole(target);
  context.pushReplacement(bookingRolePath(target));
}
