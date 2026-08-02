import 'dart:math';
import 'package:flutter/material.dart';

/// An animated, continuously-moving "biology HUD" background, drawn
/// entirely in code (CustomPainter + AnimationController). No image
/// assets involved - this recreates the STYLE of a sci-fi biology
/// dashboard (DNA helix, scan rings, molecule cluster, heartbeat line,
/// a human skeleton, corner HUD brackets) as original vector line-art,
/// not a copy of any specific photo or stock asset.
///
/// Defaults are tuned to actually read as moving on a light/cream
/// background - visible but not neon, muted green, no glow. Usage: drop
/// this behind your screen's content inside a Stack, e.g.:
///
///   Scaffold(
///     body: Stack(
///       children: [
///         const Positioned.fill(child: DnaHelixBackground()),
///         SafeArea(child: yourExistingContent),
///       ],
///     ),
///   )
class DnaHelixBackground extends StatefulWidget {
  final Color strandColor;
  final double opacity;
  final bool glow;

  const DnaHelixBackground({
    super.key,
    this.strandColor = const Color(0xFF388E3C), // muted forest green
    this.opacity = 0.38, // visible motion accent, still lets text/buttons read
    this.glow = false, // glow reads as "smudge" on light backgrounds, off by default
  });

  @override
  State<DnaHelixBackground> createState() => _DnaHelixBackgroundState();
}

