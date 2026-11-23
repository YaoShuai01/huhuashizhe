import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// 发帖时的版块选择器，以 #标签 形式展示
class ForumSectionPicker extends StatelessWidget {
  const ForumSectionPicker({
    super.key,
    required this.sections,
    required this.value,
    required this.onChanged,
    this.label = '发布到',
  });

  final List<String> sections;
  final String? value;
  final ValueChanged<String> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final hasSections = sections.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: context.palette.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        if (!hasSections)
          Text(
            '暂无可用标签',
            style: TextStyle(fontSize: 13, color: context.palette.textHint),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final section in sections)
                ChoiceChip(
                  label: Text('#$section'),
                  selected: section == value,
                  showCheckmark: false,
                  onSelected: (_) => onChanged(section),
                  backgroundColor: context.palette.surface,
                  selectedColor: AppColors.primaryLight.withValues(alpha: 0.18),
                  labelStyle: TextStyle(
                    fontSize: 13,
                    color:
                        section == value
                            ? AppColors.primary
                            : context.palette.textSecondary,
                    fontWeight:
                        section == value ? FontWeight.w600 : FontWeight.w400,
                  ),
                  side: BorderSide(
                    color:
                        section == value
                            ? AppColors.primary.withValues(alpha: 0.4)
                            : Colors.transparent,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
