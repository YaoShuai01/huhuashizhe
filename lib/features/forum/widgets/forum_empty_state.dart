import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// 空状态占位（版块无帖、我的帖子为空、分区无版块等）
class ForumEmptyState extends StatelessWidget {
  const ForumEmptyState({
    super.key,
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 64, color: context.palette.textDisabled),
                    const SizedBox(height: 12),
                    Text(
                      text,
                      textAlign: TextAlign.center,
                      style:  TextStyle(
                        fontSize: 14,
                        color: context.palette.textHint,
                      ),
                    ),
                    if (actionLabel != null && onAction != null) ...[
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: onAction,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: Text(actionLabel!),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(140, 42),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
