import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// "Professor Hoot" — the ProxyProof mascot, drawn in code so it stays crisp at any size
/// and animates at 60/120 fps without image assets.
enum OwlMood { idle, scanning, happy, worried, sleeping, alert }

class Owl extends StatefulWidget {
  const Owl({super.key, this.mood = OwlMood.idle, this.size = 140});
  final OwlMood mood;
  final double size;

  @override
  State<Owl> createState() => _OwlState();
}

class _OwlState extends State<Owl> with SingleTickerProviderStateMixin {
  // One looping clock drives every motion; the painter derives blink/bob/look from it.
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => CustomPaint(painter: _OwlPainter(_c.value, widget.mood)),
        ),
      ),
    );
  }
}

class _OwlPainter extends CustomPainter {
  _OwlPainter(this.t, this.mood);
  final double t; // 0..1 loop
  final OwlMood mood;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 200; // design on a 200x200 grid
    canvas.save();
    canvas.scale(s);

    final wave = math.sin(t * 2 * math.pi);
    final bob = switch (mood) {
      OwlMood.happy => -(wave.abs()) * 10, // little hops
      OwlMood.sleeping => wave * 1.5,
      OwlMood.alert => math.sin(t * 2 * math.pi * 6) * 1.5, // quick shiver
      _ => wave * 3,
    };
    final tilt = switch (mood) {
      OwlMood.scanning => math.sin(t * 2 * math.pi) * 0.08,
      OwlMood.worried => -0.06,
      _ => 0.0,
    };