class _DnaHelixBackgroundState extends State<DnaHelixBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _BioHudPainter(
              progress: _controller.value,
              color: widget.strandColor,
              opacity: widget.opacity,
              glow: widget.glow,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _BioHudPainter extends CustomPainter {
  final double progress; // 0.0 -> 1.0, looping
  final Color color;
  final double opacity;
  final bool glow;

  _BioHudPainter({
    required this.progress,
    required this.color,
    required this.opacity,
    required this.glow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawScanRings(canvas, size);
    _drawHelix(canvas, size);
    _drawHexCluster(canvas, size);
    _drawHeartbeatLine(canvas, size);
    _drawSkeleton(canvas, size);
    _drawCornerBrackets(canvas, size);
    _drawParticles(canvas, size);
  }

  // ---------------- DNA double helix, center ----------------
  void _drawHelix(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final amplitude = size.width * 0.22;
    const spacing = 30.0;
    final phaseShift = progress * 2 * pi;

    final rungPaint = Paint()
      ..color = color.withValues(alpha: opacity * 0.4)
      ..strokeWidth = 1.0;
    final strandAPaint = Paint()..color = color.withValues(alpha: opacity);
    final strandBPaint = Paint()..color = color.withValues(alpha: opacity * 0.6);
    final glowPaint = glow
        ? (Paint()
          ..color = color.withValues(alpha: opacity * 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6))
        : null;

    final pointsA = <Offset>[];
    final pointsB = <Offset>[];
    for (double y = -spacing; y < size.height + spacing; y += spacing) {
      final angle = (y / 85) + phaseShift;
      pointsA.add(Offset(centerX + amplitude * sin(angle), y));
      pointsB.add(Offset(centerX + amplitude * sin(angle + pi), y));
    }

    for (var i = 0; i < pointsA.length; i++) {
      canvas.drawLine(pointsA[i], pointsB[i], rungPaint);
    }
    for (var i = 0; i < pointsB.length; i++) {
      if (glowPaint != null) canvas.drawCircle(pointsB[i], 5, glowPaint);
      canvas.drawCircle(pointsB[i], 3.0, strandBPaint);
    }
    for (var i = 0; i < pointsA.length; i++) {
      if (glowPaint != null) canvas.drawCircle(pointsA[i], 7, glowPaint);
      canvas.drawCircle(pointsA[i], 4.0, strandAPaint);
    }
  }

  // ---------------- Concentric scan rings behind the helix ----------------
  void _drawScanRings(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = min(size.width, size.height) * 0.42;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = color.withValues(alpha: opacity * 0.5);

    for (var i = 1; i <= 3; i++) {
      final radius = maxRadius * (i / 3);
      // partial arcs, slowly rotating, like a radar sweep - not full circles
      final sweepStart = (progress * 2 * pi) + (i * 0.9);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        sweepStart,
        pi * 1.3,
        false,
        ringPaint,
      );
    }

    // small tick marks around the outer ring
    final tickPaint = Paint()
      ..color = color.withValues(alpha: opacity * 0.4)
      ..strokeWidth = 1.0;
    for (var i = 0; i < 24; i++) {
      final a = (i / 24) * 2 * pi + progress * 2 * pi;
      final outer = center + Offset(cos(a), sin(a)) * maxRadius;
      final inner = center + Offset(cos(a), sin(a)) * (maxRadius - 6);
      canvas.drawLine(inner, outer, tickPaint);
    }
  }

  // ---------------- Hexagon molecule cluster, bottom-left ----------------
  void _drawHexCluster(Canvas canvas, Size size) {
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color.withValues(alpha: opacity * 0.7);
    final dotPaint = Paint()..color = color.withValues(alpha: opacity * 0.8);

    final origin = Offset(size.width * 0.14, size.height * 0.80);
    const hexRadius = 16.0;
    // three hexagons sharing edges, like a simple molecular diagram
    final centers = [
      origin,
      origin + const Offset(hexRadius * 1.73, hexRadius * 1.0),
      origin + const Offset(0, hexRadius * 2.0),
    ];

    for (final c in centers) {
      final path = Path();
      for (var i = 0; i < 6; i++) {
        final a = pi / 6 + i * pi / 3;
        final p = c + Offset(cos(a), sin(a)) * hexRadius;
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      canvas.drawPath(path, basePaint);
      canvas.drawCircle(c, 2.2, dotPaint);
    }
  }

  // ---------------- EKG / heartbeat line, upper-left ----------------
  void _drawHeartbeatLine(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = color.withValues(alpha: opacity * 0.8);

    final baseY = size.height * 0.16;
    final startX = size.width * 0.08;
    final width = size.width * 0.34;
    // horizontal drift so the waveform feels alive, like a live monitor
    final drift = (progress * width * 0.4) % (width * 0.2);

    final path = Path()..moveTo(startX - drift, baseY);
    final segment = width / 10;
    for (var i = 0; i < 10; i++) {
      final x = startX - drift + i * segment;
      double y = baseY;
      if (i == 4) y = baseY - 4;
      if (i == 5) y = baseY + 22; // sharp downbeat, classic ECG spike
      if (i == 6) y = baseY - 14;
      if (i == 7) y = baseY + 2;
      path.lineTo(x, y);
    }
    canvas.drawPath(path, linePaint);
  }

  // ---------------- Human skeleton line-art, lower-right ----------------
  void _drawSkeleton(Canvas canvas, Size size) {
    final bonePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: opacity * 0.75);
    final jointPaint = Paint()..color = color.withValues(alpha: opacity * 0.9);

    // A single unit scaled to the screen's shortest side, so the figure
    // stays proportionate on both phones and tablets.
    final u = (size.shortestSide * 0.028).clamp(8.0, 16.0);
    // Anchored from the feet upward (rather than a fixed fraction from the
    // top) so the figure always sits low, near the bottom edge, regardless
    // of screen height.
    final feetY = size.height - 24;
    final skull = Offset(size.width * 0.84, feetY - u * 8.3);

    // Skull + jaw hint.
    canvas.drawCircle(skull, u * 1.1, bonePaint);
    canvas.drawLine(
      skull + Offset(-u * 0.4, u * 0.9),
      skull + Offset(u * 0.4, u * 0.9),
      bonePaint,
    );

    // Spine.
    final neckBase = skull + Offset(0, u * 1.3);
    final spineEnd = neckBase + Offset(0, u * 3.2);
    canvas.drawLine(neckBase, spineEnd, bonePaint);

    // Shoulders + a few ribcage arcs.
    final shoulderY = neckBase.dy + u * 0.5;
    final shoulderL = Offset(neckBase.dx - u * 1.3, shoulderY);
    final shoulderR = Offset(neckBase.dx + u * 1.3, shoulderY);
    canvas.drawLine(shoulderL, shoulderR, bonePaint);
    for (var i = 1; i <= 3; i++) {
      final ribY = shoulderY + u * 0.55 * i;
      final ribWidth = u * (1.1 - i * 0.12);
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(neckBase.dx, ribY),
          width: ribWidth * 2,
          height: u * 0.7,
        ),
        0,
        pi,
        false,
        bonePaint,
      );
    }

    // Arms: shoulder -> elbow -> hand. dir = -1 (left) / 1 (right).
    void arm(Offset shoulder, double dir) {
      final elbow = shoulder + Offset(dir * u * 0.9, u * 1.5);
      final hand = elbow + Offset(dir * u * 0.3, u * 1.4);
      canvas.drawLine(shoulder, elbow, bonePaint);
      canvas.drawLine(elbow, hand, bonePaint);
      canvas.drawCircle(elbow, 1.6, jointPaint);
      canvas.drawCircle(hand, 1.8, jointPaint);
    }

    arm(shoulderL, -1);
    arm(shoulderR, 1);

    // Pelvis.
    final hipL = Offset(spineEnd.dx - u * 0.9, spineEnd.dy);
    final hipR = Offset(spineEnd.dx + u * 0.9, spineEnd.dy);
    canvas.drawLine(hipL, hipR, bonePaint);

    // Legs: hip -> knee -> foot.
    void leg(Offset hip, double dir) {
      final knee = hip + Offset(dir * u * 0.35, u * 1.9);
      final foot = knee + Offset(dir * u * 0.15, u * 1.9);
      canvas.drawLine(hip, knee, bonePaint);
      canvas.drawLine(knee, foot, bonePaint);
      canvas.drawCircle(knee, 1.6, jointPaint);
      canvas.drawCircle(foot, 1.8, jointPaint);
    }

    leg(hipL, -1);
    leg(hipR, 1);

    // Joint accent dots, matching the hex-cluster/HUD dot motif.
    for (final joint in [skull, shoulderL, shoulderR, hipL, hipR]) {
      canvas.drawCircle(joint, 1.8, jointPaint);
    }
  }

  // ---------------- Corner HUD brackets, all 4 corners ----------------
  void _drawCornerBrackets(Canvas canvas, Size size) {
    final bracketPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = color.withValues(alpha: opacity * 0.6);
    const armLength = 18.0;
    const inset = 20.0;

    void corner(Offset origin, bool flipX, bool flipY) {
      final dx = flipX ? -1.0 : 1.0;
      final dy = flipY ? -1.0 : 1.0;
      final path = Path()
        ..moveTo(origin.dx, origin.dy + armLength * dy)
        ..lineTo(origin.dx, origin.dy)
        ..lineTo(origin.dx + armLength * dx, origin.dy);
      canvas.drawPath(path, bracketPaint);
    }

    corner(const Offset(inset, inset), false, false);
    corner(Offset(size.width - inset, inset), true, false);
    corner(Offset(inset, size.height - inset), false, true);
    corner(Offset(size.width - inset, size.height - inset), true, true);
  }

  // ---------------- Scattered data-point dots ----------------
  void _drawParticles(Canvas canvas, Size size) {
    final particlePaint = Paint()..color = color.withValues(alpha: opacity * 0.5);
    final rand = Random(7); // fixed seed - stable layout, only position drifts
    for (var i = 0; i < 16; i++) {
      final baseX = rand.nextDouble() * size.width;
      final baseY =
          (rand.nextDouble() * size.height + progress * size.height * 0.25) %
              size.height;
      canvas.drawCircle(Offset(baseX, baseY), 1.5, particlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _BioHudPainter oldDelegate) =>
      oldDelegate.progress != progress;
}