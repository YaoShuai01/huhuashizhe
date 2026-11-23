import 'dart:math';
import 'package:flutter/material.dart';

/// 无人机虚拟摇杆组件
/// 支持双轴操控，返回X(-100~100)和Y(-100~100)
/// stickyY=true时Y轴松手保持位置（油门），false时双轴回中
class DroneJoystick extends StatefulWidget {
  final double size;
  final Color? color;
  final bool stickyY; // 油门轴松手保持位置
  final void Function(double x, double y)? onChanged;
  final void Function()? onReleased;

  const DroneJoystick({
    super.key,
    this.size = 140,
    this.color,
    this.stickyY = false,
    this.onChanged,
    this.onReleased,
  });

  @override
  State<DroneJoystick> createState() => _DroneJoystickState();
}

class _DroneJoystickState extends State<DroneJoystick> {
  double _x = 0;
  double _y = 0;
  // 手指按下点作为本次拖动的相对原点：按偏了也不会让摇杆瞬间跳过去
  Offset? _origin;

  double get _travel => widget.size / 2 - widget.size * 0.18;

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Colors.blue;
    final thumbRadius = widget.size * 0.18;
    final outerColor = Colors.grey[850]!;
    final borderColor = Colors.grey[700]!;

    // 用 GestureDetector 包裹整个摇杆区域，确保坐标相对于摇杆中心
    return SizedBox(
      width: widget.size,
      height: widget.size + 30,
      child: GestureDetector(
        onPanStart: _onStart,
        onPanUpdate: _onUpdate,
        onPanEnd: (_) => _onRelease(),
        onPanCancel: _onRelease,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 外圈
            Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: outerColor,
                border: Border.all(color: borderColor, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.15),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
            // 十字线
            CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _CrosshairPainter(color: Colors.grey[700]!),
            ),
            // 中心点
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey[600]),
            ),
            // 摇杆拇指（只负责渲染，不处理触摸）
            Positioned(
              left: widget.size / 2 - thumbRadius + _x * (widget.size / 2 - thumbRadius),
              top: widget.size / 2 - thumbRadius + _y * (widget.size / 2 - thumbRadius),
              child: Container(
                width: thumbRadius * 2,
                height: thumbRadius * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [color.withValues(alpha: 0.95), color.withValues(alpha: 0.5)],
                  ),
                  boxShadow: [
                    BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 10, spreadRadius: 1),
                  ],
                ),
              ),
            ),
            // 中心十字虚线
            Positioned(
              left: 0,
              right: 0,
              top: widget.size / 2 - 0.5,
              child: Container(height: 1, color: Colors.grey[700]!.withValues(alpha: 0.5)),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              left: widget.size / 2 - 0.5,
              child: Container(width: 1, color: Colors.grey[700]!.withValues(alpha: 0.5)),
            ),
          ],
        ),
      ),
    );
  }

  void _onStart(DragStartDetails d) {
    final center = Offset(widget.size / 2, widget.size / 2);
    // 只接受从摇杆圆圈内开始的触摸，圈外按下不响应
    if ((d.localPosition - center).distance > widget.size / 2) return;
    _origin = d.localPosition;
  }

  void _onUpdate(DragUpdateDetails d) {
    final origin = _origin;
    if (origin == null) return;

    double dx = (d.localPosition.dx - origin.dx) / _travel;
    double dy = (d.localPosition.dy - origin.dy) / _travel;

    // 圆形限幅，斜向不会比正向更灵敏
    final dist = sqrt(dx * dx + dy * dy);
    if (dist > 1.0) {
      dx /= dist;
      dy /= dist;
    }

    final sx = _expo(dx);
    final sy = _expo(dy);

    setState(() {
      _x = sx;
      _y = sy;
    });
    widget.onChanged?.call(_x * 100, -_y * 100);
  }

  /// 中心柔和、满杆仍能到位的指数曲线，避免轻碰一下就是大杆量
  static double _expo(double v) => 0.62 * v + 0.38 * v * v * v;

  void _onRelease() {
    _origin = null;
    if (widget.stickyY) {
      // 油门轴保持位置，仅横滚轴回中
      setState(() { _x = 0; });
      widget.onChanged?.call(0, -_y * 100);
    } else {
      // 双轴回中
      setState(() { _x = 0; _y = 0; });
      widget.onChanged?.call(0, 0);
    }
    widget.onReleased?.call();
  }
}

class _CrosshairPainter extends CustomPainter {
  final Color color;
  _CrosshairPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    canvas.drawLine(Offset(center.dx - radius, center.dy), Offset(center.dx + radius, center.dy), paint);
    canvas.drawLine(Offset(center.dx, center.dy - radius), Offset(center.dx, center.dy + radius), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}