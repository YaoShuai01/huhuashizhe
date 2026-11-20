import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// 发帖时的版块选择器
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
          style:  TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: context.palette.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: context.palette.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: hasSections ? value : null,
              isExpanded: true,
              borderRadius: BorderRadius.circular(12),
              hint: const Text('暂无可用版块'),
              items: [
                for (final section in sections)
                  DropdownMenuItem(value: section, child: Text(section)),
              ],
              onChanged: hasSections
                  ? (v) {
                      if (v != null) onChanged(v);
                    }
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}
