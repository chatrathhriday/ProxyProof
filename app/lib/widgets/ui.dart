import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme.dart';

/// Expanding gold rings, like a sonar ping. Used behind the owl while scanning/broadcasting.
class Radar extends StatefulWidget {
  const Radar({super.key, required this.child, this.active = true, this.size = 260, this.color = Brand.gold});
  final Widget child;
  final bool active;
  final double size;
  final Color color;

  @override
  State<Radar> createState() => _RadarState();
}

class _RadarState extends State<Radar> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat();
  }

  @override
  void didUpdateWidget(Radar old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) _c.repeat();
    if (!widget.active && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.active)
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, _) =>
                    CustomPaint(size: Size.square(widget.size), painter: _RadarPainter(_c.value, widget.color)),
              ),
            ),
          widget.child,
        ],
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1;
      canvas.drawCircle(
        c,
        size.width * 0.22 + p * size.width * 0.28,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: (1 - p) * 0.55),
      );
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.t != t;
}

/// Circular attendance gauge that animates from 0 to [value] the first time it appears.
class AttendanceRing extends StatelessWidget {
  const AttendanceRing({
    super.key,
    required this.value,
    this.size = 72,
    this.stroke = 7,
    this.label,
    this.dark = false,
  });
  final double? value; // 0..1, null = no classes yet
  final double size;
  final double stroke;
  final String? label;
  final bool dark;

  static Color colorFor(double? v) => v == null
      ? Colors.grey
      : v >= 0.75
      ? Brand.present
      : v >= 0.65
      ? Brand.review
      : Brand.absent;

  @override
  Widget build(BuildContext context) {
    final color = dark ? Brand.gold : colorFor(value);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value ?? 0),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RingPainter(v, color, stroke, dark ? Colors.white12 : color.withValues(alpha: 0.13)),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value == null ? '—' : '${(v * 100).round()}%',
                  style: TextStyle(
                    fontSize: size * 0.24,
                    fontWeight: FontWeight.w700,
                    color: dark ? Colors.white : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                if (label != null)
                  Text(
                    label!,
                    style: TextStyle(fontSize: size * 0.11, color: dark ? Colors.white70 : Colors.grey),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v, this.color, this.stroke, this.track);
  final double v, stroke;
  final Color color, track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset(stroke / 2, stroke / 2) & Size(size.width - stroke, size.height - stroke);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, base..color = track);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * v, false, base..color = color);
    // 75% marker
    final a = -math.pi / 2 + math.pi * 2 * 0.75;
    final r = rect.width / 2;
    final c = rect.center;
    canvas.drawCircle(c + Offset(math.cos(a) * r, math.sin(a) * r), stroke * 0.28, Paint()..color = Brand.gold);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.v != v || old.color != color;
}

/// Navy gradient panel with soft decorative circles: the "hero" at the top of main screens.
class HeroPanel extends StatelessWidget {
  const HeroPanel({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(22, 22, 22, 26)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: Brand.heroGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: Brand.navy.withValues(alpha: 0.35), blurRadius: 30, offset: const Offset(0, 14))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(right: -40, top: -50, child: _Bubble(170, Brand.gold.withValues(alpha: 0.10))),
          Positioned(left: -30, bottom: -60, child: _Bubble(140, Colors.white.withValues(alpha: 0.05))),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.size, this.color);
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}

/// Small rounded status chip.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = Brand.gold, this.icon, this.pulse = false});
  final String text;
  final Color color;
  final IconData? icon;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    Widget dot = Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    if (pulse) {
      dot = dot.animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: 1, end: 0.25, duration: 800.ms);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) Icon(icon, size: 14, color: color) else dot,
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Grey placeholder blocks that shimmer while data loads (feels faster than a spinner).
class Skeleton extends StatelessWidget {
  const Skeleton({super.key, this.height = 90, this.count = 3});
  final double height;
  final int count;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).brightness == Brightness.dark ? Colors.white10 : const Color(0xFFEDE7D8);
    return Column(
      children: [
        for (var i = 0; i < count; i++)
          Container(
            height: height,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(22)),
          ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1200.ms, color: Colors.white.withValues(alpha: 0.5)),
      ],
    );
  }
}

/// Fades + slides children in one after another: used for lists so screens feel alive.
extension Entrance on List<Widget> {
  List<Widget> staggered({int startMs = 0}) => [
    for (var i = 0; i < length; i++)
      this[i]
          .animate(delay: (startMs + i * 60).ms)
          .fadeIn(duration: 350.ms, curve: Curves.easeOut)
          .slideY(begin: 0.08, end: 0, duration: 350.ms, curve: Curves.easeOutCubic),
  ];
}

/// Serif section heading with an optional trailing widget.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
    child: Row(
      children: [
        Expanded(child: Text(text, style: Brand.display(context, size: 20))),
        ?trailing,
      ],
    ),
  );
}
