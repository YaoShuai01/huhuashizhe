import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/schedule_models.dart';

/// 月历轮协视图（查看/编辑共用）
class ScheduleCalendar extends StatelessWidget {
  final DateTime month;
  final Map<String, String> assignments;
  final List<ScheduleMember> members;
  final String? myMemberId;
  final ValueChanged<DateTime>? onPreviousMonth;
  final ValueChanged<DateTime>? onNextMonth;
  final VoidCallback? onToday;
  final ValueChanged<DateTime>? onDayTap;
  final String? selectedDateKey;
  final bool editable;
  final bool allowPastTap;

  const ScheduleCalendar({
    super.key,
    required this.month,
    required this.assignments,
    required this.members,
    this.myMemberId,
    this.onPreviousMonth,
    this.onNextMonth,
    this.onToday,
    this.onDayTap,
    this.selectedDateKey,
    this.editable = false,
    this.allowPastTap = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = ScheduleDate.today();
    final cells = ScheduleDate.monthGrid(month);
    final memberMap = {for (final m in members) m.id: m};

    return Card(
      margin: EdgeInsets.zero,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onPreviousMonth == null
                      ? null
                      : () => onPreviousMonth!(
                            DateTime(month.year, month.month - 1, 1),
                          ),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    ScheduleDate.monthLabel(month),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (onToday != null)
                  TextButton(
                    onPressed: onToday,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text('今天'),
                  ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onNextMonth == null
                      ? null
                      : () => onNextMonth!(
                            DateTime(month.year, month.month + 1, 1),
                          ),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                for (final label in const ['一', '二', '三', '四', '五', '六', '日'])
                  Expanded(
                    child: Center(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurface.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cells.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                mainAxisExtent: 62,
              ),
              itemBuilder: (context, index) {
                final date = cells[index];
                if (date == null) return const SizedBox.shrink();
                return _buildDayCell(
                  context,
                  date,
                  memberMap,
                  today,
                );
              },
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legend(context, scheme.primary, '我的协管'),
                const SizedBox(width: 12),
                _legend(
                  context,
                  scheme.primary.withValues(alpha: 0.12),
                  '其他成员',
                  borderColor: scheme.primary.withValues(alpha: 0.25),
                ),
                const SizedBox(width: 12),
                _legend(
                  context,
                  scheme.surfaceContainerHighest,
                  '未轮协',
                  borderColor: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayCell(
    BuildContext context,
    DateTime date,
    Map<String, ScheduleMember> memberMap,
    DateTime today,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final key = ScheduleDate.key(date);
    final memberId = assignments[key];
    final member = memberId == null ? null : memberMap[memberId];
    final isMine = memberId != null && memberId == myMemberId;
    final isToday = ScheduleDate.isSameDay(date, today);
    final isPast = date.isBefore(today);
    final isSelected = selectedDateKey == key;
    final hasMember = member != null;

    Color background;
    Color dayColor;
    Color nameColor;
    if (isPast) {
      // 已过日期统一浅灰；自己的历史协管记录灰度稍深一点，便于区分。
      if (isMine) {
        background = scheme.onSurface.withValues(alpha: 0.11);
        dayColor = scheme.onSurface.withValues(alpha: 0.58);
        nameColor = scheme.onSurface.withValues(alpha: 0.52);
      } else if (hasMember) {
        background = scheme.onSurface.withValues(alpha: 0.065);
        dayColor = scheme.onSurface.withValues(alpha: 0.42);
        nameColor = scheme.onSurface.withValues(alpha: 0.38);
      } else {
        background = scheme.surfaceContainerHighest.withValues(alpha: 0.42);
        dayColor = scheme.onSurface.withValues(alpha: 0.28);
        nameColor = scheme.onSurface.withValues(alpha: 0.26);
      }
    } else if (isMine) {
      background = scheme.primary;
      dayColor = scheme.onPrimary;
      nameColor = scheme.onPrimary.withValues(alpha: 0.9);
    } else if (hasMember) {
      background = scheme.primary.withValues(alpha: 0.12);
      dayColor = scheme.onSurface.withValues(alpha: 0.9);
      nameColor = scheme.onSurface.withValues(alpha: 0.7);
    } else {
      background = scheme.surfaceContainerHighest.withValues(alpha: 0.7);
      dayColor = scheme.onSurface.withValues(alpha: 0.6);
      nameColor = scheme.onSurface.withValues(alpha: 0.3);
    }

    Border? border;
    if (isSelected) {
      border = Border.all(color: AppColors.accent, width: 2);
    } else if (isToday) {
      border = Border.all(color: scheme.primary, width: 1.4);
    }

    final canTap = onDayTap != null && (allowPastTap || !isPast);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: canTap ? () => onDayTap!(date) : null,
      child: Container(
        padding: const EdgeInsets.fromLTRB(3, 3, 3, 3),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
          border: border,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${date.day}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                    color: dayColor,
                  ),
                ),
                if (isMine)
                  Text(
                    '我',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: nameColor,
                    ),
                  )
                else if (isToday)
                  Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: dayColor,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              hasMember ? member.name : (editable && !isPast ? '＋' : '—'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                height: 1.1,
                fontWeight: hasMember ? FontWeight.w600 : FontWeight.w400,
                color: nameColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend(BuildContext context, Color color, String label, {Color? borderColor}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: borderColor == null ? null : Border.all(color: borderColor),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style:  TextStyle(fontSize: 10, color: context.palette.textHint),
        ),
      ],
    );
  }
}
