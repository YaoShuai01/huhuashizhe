import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 卫星信息（方位角 0=正上方，顺时针；仰角 0~1 映射到半径）
class SatelliteInfo {
  const SatelliteInfo({
    required this.azimuth,
    required this.elevation,
    required this.prn,
    this.locked = false,
    this.strong = false,
  });

  final double azimuth;
  final double elevation;
  final int prn;
  final bool locked;
  final bool strong;
}

/// 深空霓虹风仪表盘
class SpeedGaugePainter extends CustomPainter {
  SpeedGaugePainter({
    required this.speed,
    required this.timeText,
    required this.speedText,
    required this.gpsDots,
  });

  final double speed;
  final String timeText;
  final String speedText;
  final int gpsDots;

  static const double _startDeg = 140;
  static const double _sweepDeg = 255;
  static const double _maxSpeed = 65;

  static const Color _cyan = Color(0xFF4DF0FF);
  static const Color _ice = Color(0xFFD9FBFF);
  static const Color _magenta = Color(0xFFFF4FD8);

  double _angleFor(double value) =>
      (_startDeg + _sweepDeg * (value / _maxSpeed).clamp(0.0, 1.0)) *
      math.pi /
      180;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = s * 0.44;
    final center = Offset(cx, cy);

    // 外圈细线 + 柔光
    canvas.drawCircle(
      center,
      r + s * 0.030,
      Paint()
        ..color = _cyan.withValues(alpha: 0.10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = _cyan.withValues(alpha: 0.16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // 轨道底弧
    final trackRect = Rect.fromCircle(center: center, radius: r - s * 0.020);
    canvas.drawArc(
      trackRect,
      _angleFor(0),
      _angleFor(65) - _angleFor(0),
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.07)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    // 已行驶进度弧（霓虹光晕）
    if (speed > 0) {
      final sweep = _angleFor(speed) - _angleFor(0);
      canvas.drawArc(
        trackRect,
        _angleFor(0),
        sweep,
        false,
        Paint()
          ..color = _cyan.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawArc(
        trackRect,
        _angleFor(0),
        sweep,
        false,
        Paint()
          ..shader = const SweepGradient(
            colors: [Color(0xFF2FA8FF), Color(0xFF8B7BFF)],
          ).createShader(trackRect)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round,
      );
    } else {
      // 静止时起点光点
      final startPoint = center +
          Offset(math.cos(_angleFor(0)), math.sin(_angleFor(0))) *
              (r - s * 0.020);
      canvas.drawCircle(
        startPoint,
        s * 0.010,
        Paint()
          ..color = _cyan.withValues(alpha: 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawCircle(startPoint, s * 0.004, Paint()..color = _ice);
    }

    // 极细刻度
    for (var v = 0; v <= 65; v++) {
      final major = v % 5 == 0;
      final angle = _angleFor(v.toDouble());
      final outer = r - s * 0.012;
      final len = major ? s * 0.040 : s * 0.018;
      final dir = Offset(math.cos(angle), math.sin(angle));
      final color = v >= 60
          ? _magenta.withValues(alpha: 0.85)
          : Colors.white.withValues(alpha: major ? 0.55 : 0.22);
      canvas.drawLine(
        center + dir * outer,
        center + dir * (outer - len),
        Paint()
          ..color = color
          ..strokeWidth = major ? 1.4 : 0.8,
      );
    }

    // 数字（等宽科幻感）
    final numberStyle = TextStyle(
      color: _ice.withValues(alpha: 0.72),
      fontSize: s * 0.050,
      fontWeight: FontWeight.w300,
      fontFamily: 'monospace',
      letterSpacing: 1.2,
      height: 1,
    );
    for (var v = 5; v <= 60; v += 5) {
      final angle = _angleFor(v.toDouble());
      final labelRadius = r - s * 0.110;
      _drawCenteredText(
        canvas,
        v.toString().padLeft(2, '0'),
        center + Offset(math.cos(angle), math.sin(angle)) * labelRadius,
        numberStyle,
      );
    }

    for (final entry in {0.0: '00', 65.0: '65'}.entries) {
      final angle = _angleFor(entry.key);
      final labelRadius = r - s * 0.080;
      final pos =
          center + Offset(math.cos(angle), math.sin(angle)) * labelRadius;
      _drawGlowText(
        canvas,
        entry.value,
        pos,
        TextStyle(
          color: _cyan,
          fontSize: s * 0.040,
          fontWeight: FontWeight.w400,
          fontFamily: 'monospace',
          letterSpacing: 1,
          height: 1,
        ),
        glowColor: _cyan,
      );
    }

    // 极细霓虹指针（悬浮于外圈，不穿过中央数字）
    final needleAngle = _angleFor(speed);
    final needleDir = Offset(math.cos(needleAngle), math.sin(needleAngle));
    final tail = center + needleDir * (r * 0.54);
    final tip = center + needleDir * (r * 0.90);
    canvas.drawLine(
      tail,
      tip,
      Paint()
        ..color = _cyan.withValues(alpha: 0.55)
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawLine(
      tail,
      tip,
      Paint()
        ..color = const Color(0xFFEAFEFF)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      tip,
      s * 0.010,
      Paint()
        ..color = _cyan.withValues(alpha: 0.70)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(tip, s * 0.004, Paint()..color = _ice);
    canvas.drawCircle(
      tail,
      s * 0.007,
      Paint()
        ..color = _cyan.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // GPS 信号点
    final dotY = cy - r * 0.43;
    final gap = s * 0.024;
    final startX = cx - gap * 2.5;
    for (var i = 0; i < 6; i++) {
      final active = i < gpsDots;
      final p = Offset(startX + gap * i, dotY);
      if (active) {
        canvas.drawCircle(
          p,
          s * 0.009,
          Paint()
            ..color = _cyan.withValues(alpha: 0.45)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }
      canvas.drawCircle(
        p,
        s * 0.0055,
        Paint()
          ..color = active
              ? _ice
              : Colors.white.withValues(alpha: 0.16),
      );
    }

    // 时间
    _drawCenteredText(
      canvas,
      timeText,
      Offset(cx, cy - r * 0.28),
      TextStyle(
        color: const Color(0xFF9FD8E8).withValues(alpha: 0.80),
        fontSize: s * 0.034,
        fontWeight: FontWeight.w300,
        fontFamily: 'monospace',
        letterSpacing: 0.4,
        height: 1,
      ),
    );

    // 中央发光速度数字（无底框）
    final parts = speedText.split(' ');
    final valueText = parts.first;
    final unitText = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    final valueStyle = TextStyle(
      fontSize: s * 0.150,
      fontWeight: FontWeight.w300,
      fontFamily: 'monospace',
      height: 1,
      letterSpacing: 2,
    );
    final unitStyle = TextStyle(
      color: _cyan.withValues(alpha: 0.9),
      fontSize: s * 0.045,
      fontWeight: FontWeight.w400,
      fontFamily: 'monospace',
      letterSpacing: 3,
      height: 1,
    );
    final valueTp = TextPainter(
      text: TextSpan(text: valueText, style: valueStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final unitTp = TextPainter(
      text: TextSpan(text: unitText, style: unitStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final gapX = s * 0.022;
    final totalW = valueTp.width + gapX + unitTp.width;
    final baselineY = cy + r * 0.28;
    final leftX = cx - totalW / 2;

    // 光晕
    _paintText(
      canvas,
      valueText,
      valueStyle.copyWith(
        foreground: Paint()
          ..color = _cyan.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      ),
      Offset(leftX, baselineY - valueTp.height / 2),
    );
    // 渐变描字
    final valueRect = Rect.fromLTWH(
        leftX, baselineY - valueTp.height / 2, valueTp.width, valueTp.height);
    _paintText(
      canvas,
      valueText,
      valueStyle.copyWith(
        foreground: Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF2FEFF), Color(0xFF6FE9FF), Color(0xFF2FA8FF)],
          ).createShader(valueRect),
      ),
      valueRect.topLeft,
    );
    unitTp.paint(
      canvas,
      Offset(leftX + valueTp.width + gapX,
          baselineY - unitTp.height / 2 + s * 0.030),
    );
  }

  void _paintText(
      Canvas canvas, String text, TextStyle style, Offset offset) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  void _drawCenteredText(
      Canvas canvas, String text, Offset center, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _drawGlowText(
      Canvas canvas, String text, Offset center, TextStyle style,
      {required Color glowColor}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final offset = center - Offset(tp.width / 2, tp.height / 2);
    final glow = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(
          color: glowColor.withValues(alpha: 0.55),
          shadows: [
            Shadow(color: glowColor.withValues(alpha: 0.9), blurRadius: 12),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    glow.paint(canvas, offset);
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant SpeedGaugePainter oldDelegate) =>
      oldDelegate.speed != speed ||
      oldDelegate.timeText != timeText ||
      oldDelegate.speedText != speedText ||
      oldDelegate.gpsDots != gpsDots;
}

/// 罗盘式卫星星空图（品牌绿 / 琥珀配色）
class SkyPlotPainter extends CustomPainter {
  SkyPlotPainter({required this.satellites, this.sweep = 0});

  final List<SatelliteInfo> satellites;

  /// 雷达扫描角（弧度，0 指向正北）
  final double sweep;

  static const Color _green = Color(0xFF66BB6A);
  static const Color _amber = Color(0xFFFF8F00);
  static const Color _muted = Color(0xFF8A9690);

  /// 罗盘方位：0=正北，顺时针
  static const Map<int, String> _compass = {
    0: '北',
    90: '东',
    180: '南',
    270: '西',
  };

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);
    final r = s / 2 - s * 0.095;

    // 罗盘底：淡绿径向光
    final discRect = Rect.fromCircle(center: center, radius: r);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = const RadialGradient(
          colors: [
            Color(0x332E7D32),
            Color(0x1A1B5E20),
            Color(0x0D0F1A14),
            Color(0x00000000),
          ],
          stops: [0.0, 0.45, 0.8, 1.0],
        ).createShader(discRect),
    );

    // 雷达扫描扇区
    final sweepCanvas = sweep - math.pi / 2;
    canvas.save();
    canvas.clipPath(Path()..addOval(discRect));
    canvas.drawArc(
      discRect,
      sweepCanvas - 0.65,
      0.65,
      true,
      Paint()
        ..shader = SweepGradient(
          startAngle: sweepCanvas - 0.65,
          endAngle: sweepCanvas,
          colors: [const Color(0x0066BB6A), _green.withValues(alpha: 0.17)],
          tileMode: TileMode.clamp,
        ).createShader(discRect),
    );
    canvas.restore();
    final sweepDir = Offset(math.cos(sweepCanvas), math.sin(sweepCanvas));
    canvas.drawLine(
      center,
      center + sweepDir * r,
      Paint()
        ..color = _green.withValues(alpha: 0.55)
        ..strokeWidth = 1.2
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // 同心圆
    for (final f in const [0.33, 0.66, 1.0]) {
      canvas.drawCircle(
        center,
        r * f,
        Paint()
          ..color = _green.withValues(alpha: f == 1.0 ? 0.38 : 0.14)
          ..style = PaintingStyle.stroke
          ..strokeWidth = f == 1.0 ? 1.4 : 1,
      );
      if (f == 1.0) {
        canvas.drawCircle(
          center,
          r * f,
          Paint()
            ..color = _green.withValues(alpha: 0.10)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
      }
    }

    // 外侧虚线环
    final dashPath = Path()
      ..addOval(Rect.fromCircle(center: center, radius: r + s * 0.028));
    final dashPaint = Paint()
      ..color = _green.withValues(alpha: 0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in dashPath.computeMetrics()) {
      final period = s * 0.018;
      final phase = (sweep * 8) % period;
      var d = -phase;
      while (d < metric.length) {
        final a = math.max(0.0, d);
        final b = math.min(metric.length, d + s * 0.009);
        if (b > a) {
          canvas.drawPath(metric.extractPath(a, b), dashPaint);
        }
        d += period;
      }
    }

    // 细密刻度（每 2°）
    for (var deg = 0; deg < 360; deg += 2) {
      if (deg % 10 == 0) continue;
      final rad = deg * math.pi / 180;
      final dir = Offset(math.sin(rad), -math.cos(rad));
      canvas.drawLine(
        center + dir * (r + s * 0.003),
        center + dir * (r + s * 0.007),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.10)
          ..strokeWidth = 0.6,
      );
    }

    // 十字准线
    for (final a in const [0.0, 45.0, 90.0, 135.0]) {
      final rad = a * math.pi / 180;
      final dir = Offset(math.sin(rad), -math.cos(rad));
      canvas.drawLine(
        center - dir * r,
        center + dir * r,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.06)
          ..strokeWidth = 1,
      );
    }

    // 方位刻度 + 东南西北
    for (var deg = 0; deg < 360; deg += 10) {
      final rad = deg * math.pi / 180;
      final dir = Offset(math.sin(rad), -math.cos(rad));
      final major = deg % 30 == 0;
      canvas.drawLine(
        center + dir * (r + s * 0.004),
        center + dir * (r + s * (major ? 0.018 : 0.011)),
        Paint()
          ..color = Colors.white.withValues(alpha: major ? 0.40 : 0.16)
          ..strokeWidth = major ? 1.2 : 0.7,
      );
      if (!major) continue;
      // 东南西北由页面用 Text 组件绘制，保证中文字体渲染
      if (_compass.containsKey(deg)) continue;
      _drawCenteredText(
        canvas,
        deg.toString().padLeft(3, '0'),
        center + dir * (r + s * 0.046),
        TextStyle(
          color: Colors.white.withValues(alpha: 0.38),
          fontSize: s * 0.026,
          fontWeight: FontWeight.w400,
          fontFamily: 'monospace',
          letterSpacing: 0.5,
          height: 1,
        ),
      );
    }

    // 中心能量高光
    canvas.drawCircle(
      center,
      r * 0.20,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.55),
            _green.withValues(alpha: 0.28),
            Colors.transparent,
          ],
          stops: const [0.0, 0.35, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: r * 0.20)),
    );

    // 卫星粒子
    for (final sat in satellites) {
      final rad = sat.azimuth * math.pi / 180;
      final dist = r * sat.elevation.clamp(0.0, 1.0);
      final pos = center + Offset(math.sin(rad), -math.cos(rad)) * dist;
      final color = sat.locked
          ? _green
          : (sat.strong ? _amber : _muted);
      final strength = sat.locked || sat.strong ? 1.0 : 0.65;
      final dotR = s * 0.023;

      // 外发光
      canvas.drawCircle(
        pos,
        dotR * 1.9,
        Paint()
          ..color = color.withValues(alpha: 0.16 * strength)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
      // 核心
      canvas.drawCircle(
        pos,
        dotR,
        Paint()..color = color.withValues(alpha: 0.14 * strength + 0.06),
      );
      canvas.drawCircle(
        pos,
        dotR,
        Paint()
          ..color = color.withValues(alpha: 0.55 * strength + 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      // 编号
      _drawCenteredText(
        canvas,
        sat.prn.toString().padLeft(2, '0'),
        pos,
        TextStyle(
          color: Colors.white.withValues(alpha: 0.92),
          fontSize: 9,
          fontWeight: FontWeight.w500,
          fontFamily: 'monospace',
          height: 1,
        ),
      );
    }

    // 方位高亮弧（北斗 / GPS 方向）
    for (final az in const [318.0, 88.0]) {
      final start = (az - 6 - 90) * math.pi / 180;
      final arcRect = Rect.fromCircle(center: center, radius: r + s * 0.010);
      canvas.drawArc(
        arcRect,
        start,
        12 * math.pi / 180,
        false,
        Paint()
          ..color = _green.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawArc(
        arcRect,
        start,
        12 * math.pi / 180,
        false,
        Paint()
          ..color = _green.withValues(alpha: 0.95)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _drawCenteredText(
      Canvas canvas, String text, Offset center, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant SkyPlotPainter oldDelegate) =>
      oldDelegate.satellites != satellites || oldDelegate.sweep != sweep;
}
