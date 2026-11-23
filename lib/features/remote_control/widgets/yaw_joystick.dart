import 'package:flutter/material.dart';

/// 只左右打杆的偏航摇杆，松手自动回中。
class YawJoystick extends StatefulWidget {
  final double width;
  final double height;
  final ValueChanged<int> onChanged;
  final VoidCallback? onReleased;

  const YawJoystick({
    super.key,
    this.width = 150,
    this.height = 64,
    required this.onChanged,
    this.onReleased,
  });

  @override
  State<YawJoystick> createState() => _YawJoystickState();
}

class _YawJoystickState extends State<YawJoystick> {
  double _x = 0;
  // 手指按下点作为相对原点，按偏了也不会让滑块瞬间跳过去
  double? _originDx;

  @override
  Widget build(BuildContext context) {
    final thumb = widget.height * 0.42;
    final travel = widget.width / 2 - thumb / 2;

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (d) => _originDx = d.localPosition.dx,
        onHorizontalDragUpdate: (d) => _update(d.localPosition.dx),
        onHorizontalDragEnd: (_) => _release(),
        onHorizontalDragCancel: _release,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: widget.width,
              height: widget.height,
              decoration: BoxDecoration(
                color: Colors.grey[850],
                borderRadius: BorderRadius.circular(widget.height / 2),
                border: Border.all(color: Colors.grey[700]!, width: 2),
              ),
            ),
            // 中线
            Container(width: 1, height: widget.height * 0.5, color: Colors.grey[600]),
            // 滑块
            Positioned(
              left: widget.width / 2 - thumb / 2 + _x * travel,
              child: Container(
                width: thumb,
                height: thumb,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Colors.cyan.withValues(alpha: 0.95), Colors.cyan.withValues(alpha: 0.5)],
                  ),
                  boxShadow: [
                    BoxShadow(color: Colors.cyan.withValues(alpha: 0.45), blurRadius: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _update(double localDx) {
    final origin = _originDx;
    if (origin == null) return;
    final travel = widget.width / 2 - (widget.height * 0.42) / 2;
    var x = ((localDx - origin) / travel).clamp(-1.0, 1.0);
    // 指数曲线：小杆量更柔和，满杆仍到 100
    x = 0.62 * x + 0.38 * x * x * x;
    setState(() => _x = x);
    widget.onChanged((x * 100).round());
  }

  void _release() {
    _originDx = null;
    setState(() => _x = 0);
    widget.onChanged(0);
    widget.onReleased?.call();
  }
}
