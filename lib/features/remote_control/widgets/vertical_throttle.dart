import 'package:flutter/material.dart';

/// 竖向油门力度滑杆：0~100%，拖动/点击直接设定，不自动回中。
class VerticalThrottle extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final Color color;

  const VerticalThrottle({
    super.key,
    required this.value,
    required this.onChanged,
    this.color = Colors.orange,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '油门 $value%',
          style: const TextStyle(fontSize: 11, color: Colors.white70),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final h = constraints.maxHeight;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _setFromDy(d.localPosition.dy, h),
                onVerticalDragStart: (d) => _setFromDy(d.localPosition.dy, h),
                onVerticalDragUpdate: (d) => _setFromDy(d.localPosition.dy, h),
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    // 轨道
                    Container(
                      width: 18,
                      height: h,
                      decoration: BoxDecoration(
                        color: Colors.grey[850],
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: Colors.grey[700]!, width: 1),
                      ),
                    ),
                    // 已推力度
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: value / 100.0,
                        child: Container(
                          width: 18,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(9),
                          ),
                        ),
                      ),
                    ),
                    // 滑块
                    Align(
                      alignment: Alignment(0, 1.0 - 2.0 * value / 100.0),
                      child: Container(
                        width: 44,
                        height: 20,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8),
                          ],
                        ),
                        child: Icon(
                          Icons.drag_handle,
                          size: 16,
                          color: Colors.black.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        const Text('0', style: TextStyle(fontSize: 10, color: Colors.white38)),
      ],
    );
  }

  void _setFromDy(double dy, double height) {
    if (height <= 0) return;
    final v = ((1.0 - dy / height) * 100.0).round().clamp(0, 100);
    if (v != value) onChanged(v);
  }
}
