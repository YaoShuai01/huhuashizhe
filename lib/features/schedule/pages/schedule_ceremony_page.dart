import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 姓名验证通过后的科技感仪式动画：
/// 动画结束后底部渐显“进入”按钮，点击后播放时空穿越动画再返回轮协页。
class ScheduleCeremonyPage extends StatefulWidget {
  final int memberNumber;
  final String memberName;

  const ScheduleCeremonyPage({
    super.key,
    required this.memberNumber,
    required this.memberName,
  });

  @override
  State<ScheduleCeremonyPage> createState() => _ScheduleCeremonyPageState();
}

class _ScheduleCeremonyPageState extends State<ScheduleCeremonyPage>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final AnimationController _warpController;

  bool _showEnter = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..forward();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _showEnter = true);
      }
    });
    _warpController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _warpController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _warpController.dispose();
    super.dispose();
  }

  void _enter() {
    if (_leaving) return;
    _leaving = true;
    HapticFeedback.mediumImpact();
    setState(() => _showEnter = false);
    _warpController.forward();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF030806),
        body: AnimatedBuilder(
          animation: Listenable.merge([_controller, _warpController]),
          builder: (context, _) {
            final p = _controller.value;
            final w = Curves.easeInCubic.transform(_warpController.value);
            final warpFade = 1.0 - ((w - 0.1) / 0.9).clamp(0.0, 1.0);
            final flash = ((w - 0.45) / 0.55).clamp(0.0, 1.0);
            final showButton = _showEnter && _warpController.value == 0;
            return Stack(
              fit: StackFit.expand,
              children: [
                Opacity(
                  opacity: warpFade,
                  child: Transform.scale(
                    scale: 1 + 0.24 * w,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: Alignment(0, -0.1),
                              radius: 1.1,
                              colors: [
                                Color(0xFF0B1F12),
                                Color(0xFF050807),
                                Color(0xFF020303),
                              ],
                              stops: [0.0, 0.58, 1.0],
                            ),
                          ),
                        ),
                        CustomPaint(painter: _CeremonyPainter(progress: p)),
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _successText(p),
                                const SizedBox(height: 20),
                                _greeting(p),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_warpController.value > 0)
                  CustomPaint(painter: _WarpPainter(progress: w)),
                IgnorePointer(
                  child: Opacity(
                    opacity: flash,
                    child: const ColoredBox(color: Color(0xFFEDFFEF)),
                  ),
                ),
                IgnorePointer(
                  ignoring: !showButton,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 46),
                        child: AnimatedOpacity(
                          opacity: showButton ? 1 : 0,
                          duration: const Duration(milliseconds: 650),
                          curve: Curves.easeOut,
                          child: AnimatedSlide(
                            offset:
                                showButton
                                    ? Offset.zero
                                    : const Offset(0, 0.35),
                            duration: const Duration(milliseconds: 650),
                            curve: Curves.easeOutCubic,
                            child: _enterButton(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _enterButton() {
    return GestureDetector(
      onTap: _enter,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xB31E4628),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0x668AFF9A)),
          boxShadow: const [
            BoxShadow(color: Color(0x558AFF9A), blurRadius: 22),
          ],
        ),
        child: const Text(
          '进入',
          style: TextStyle(
            color: Color(0xFFE8FFE9),
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 8,
          ),
        ),
      ),
    );
  }

  Widget _successText(double p) {
    final t = (p / 0.22).clamp(0.0, 1.0);
    final scale = 0.78 + 0.22 * Curves.easeOutCubic.transform(t);
    return Opacity(
      opacity: t,
      child: Transform.scale(
        scale: scale,
        child: const Text(
          '验证成功',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFFD7FFD9),
            fontSize: 42,
            fontWeight: FontWeight.w900,
            letterSpacing: 8,
            shadows: [
              Shadow(color: Color(0xCC66BB6A), blurRadius: 20),
              Shadow(color: Color(0x8066BB6A), blurRadius: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _greeting(double p) {
    final t = ((p - 0.55) / 0.25).clamp(0.0, 1.0);
    final offset = (1 - Curves.easeOutCubic.transform(t)) * 16;
    return Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset(0, offset),
        child: Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: '你好，'),
              TextSpan(
                text: '${widget.memberNumber}号成员',
                style: const TextStyle(
                  color: Color(0xFF8AFF9A),
                  fontWeight: FontWeight.w900,
                ),
              ),
              TextSpan(text: widget.memberName),
              const TextSpan(text: '\n欢迎加入团队'),
            ],
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFE8FFE9),
            fontSize: 24,
            height: 1.6,
            fontWeight: FontWeight.w800,
            shadows: [Shadow(color: Color(0x5966BB6A), blurRadius: 16)],
          ),
        ),
      ),
    );
  }
}

