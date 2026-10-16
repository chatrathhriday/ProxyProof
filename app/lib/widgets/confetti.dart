import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// One-shot confetti burst (gold, ivory, navy) drawn on a canvas: no package, no assets.
/// Call [ConfettiController.fire] to play it.
class ConfettiController extends ChangeNotifier {
  void fire() => notifyListeners();
}

class Confetti extends StatefulWidget {
  const Confetti({super.key, required this.controller, required this.child});
  final ConfettiController controller;
  final Widget child;

  @override
  State<Confetti> createState() => _ConfettiState();
}

class _Bit {
  _Bit(math.Random r)
    : angle = -math.pi / 2 + (r.nextDouble() - 0.5) * math.pi * 1.1,
      speed = 380 + r.nextDouble() * 420,
      spin = (r.nextDouble() - 0.5) * 14,
      size = 5 + r.nextDouble() * 6,
      color = [Brand.gold, Brand.goldSoft, Colors.white, const Color(0xFF7BE0A8), Brand.navy3][r.nextInt(5)];
  final double angle, speed, spin, size;
  final Color color;
}

class _ConfettiState extends State<Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  List<_Bit> _bits = const [];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_fire);
  }

  void _fire() {
    final r = math.Random();
    setState(() => _bits = List.generate(70, (_) => _Bit(r)));
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_fire);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, _) =>
                    _c.isAnimating ? CustomPaint(painter: _ConfettiPainter(_bits, _c.value)) : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.bits, this.t);
  final List<_Bit> bits;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, size.height * 0.42);
    final secs = t * 1.6;
    final p = Paint();
    for (final b in bits) {
      final x = origin.dx + math.cos(b.angle) * b.speed * secs;
      final y = origin.dy + math.sin(b.angle) * b.speed * secs + 520 * secs * secs; // gravity
      p.color = b.color.withValues(alpha: (1 - t).clamp(0, 1));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(b.spin * secs);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: b.size, height: b.size * 0.55),
          const Radius.circular(1.5),
        ),
        p,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
