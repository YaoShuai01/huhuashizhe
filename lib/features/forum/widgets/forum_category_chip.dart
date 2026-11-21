import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/forum_models.dart';

/// 分区入口按钮（圆形图标 + 名称）
class ForumCategoryChip extends StatelessWidget {
  const ForumCategoryChip({
    super.key,
    required this.category,
    required this.selected,
    required this.onTap,
    this.size = 52,
  });

  final ForumCategory category;
  final bool selected;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: category.name,
      child: InkWell(
        borderRadius: BorderRadius.circular(size),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary
                      : AppColors.primaryLight.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.28),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  category.icon,
                  size: size * 0.46,
                  color:
 selected ? AppColors.textOnPrimary : AppColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: size + 16),
                child: Text(
                  category.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
 selected ? FontWeight.w600 : FontWeight.w400,
                    color:
 selected ? AppColors.primary : context.palette.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
