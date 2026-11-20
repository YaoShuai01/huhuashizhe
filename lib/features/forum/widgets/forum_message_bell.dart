import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// 论坛右上角消息入口：彩色圆底 + 醒目铃铛 + 未读数角标
class ForumMessageBell extends StatelessWidget {
  const ForumMessageBell({
    super.key,
    required this.unreadCount,
    required this.onTap,
  });

  final int unreadCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasUnread = unreadCount > 0;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Semantics(
        button: true,
        label: hasUnread ? '消息提醒，$unreadCount 条未读' : '消息提醒',
        child: Material(
          color: AppColors.textOnPrimary.withValues(alpha: 0.18),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    hasUnread
                        ? Icons.notifications_active
                        : Icons.notifications_none,
                    size: 24,
                    color: AppColors.textOnPrimary,
                  ),
                  if (hasUnread)
                    Positioned(
                      top: -3,
                      right: -4,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 18),
                        height: 18,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: AppColors.error,
                          borderRadius: BorderRadius.all(Radius.circular(9)),
                        ),
                        child: Text(
                          unreadCount > 99 ? '99+' : '$unreadCount',
                          style: const TextStyle(
                            fontSize: 11,
                            height: 1,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textOnPrimary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