    // soft ground shadow
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(100, 188), width: 92 - bob.abs() * 2, height: 12),
      Paint()..color = Brand.navy.withValues(alpha: 0.12),
    );

    canvas.save();
    canvas.translate(100, 110 + bob);
    canvas.rotate(tilt);
    canvas.translate(-100, -110);
    _body(canvas);
    _face(canvas, wave);
    _cap(canvas, wave);
    canvas.restore();

    if (mood == OwlMood.happy) _sparkles(canvas);
    if (mood == OwlMood.sleeping) _zzz(canvas);
    if (mood == OwlMood.alert) _exclaim(canvas);
    canvas.restore();
  }

  void _body(Canvas canvas) {
    final navy = Paint()..color = Brand.navy;
    // ear tufts
    final tufts = Path()
      ..moveTo(52, 62)
      ..lineTo(60, 30)
      ..lineTo(80, 52)
      ..moveTo(148, 62)
      ..lineTo(140, 30)
      ..lineTo(120, 52);
    canvas.drawPath(tufts, navy);
    // wings (flap when happy)
    final flap = mood == OwlMood.happy ? math.sin(t * 2 * math.pi * 2) * 0.35 : 0.0;
    for (final side in [-1, 1]) {
      canvas.save();
      canvas.translate(100 + side * 52, 112);
      canvas.rotate(side * (0.25 + flap));
      canvas.drawOval(
        Rect.fromCenter(center: Offset(side * 8, 18), width: 30, height: 64),
        Paint()..color = Brand.navy2,
      );
      canvas.restore();
    }
    // body
    canvas.drawOval(Rect.fromCenter(center: const Offset(100, 112), width: 124, height: 140), navy);
    // belly
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(100, 132), width: 78, height: 84),
      Paint()..color = Brand.ivory,
    );
    // gold feather chevrons on the belly
    final chev = Paint()
      ..color = Brand.gold.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final y = 122.0 + i * 14;
      for (final x in [86.0, 100.0, 114.0]) {
        if (i == 2 && x != 100) continue;
        canvas.drawPath(
          Path()
            ..moveTo(x - 5, y)
            ..quadraticBezierTo(x, y + 6, x + 5, y),
          chev,
        );
      }
    }
    // feet
    final feet = Paint()..color = Brand.gold;
    for (final x in [86.0, 114.0]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, 180), width: 18, height: 8),
          const Radius.circular(4),
        ),
        feet,
      );
    }
  }

  void _face(Canvas canvas, double wave) {
    // face disc
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(100, 84), width: 104, height: 70),
      Paint()..color = Brand.navy2,
    );
    final blink = (t % 0.5) > 0.47; // two blinks per loop, very short
    final lookX = switch (mood) {
      OwlMood.scanning => math.sin(t * 2 * math.pi) * 7,
      OwlMood.alert => 0.0,
      _ => wave * 1.5,
    };
    for (final cx in [78.0, 122.0]) {
      final c = Offset(cx, 84);
      // gold ring + white eye
      canvas.drawCircle(c, 22, Paint()..color = Brand.gold);
      canvas.drawCircle(c, 18.5, Paint()..color = Colors.white);
      final closedLine = Paint()
        ..color = Brand.navy
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      switch (mood) {
        case OwlMood.happy:
          // ^ ^ smiling eyes
          canvas.drawArc(
            Rect.fromCircle(center: c.translate(0, 4), radius: 9),
            math.pi * 1.1,
            math.pi * 0.8,
            false,
            closedLine,
          );
        case OwlMood.sleeping:
          canvas.drawArc(
            Rect.fromCircle(center: c.translate(0, -3), radius: 9),
            math.pi * 0.15,
            math.pi * 0.7,
            false,
            closedLine,
          );
        default:
          if (blink && mood != OwlMood.alert) {
            canvas.drawLine(c.translate(-10, 0), c.translate(10, 0), closedLine);
          } else {
            final r = mood == OwlMood.alert ? 6.0 : 8.5;
            canvas.drawCircle(c.translate(lookX, 1), r, Paint()..color = Brand.navy);
            canvas.drawCircle(c.translate(lookX + 3, -2.5), 2.6, Paint()..color = Colors.white);
          }
      }
      if (mood == OwlMood.worried) {
        // slanted brows
        final dir = cx < 100 ? 1 : -1;
        canvas.drawLine(
          c.translate(-12.0 * dir, -24),
          c.translate(10.0 * dir, -30),
          closedLine..color = Brand.goldSoft,
        );
      }
    }
    // beak
    canvas.drawPath(
      Path()
        ..moveTo(93, 96)
        ..lineTo(107, 96)
        ..lineTo(100, 110)
        ..close(),
      Paint()..color = Brand.gold,
    );
  }

  void _cap(Canvas canvas, double wave) {
    final navy = Paint()..color = const Color(0xFF07122C);
    // mortarboard
    canvas.drawPath(
      Path()
        ..moveTo(100, 22)
        ..lineTo(150, 38)
        ..lineTo(100, 54)
        ..lineTo(50, 38)
        ..close(),
      navy,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(100, 52), width: 52, height: 14),
        const Radius.circular(4),
      ),
      navy,
    );
    // tassel swings with the loop (faster when alert)
    final swing = mood == OwlMood.alert ? math.sin(t * 2 * math.pi * 6) * 0.5 : wave * 0.25;
    final gold = Paint()
      ..color = Brand.gold
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(const Offset(100, 38), 3.5, Paint()..color = Brand.gold);
    final end = const Offset(140, 40) + Offset(math.sin(swing) * 6, 22 * math.cos(swing));
    canvas.drawLine(const Offset(100, 38), const Offset(140, 40), gold);
    canvas.drawLine(const Offset(140, 40), end, gold);
    canvas.drawCircle(end, 4, Paint()..color = Brand.gold);
  }

  void _sparkles(Canvas canvas) {
    final p = Paint()..color = Brand.gold;
    for (var i = 0; i < 5; i++) {
      final phase = (t + i / 5) % 1;
      final angle = i * 1.256 - math.pi / 2;
      final dist = 70 + phase * 30;
      final c = Offset(100 + math.cos(angle) * dist, 100 + math.sin(angle) * dist * 0.8);
      final r = 6 * (1 - phase);
      p.color = Brand.gold.withValues(alpha: 1 - phase);
      _star(canvas, c, r, p);
    }
  }

  void _star(Canvas canvas, Offset c, double r, Paint p) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final rad = i.isEven ? r : r * 0.35;
      final a = i * math.pi / 4;
      final pt = c + Offset(math.cos(a) * rad, math.sin(a) * rad);
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    canvas.drawPath(path..close(), p);
  }

  void _zzz(Canvas canvas) {
    for (var i = 0; i < 3; i++) {
      final phase = (t + i / 3) % 1;
      final tp = TextPainter(
        text: TextSpan(
          text: 'z',
          style: TextStyle(
            color: Brand.gold.withValues(alpha: 1 - phase),
            fontSize: 14 + phase * 10,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(150 + phase * 18, 40 - phase * 30));
    }
  }

  void _exclaim(Canvas canvas) {
    final p = Paint()..color = Brand.gold;
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(160, 14, 8, 26), const Radius.circular(4)), p);
    canvas.drawCircle(const Offset(164, 48), 4.5, p);
  }

  @override
  bool shouldRepaint(_OwlPainter old) => old.t != t || old.mood != mood;
}
