import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/cloud_models.dart';
import '../services/cloud_engine.dart';

/// 主题适配的通用颜色
Color cloudCardColor(BuildContext context) {
  final theme = Theme.of(context);
  return theme.cardTheme.color ?? theme.colorScheme.surface;
}

Color cloudSoft(Color base, BuildContext context, {double light = 0.12, double dark = 0.22}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return base.withValues(alpha: isDark ? dark : light);
}

Color cloudSubtle(BuildContext context) =>
    Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.64);

Color cloudHint(BuildContext context) =>
    Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45);

String cloudAccuracyText(double? accuracy) {
  if (accuracy == null || accuracy <= 0) return '精度未知';
  final value =
      accuracy >= 10 ? accuracy.round().toString() : accuracy.toStringAsFixed(1);
  return '定位精度 ±${value}m';
}

String cloudSourceLabel(String source) {
  switch (source) {
    case 'gps':
      return 'GPS 定位';
    case 'manual':
      return '手动位置';
    default:
      return '示例位置';
  }
}

class CloudCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final BoxBorder? border;
  final double radius;

  const CloudCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color,
    this.border,
    this.radius = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? cloudCardColor(context),
        borderRadius: BorderRadius.circular(radius),
        border: border ?? Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.4)),
      ),
      child: child,
    );
  }
}

class CloudSectionHead extends StatelessWidget {
  final String title;
  final String? sub;
  final Widget? action;

