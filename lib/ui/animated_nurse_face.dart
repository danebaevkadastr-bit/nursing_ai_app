import 'package:flutter/material.dart';
import 'dart:math' as math;

class AnimatedNurseFace extends StatefulWidget {
  final bool isSpeaking;
  final bool isListening;

  const AnimatedNurseFace({
    super.key,
    required this.isSpeaking,
    required this.isListening,
  });

  @override
  State<AnimatedNurseFace> createState() => _AnimatedNurseFaceState();
}

class _AnimatedNurseFaceState extends State<AnimatedNurseFace>
    with TickerProviderStateMixin {
  late AnimationController _breathingController;
  late AnimationController _speakingController;
  late AnimationController _blinkingController;
  late AnimationController _floatController;

  @override
  void initState() {
    super.initState();

    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);

    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _speakingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _blinkingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 110),
    );

    _startBlinking();
  }

  void _startBlinking() async {
    while (mounted) {
      await Future.delayed(
        Duration(milliseconds: 2800 + math.Random().nextInt(2200)),
      );
      if (!mounted) break;
      await _blinkingController.forward();
      await Future.delayed(const Duration(milliseconds: 70));
      await _blinkingController.reverse();
    }
  }

  @override
  void didUpdateWidget(AnimatedNurseFace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSpeaking && !oldWidget.isSpeaking) {
      _speakingController.repeat(reverse: true);
    } else if (!widget.isSpeaking && oldWidget.isSpeaking) {
      _speakingController.animateTo(
        0,
        duration: const Duration(milliseconds: 120),
      );
    }
    if (widget.isListening && !oldWidget.isListening) {
      _breathingController.duration = const Duration(milliseconds: 800);
      _breathingController.repeat(reverse: true);
    } else if (!widget.isListening && oldWidget.isListening) {
      _breathingController.duration = const Duration(milliseconds: 2400);
      _breathingController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _breathingController.dispose();
    _speakingController.dispose();
    _blinkingController.dispose();
    _floatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _breathingController,
        _speakingController,
        _blinkingController,
        _floatController,
      ]),
      builder: (context, child) {
        final breathScale = 1.0 + _breathingController.value * 0.028;
        final floatOffset = math.sin(_floatController.value * math.pi) * 12.0;

        return Transform.translate(
          offset: Offset(0, -floatOffset),
          child: Transform.scale(
            scale: breathScale,
            child: SizedBox(
              width: 300,
              height: 300,
              child: CustomPaint(
                painter: NurseFacePainter(
                  mouthOpen: _speakingController.value,
                  eyeClose: _blinkingController.value,
                  isListening: widget.isListening,
                  isSpeaking: widget.isSpeaking,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class NurseFacePainter extends CustomPainter {
  final double mouthOpen;
  final double eyeClose;
  final bool isListening;
  final bool isSpeaking;

  NurseFacePainter({
    required this.mouthOpen,
    required this.eyeClose,
    required this.isListening,
    required this.isSpeaking,
  });

  // Pink palette
  static const Color pinkLight = Color(0xFFFFF0F5);
  static const Color pinkMid = Color(0xFFFFD6E7);
  static const Color pinkAccent = Color(0xFFFF8FB1);
  static const Color pinkDeep = Color(0xFFE8527A);
  static const Color pinkBorder = Color(0xFFFFB3CE);
  static const Color darkInk = Color(0xFF2D1B2E);
  static const Color blushColor = Color(0xFFFFB3C6);
  static const Color hatWhite = Color(0xFFFFF5F8);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2 + 10;

    _drawShadow(canvas, cx, cy);
    _drawBody(canvas, cx, cy);
    _drawCheeks(canvas, cx, cy);
    _drawEyes(canvas, cx, cy);
    _drawMouth(canvas, cx, cy);
    _drawHat(canvas, cx, cy);
  }

  void _drawShadow(Canvas canvas, double cx, double cy) {
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + 88), width: 200, height: 30),
      Paint()
        ..color = pinkAccent.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
  }

  void _drawBody(Canvas canvas, double cx, double cy) {
    final bodyPath = _buildBodyPath(cx, cy);

    // Main fill — white-pink radial gradient
    canvas.drawPath(
      bodyPath,
      Paint()
        ..shader =
            RadialGradient(
              center: const Alignment(-0.25, -0.35),
              radius: 0.9,
              colors: [
                Colors.white,
                const Color(0xFFFFF0F5),
                const Color(0xFFFFD6E7),
              ],
              stops: const [0.0, 0.55, 1.0],
            ).createShader(
              Rect.fromCenter(center: Offset(cx, cy), width: 260, height: 210),
            ),
    );

    // Soft border
    canvas.drawPath(
      bodyPath,
      Paint()
        ..color = pinkBorder.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Top-left shine
    canvas.drawPath(
      bodyPath,
      Paint()
        ..shader =
            RadialGradient(
              center: const Alignment(-0.55, -0.5),
              radius: 0.55,
              colors: [
                Colors.white.withValues(alpha: 0.9),
                Colors.white.withValues(alpha: 0.0),
              ],
            ).createShader(
              Rect.fromCenter(
                center: Offset(cx - 45, cy - 45),
                width: 150,
                height: 120,
              ),
            ),
    );
  }

  Path _buildBodyPath(double cx, double cy) {
    // Cute round blob — wider, rounder
    final p = Path();
    p.moveTo(cx - 90, cy + 5);
    p.cubicTo(cx - 112, cy - 28, cx - 112, cy - 72, cx - 65, cy - 96);
    p.cubicTo(cx - 36, cy - 112, cx + 36, cy - 112, cx + 65, cy - 96);
    p.cubicTo(cx + 112, cy - 72, cx + 112, cy - 28, cx + 90, cy + 5);
    p.cubicTo(cx + 105, cy + 48, cx + 78, cy + 88, cx + 42, cy + 92);
    p.cubicTo(cx + 18, cy + 96, cx - 18, cy + 96, cx - 42, cy + 92);
    p.cubicTo(cx - 78, cy + 88, cx - 105, cy + 48, cx - 90, cy + 5);
    p.close();
    return p;
  }

  void _drawCheeks(Canvas canvas, double cx, double cy) {
    // Left cheek blush
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - 68, cy + 18), width: 48, height: 24),
      Paint()
        ..color = blushColor.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    // Right cheek blush
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + 68, cy + 18), width: 48, height: 24),
      Paint()
        ..color = blushColor.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
  }

  void _drawEyes(Canvas canvas, double cx, double cy) {
    final eyeH = 22.0 * (1.0 - eyeClose);

    for (final side in [-1.0, 1.0]) {
      final ex = cx + side * 44;
      final ey = cy - 14;

      // Eye shadow
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(ex, ey + 2),
          width: 24,
          height: eyeH + 6,
        ),
        Paint()
          ..color = darkInk.withValues(alpha: 0.08)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );

      // Main eye (dark oval)
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(ex, ey),
          width: 22,
          height: math.max(eyeH, 2.0),
        ),
        Paint()..color = darkInk,
      );

      // White shine dot
      if (eyeClose < 0.45) {
        canvas.drawCircle(
          Offset(ex - side * 4 - 2, ey - 5),
          3.5,
          Paint()..color = Colors.white.withValues(alpha: 0.85),
        );
        // Smaller second shine
        canvas.drawCircle(
          Offset(ex + side * 2, ey + 3),
          1.5,
          Paint()..color = Colors.white.withValues(alpha: 0.5),
        );
      }
    }
  }

  void _drawMouth(Canvas canvas, double cx, double cy) {
    final my = cy + 42;

    if (isSpeaking) {
      final openH = 5.0 + mouthOpen * 20.0;
      final openW = 30.0 + mouthOpen * 10.0;

      // Outer mouth
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, my), width: openW, height: openH),
        Paint()..color = pinkDeep,
      );
      // Inner mouth (tongue hint when open wide)
      if (openH > 12) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(cx, my + openH * 0.15),
            width: openW - 10,
            height: openH * 0.55,
          ),
          Paint()..color = const Color(0xFFFF6B8A),
        );
      }
      // Teeth
      if (openH > 8) {
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(cx, my - openH * 0.25),
            width: openW - 8,
            height: 5,
          ),
          Paint()..color = Colors.white.withValues(alpha: 0.85),
        );
      }
    } else {
      // Cute small smile
      final smilePath = Path();
      smilePath.moveTo(cx - 18, my - 1);
      smilePath.quadraticBezierTo(cx, my + 10, cx + 18, my - 1);

      canvas.drawPath(
        smilePath,
        Paint()
          ..color = pinkDeep
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _drawHat(Canvas canvas, double cx, double cy) {
    // === Nurse Cap — yassi, keng, tepasi tekis ===
    // Cap base Y position (top of head)
    final hatBaseY = cy - 92.0;

    // --- Cap main body (wide flat trapezoid shape) ---
    final capPath = Path();
    capPath.moveTo(cx - 76, hatBaseY + 2); // bottom-left
    capPath.lineTo(cx - 68, hatBaseY - 44); // top-left
    capPath.lineTo(cx + 68, hatBaseY - 44); // top-right
    capPath.lineTo(cx + 76, hatBaseY + 2); // bottom-right
    // Slight bottom curve
    capPath.quadraticBezierTo(cx, hatBaseY + 12, cx - 76, hatBaseY + 2);
    capPath.close();

    // Cap shadow
    canvas.drawPath(
      capPath,
      Paint()
        ..color = pinkAccent.withValues(alpha: 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    // Cap fill — white with slight pink tint
    canvas.drawPath(
      capPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, hatWhite, pinkMid],
          stops: const [0.0, 0.6, 1.0],
        ).createShader(Rect.fromLTWH(cx - 80, hatBaseY - 48, 160, 60)),
    );

    // Cap border
    canvas.drawPath(
      capPath,
      Paint()
        ..color = pinkBorder.withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // --- Fold/crease line at the bottom of cap ---
    final foldRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, hatBaseY + 4), width: 148, height: 14),
      const Radius.circular(5),
    );
    canvas.drawRRect(
      foldRect,
      Paint()
        ..shader =
            LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [const Color(0xFFFFF0F8), pinkMid],
            ).createShader(
              Rect.fromCenter(
                center: Offset(cx, hatBaseY + 4),
                width: 148,
                height: 14,
              ),
            ),
    );
    canvas.drawRRect(
      foldRect,
      Paint()
        ..color = pinkBorder.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Cap shine highlight (top-left)
    final shinePath = Path();
    shinePath.moveTo(cx - 50, hatBaseY - 40);
    shinePath.cubicTo(
      cx - 60,
      hatBaseY - 30,
      cx - 58,
      hatBaseY - 12,
      cx - 52,
      hatBaseY - 5,
    );
    shinePath.cubicTo(
      cx - 38,
      hatBaseY - 10,
      cx - 30,
      hatBaseY - 28,
      cx - 34,
      hatBaseY - 40,
    );
    shinePath.close();
    canvas.drawPath(
      shinePath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..style = PaintingStyle.fill,
    );

    // === Red Cross on cap center ===
    _drawRedCross(canvas, cx, hatBaseY - 22);
  }

  void _drawRedCross(Canvas canvas, double cx, double cy) {
    const crossColor = Color(0xFFC0392B);
    final shadow = Paint()
      ..color = crossColor.withValues(alpha: 0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

    // Shadow
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy + 1), width: 32, height: 11),
        const Radius.circular(3),
      ),
      shadow,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy + 1), width: 11, height: 32),
        const Radius.circular(3),
      ),
      shadow,
    );

    final crossPaint = Paint()
      ..color = crossColor
      ..style = PaintingStyle.fill;

    // Horizontal
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: 32, height: 11),
        const Radius.circular(3),
      ),
      crossPaint,
    );
    // Vertical
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: 11, height: 32),
        const Radius.circular(3),
      ),
      crossPaint,
    );
  }

  @override
  bool shouldRepaint(covariant NurseFacePainter oldDelegate) {
    return oldDelegate.mouthOpen != mouthOpen ||
        oldDelegate.eyeClose != eyeClose ||
        oldDelegate.isListening != isListening ||
        oldDelegate.isSpeaking != isSpeaking;
  }
}