class _CeremonyPainter extends CustomPainter {
  final double progress;

  _CeremonyPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final t = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
    final center = Offset(size.width / 2, size.height * 0.45);
    final maxR =
        math.sqrt(size.width * size.width + size.height * size.height) * 0.62;

    // 全屏网格
    final gridPaint =
        Paint()
          ..color = const Color(0xFF66BB6A).withValues(alpha: 0.05 * t)
          ..strokeWidth = 1;
    const gap = 36.0;
    for (double x = 0; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // 从中心向外扩散的科技射线与粒子
    const count = 120;
    for (var i = 0; i < count; i++) {
      final angle = (math.pi * 2 * i) / count + math.sin(i * 1.7) * 0.08;
      final speed = 0.45 + ((i * 37) % 100) / 100 * 0.75;
      final r = maxR * t * speed;
      final end = center + Offset(math.cos(angle) * r, math.sin(angle) * r);
      final alpha = (1 - t).clamp(0.0, 1.0);
      final color =
          i % 3 == 0 ? const Color(0xFF3DDC84) : const Color(0xFF8AFF9A);
      canvas.drawLine(
        center,
        end,
        Paint()
          ..color = color.withValues(alpha: alpha * 0.45)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(
        end,
        1.2 + (i % 5) * 0.5,
        Paint()..color = color.withValues(alpha: alpha * 0.9),
      );
    }

    // 扩散圆环
    for (var i = 0; i < 3; i++) {
      final r = maxR * t * (0.45 + i * 0.18);
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = const Color(
            0xFF8AFF9A,
          ).withValues(alpha: (1 - t) * (0.24 - i * 0.06)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CeremonyPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// 时空穿越：向外飞驰的光线与中心高亮
class _WarpPainter extends CustomPainter {
  final double progress;

  _WarpPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.clamp(0.0, 1.0);
    final center = Offset(size.width / 2, size.height * 0.45);
    final maxR =
        math.sqrt(size.width * size.width + size.height * size.height) * 0.72;
    final front = Curves.easeIn.transform(t);

    const count = 110;
    for (var i = 0; i < count; i++) {
      final angle = (math.pi * 2 * i) / count + math.sin(i * 2.3) * 0.06;
      final speed = 0.5 + ((i * 53) % 100) / 100 * 0.8;
      final head = maxR * front * speed;
      final tail = head - maxR * (0.06 + 0.42 * t) * speed;
      if (head <= 0) continue;
      final start =
          center +
          Offset(
            math.cos(angle) * math.max(tail, 0),
            math.sin(angle) * math.max(tail, 0),
          );
      final end =
          center + Offset(math.cos(angle) * head, math.sin(angle) * head);
      final color =
          i % 4 == 0 ? const Color(0xFFD7FFD9) : const Color(0xFF8AFF9A);
      canvas.drawLine(
        start,
        end,
        Paint()
          ..color = color.withValues(alpha: (0.25 + 0.65 * t).clamp(0.0, 1.0))
          ..strokeWidth = 1 + (i % 4) * 0.6
          ..strokeCap = StrokeCap.round,
      );
    }

    canvas.drawCircle(
      center,
      18 + 60 * front,
      Paint()
        ..color = const Color(0xFFEAFFEC).withValues(alpha: 0.18 + 0.4 * t)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24),
    );
  }

  @override
  bool shouldRepaint(covariant _WarpPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