  const CloudSectionHead({super.key, required this.title, this.sub, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
      child: Row(
        children: [
          Text(title,
              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
          if (sub != null) ...[
            const SizedBox(width: 8),
            Text(sub!, style: TextStyle(fontSize: 11, color: cloudHint(context))),
          ],
          const Spacer(),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class CloudTag extends StatelessWidget {
  final String text;
  final Color? color;
  final IconData? icon;

  const CloudTag(this.text, {super.key, this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: cloudSoft(c, context),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: c),
            const SizedBox(width: 3),
          ],
          Text(
            text,
            style: TextStyle(fontSize: 10.5, color: c, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class CloudPillButton extends StatelessWidget {
  final String text;
  final bool active;
  final VoidCallback? onTap;
  final IconData? icon;

  const CloudPillButton({
    super.key,
    required this.text,
    required this.active,
    this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Material(
      color: active ? primary : cloudSoft(primary, context, light: 0.08, dark: 0.14),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: active ? Colors.white : primary),
                const SizedBox(width: 4),
              ],
              Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CloudLinkButton extends StatelessWidget {
  final String text;
  final IconData? icon;
  final VoidCallback onTap;

  const CloudLinkButton(this.text, {super.key, this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: c),
              const SizedBox(width: 3),
            ],
            Text(text,
                style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// 圆形进度环
class CloudRing extends StatelessWidget {
  final double pct;
  final double size;
  final double stroke;

  const CloudRing({super.key, required this.pct, this.size = 48, this.stroke = 4.5});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final track = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.10);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(
              pct: pct.clamp(0, 100),
              stroke: stroke,
              track: track,
              color: primary,
            ),
          ),
          Text(
            '${pct.round()}%',
            style: TextStyle(
              fontSize: size * 0.25,
              fontWeight: FontWeight.w700,
              color: primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double pct;
  final double stroke;
  final Color track;
  final Color color;

  _RingPainter({
    required this.pct,
    required this.stroke,
    required this.track,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: [color.withValues(alpha: 0.65), color],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * pct / 100,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.pct != pct || old.color != color || old.track != track || old.stroke != stroke;
}

/// 田块缩略图（渐变 + 垄行纹理）
class PlotThumb extends StatelessWidget {
  final String? cropId;
  final double width;
  final double height;
  final double radius;

  const PlotThumb({
    super.key,
    required this.cropId,
    this.width = 56,
    this.height = 56,
    this.radius = 12,
  });

  @override
  Widget build(BuildContext context) {
    final base = cropId == null ? const Color(0xFF9E9E9E) : cropColor(cropId);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          colors: [base.withValues(alpha: 0.28), base.withValues(alpha: 0.55)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _FieldPatternPainter(base)),
          ),
          Center(
            child: Icon(cropGlyph(cropId), size: height * 0.42, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _FieldPatternPainter extends CustomPainter {
  final Color color;

  _FieldPatternPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 1; i < 5; i++) {
      final y = size.height * i / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    final p2 = Paint()
      ..color = Colors.black.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final x = size.width * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p2);
    }
  }

  @override
  bool shouldRepaint(covariant _FieldPatternPainter old) => old.color != color;
}

/// 田块卡片
class CloudPlotCard extends StatelessWidget {
  final CloudPlot plot;
  final GrowthInfo? growth;
  final MoistureInfo moisture;
  final VoidCallback onTap;

  const CloudPlotCard({
    super.key,
    required this.plot,
    required this.growth,
    required this.moisture,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final crop = CloudSeed.cropOf(plot.cropId);
    final g = growth;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: cloudCardColor(context),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                PlotThumb(cropId: plot.cropId, width: 54, height: 54),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              plot.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (g != null)
                            CloudTag('${g.stage.name}期', color: const Color(0xFFF59100))
                          else
                            CloudTag('待种植', color: cloudHint(context)),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        crop != null ? '${crop.name} · ${crop.variety}' : '选择作物后开始云种植',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: cloudSubtle(context)),
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: [
                          CloudTag('墒情 ${moisture.value}%',
                              color: Theme.of(context).colorScheme.primary, icon: Icons.water_drop_outlined),
                          CloudTag('1:1 建模', color: cloudSubtle(context), icon: Icons.straighten),
                          if (g != null)
                            CloudTag('已同步',
                                color: const Color(0xFF2E7D32), icon: Icons.sync),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  children: [
                    CloudRing(pct: g?.pct ?? 0, size: 46, stroke: 4),
                    const SizedBox(height: 3),
                    Text(
                      g != null ? '${g.daysLeft}天' : '去种植',
                      style: TextStyle(fontSize: 9.5, color: cloudHint(context)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 农事提醒卡片
class CloudAlertCard extends StatelessWidget {
  final CloudAlert alert;
  final String plotName;
  final VoidCallback onDone;
  final VoidCallback onSnooze;

  const CloudAlertCard({
    super.key,
    required this.alert,
    required this.plotName,
    required this.onDone,
    required this.onSnooze,
  });

  @override
  Widget build(BuildContext context) {
    final high = alert.urgency == CloudUrgency.high;
    final tagColor = high
        ? const Color(0xFFD84343)
        : alert.urgency == CloudUrgency.low
            ? cloudHint(context)
            : const Color(0xFFB96B00);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: cloudCardColor(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: high
                ? const Color(0xFFD84343).withValues(alpha: 0.45)
                : Theme.of(context).dividerColor.withValues(alpha: 0.4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: cloudSoft(alert.color, context),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(alert.icon, size: 18, color: alert.color),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alert.title,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(alert.subtitle,
                          style: TextStyle(fontSize: 10.5, color: cloudHint(context))),
                    ],
                  ),
                ),
                CloudTag(alert.urgencyLabel, color: tagColor),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              alert.reason,
              style: TextStyle(fontSize: 11, height: 1.5, color: cloudSubtle(context)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.schedule, size: 12, color: cloudHint(context)),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(alert.window,
                      style: TextStyle(fontSize: 10.5, color: cloudHint(context))),
                ),
                Icon(Icons.eco_outlined, size: 12, color: cloudHint(context)),
                const SizedBox(width: 3),
                Text(plotName,
                    style: TextStyle(fontSize: 10.5, color: cloudHint(context))),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onSnooze,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    foregroundColor: cloudSubtle(context),
                  ),
                  child: const Text('稍后', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: onDone,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  child: Text(alert.actionText),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 作物动态场景（替代原型 SVG 动画）
class CropScene extends StatefulWidget {
  final int stageIdx;
  final double height;

  const CropScene({super.key, required this.stageIdx, this.height = 184});

  @override
  State<CropScene> createState() => _CropSceneState();
}

class _CropSceneState extends State<CropScene> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _CropScenePainter(
            stageIdx: widget.stageIdx,
            sway: _controller.value,
          ),
        ),
      ),
    );
  }
}

class _CropScenePainter extends CustomPainter {
  final int stageIdx;
  final double sway;

  _CropScenePainter({required this.stageIdx, required this.sway});

  @override
  void paint(Canvas canvas, Size size) {
    final warm = stageIdx >= 7;
    final skyRect = Rect.fromLTWH(0, 0, size.width, size.height * 0.78);
    canvas.drawRect(
      skyRect,
      Paint()
        ..shader = LinearGradient(
          colors: warm
              ? [const Color(0xFFF6E5C1), const Color(0xFFFBF1DE)]
              : [const Color(0xFFD5ECF8), const Color(0xFFEEF8F6)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(skyRect),
    );

    // 太阳
    final sun = Offset(size.width * 0.83, size.height * 0.16);
    canvas.drawCircle(sun, size.height * 0.135, Paint()..color = const Color(0xFFFFF8D8));
    canvas.drawCircle(sun, size.height * 0.09, Paint()..color = const Color(0xFFFFFDF0));

    // 云
    final cloudPaint = Paint()..color = Colors.white.withValues(alpha: 0.52);
    void cloud(double cx, double cy, double rx) {
      canvas.drawOval(
          Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: rx * 0.62), cloudPaint);
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(cx + rx * 0.55, cy - rx * 0.08), width: rx * 1.2, height: rx * 0.5),
          cloudPaint);
    }

    cloud(size.width * 0.24, size.height * 0.17, size.width * 0.07);
    cloud(size.width * 0.66, size.height * 0.28, size.width * 0.05);

    // 远山
    final hillPath = Path()
      ..moveTo(0, size.height * 0.73)
      ..quadraticBezierTo(size.width * 0.18, size.height * 0.66, size.width * 0.36, size.height * 0.71)
      ..quadraticBezierTo(size.width * 0.55, size.height * 0.66, size.width * 0.72, size.height * 0.71)
      ..quadraticBezierTo(size.width * 0.88, size.height * 0.65, size.width, size.height * 0.70)
      ..lineTo(size.width, size.height * 0.80)
      ..lineTo(0, size.height * 0.80)
      ..close();
    canvas.drawPath(
      hillPath,
      Paint()..color = (warm ? const Color(0xFF8EA06A) : const Color(0xFF5E8E58)).withValues(alpha: 0.5),
    );

    // 土壤
    final soilRect = Rect.fromLTWH(0, size.height * 0.72, size.width, size.height * 0.28);
    canvas.drawRect(
      soilRect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF7B5C3E), Color(0xFF5B4530)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(soilRect),
    );
    final furrow = Paint()
      ..color = const Color(0xFF4C3826).withValues(alpha: 0.25)
      ..strokeWidth = 1;
    for (var i = 1; i <= 3; i++) {
      final y = soilRect.top + soilRect.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), furrow);
    }

    // 植株：后排 8 株，前排 6 株
    for (var i = 0; i < 8; i++) {
      _drawPlant(
        canvas,
        Offset(size.width * (0.04 + i * 0.13), size.height * 0.86),
        size.height * (0.55 + (i % 3) * 0.025),
        (i % 2 == 0 ? 1 : -1) * (sway - 0.5) * 0.025,
      );
    }
    for (var i = 0; i < 6; i++) {
      _drawPlant(
        canvas,
        Offset(size.width * (0.10 + i * 0.16), size.height * 0.98),
        size.height * (0.82 + (i % 2) * 0.05),
        (i % 2 == 0 ? 1 : -1) * (sway - 0.5) * 0.04,
      );
    }

    // 土粒
    final dot = Paint()..color = const Color(0xFF2F2417).withValues(alpha: 0.22);
    final dots = [
      Offset(size.width * 0.05, size.height * 0.90),
      Offset(size.width * 0.28, size.height * 0.94),
      Offset(size.width * 0.52, size.height * 0.88),
      Offset(size.width * 0.74, size.height * 0.96),
      Offset(size.width * 0.91, size.height * 0.91),
    ];
    for (final d in dots) {
      canvas.drawCircle(d, 1.1, dot);
    }
  }

  void _drawPlant(Canvas canvas, Offset base, double unit, double sway) {
    final gold = stageIdx >= 7;
    final stemColor = gold ? const Color(0xFFB3924F) : const Color(0xFF3F8F3F);
    final leafColor = gold ? const Color(0xFFC0A052) : const Color(0xFF4C9B45);
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.rotate(sway);

    if (stageIdx <= 0) {
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(0, -1.5), width: unit * 0.11, height: unit * 0.06),
        Paint()..color = const Color(0xFF6B4D32),
      );
      canvas.drawOval(
        Rect.fromCenter(center: Offset(unit * 0.2, -1), width: unit * 0.08, height: unit * 0.045),
        Paint()..color = const Color(0xFF7A5A3C),
      );
    } else {
      final stemHeight = stageIdx == 1
          ? unit * 0.10
          : stageIdx == 2
              ? unit * 0.22
              : stageIdx == 3
                  ? unit * 0.10
                  : stageIdx == 4
                      ? unit * 0.52
                      : unit * 0.62;
      if (stageIdx != 3) {
        canvas.drawLine(
          Offset.zero,
          Offset(0, -stemHeight),
          Paint()
            ..color = stemColor
            ..strokeWidth = 2.2
            ..strokeCap = StrokeCap.round,
        );
      }
      if (stageIdx == 1 || stageIdx == 2) {
        _leaf(canvas, Offset(0, -stemHeight * 0.9), -0.8, unit * 0.16, leafColor);
        _leaf(canvas, Offset(0, -stemHeight * 0.9), 0.8, unit * 0.16, leafColor);
      } else if (stageIdx == 3) {
        for (final a in [-1.2, -0.6, 0.0, 0.6, 1.2]) {
          _leaf(canvas, const Offset(0, -2), a, unit * (a.abs() > 1 ? 0.20 : 0.25),
              leafColor);
        }
      } else {
        _leaf(canvas, Offset(0, -stemHeight * 0.25), -1.05, unit * 0.2, leafColor);
        _leaf(canvas, Offset(0, -stemHeight * 0.5), 0.95, unit * 0.17, leafColor);
        _leaf(canvas, Offset(0, -stemHeight * 0.72), -0.8, unit * 0.13, leafColor);
        if (stageIdx == 5) {
          _flower(canvas, Offset(-unit * 0.09, -stemHeight * 0.95), unit * 0.055);
          _flower(canvas, Offset(unit * 0.08, -stemHeight * 1.05), unit * 0.05);
          _flower(canvas, Offset(0, -stemHeight * 1.15), unit * 0.045);
        } else if (stageIdx >= 6) {
          final podColor = stageIdx >= 7 ? const Color(0xFFB3924F) : const Color(0xFF8BC34A);
          _pod(canvas, Offset(-unit * 0.05, -stemHeight * 0.85), -0.4, unit * 0.24, podColor);
          _pod(canvas, Offset(unit * 0.05, -stemHeight * 0.98), 0.35, unit * 0.26, podColor);
          _pod(canvas, Offset(-unit * 0.03, -stemHeight * 1.08), -0.3, unit * 0.23, podColor);
        }
      }
    }
    canvas.restore();
  }

  void _leaf(Canvas canvas, Offset origin, double angle, double length, Color color) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.rotate(angle);
    final w = length * 0.46;
    final path = Path()
      ..moveTo(0, 0)
      ..cubicTo(-w, -length * 0.28, -w, -length * 0.92, 0, -length)
      ..cubicTo(w, -length * 0.92, w, -length * 0.28, 0, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  void _flower(Canvas canvas, Offset center, double radius) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    final petal = Paint()..color = const Color(0xFFFDD835).withValues(alpha: 0.96);
    for (var i = 0; i < 5; i++) {
      final angle = i * 72 * math.pi / 180;
      canvas.drawCircle(
        Offset(math.sin(angle) * radius, -math.cos(angle) * radius),
        radius * 0.62,
        petal,
      );
    }
    canvas.drawCircle(Offset.zero, radius * 0.4, Paint()..color = const Color(0xFFF7A600));
    canvas.restore();
  }

  void _pod(Canvas canvas, Offset center, double angle, double length, Color color) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0, -length / 2),
        width: length * 0.30,
        height: length,
      ),
      Paint()..color = color,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CropScenePainter old) =>
      old.stageIdx != stageIdx || old.sway != sway;
}

/// 简单指标格
class CloudMetricItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final String sub;

  const CloudMetricItem({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.unit = '',
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cloudSoft(primary, context, light: 0.05, dark: 0.12),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: primary),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(fontSize: 10.5, color: cloudSubtle(context))),
            ],
          ),
          const SizedBox(height: 3),
          Text.rich(
            TextSpan(
              text: value,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
              children: [
                if (unit.isNotEmpty)
                  TextSpan(
                    text: unit,
                    style: TextStyle(fontSize: 10, color: cloudHint(context)),
                  ),
              ],
            ),
          ),
          Text(sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 9.5, color: cloudHint(context))),
        ],
      ),
    );
  }
}
