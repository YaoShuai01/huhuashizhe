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
        onPanStart: (d) => _updatePosition(d.localPosition),
        onPanUpdate: (d) => _updatePosition(d.localPosition),
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

  void _updatePosition(Offset local) {
    final center = Offset(widget.size / 2, widget.size / 2);
    final dx = local.dx - center.dx;
    final dy = local.dy - center.dy;
    final maxRadius = widget.size / 2 - widget.size * 0.18;

    final distSq = dx * dx + dy * dy;
    double nx, ny;
    if (distSq > maxRadius * maxRadius) {
      final dist = sqrt(distSq);
      nx = dx / dist;
      ny = dy / dist;
    } else {
      nx = dx / maxRadius;
      ny = dy / maxRadius;
    }

    setState(() {
      _x = nx.clamp(-1.0, 1.0);
      _y = ny.clamp(-1.0, 1.0);
    });
    widget.onChanged?.call(_x * 100, -_y * 100);
  }

  void _onRelease() {
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