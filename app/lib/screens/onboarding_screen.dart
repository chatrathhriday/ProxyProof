import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';
import '../widgets/owl.dart';
import '../widgets/ui.dart';
import 'login_screen.dart';

/// Three-slide welcome, shown once on first launch.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  static Future<bool> seen() async => (await SharedPreferences.getInstance()).getBool('onboarded') ?? false;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _Slide {
  const _Slide(this.mood, this.title, this.body, this.icon);
  final OwlMood mood;
  final String title, body;
  final IconData icon;
}

const _slides = [
  _Slide(
    OwlMood.scanning,
    'Walk in. You\'re marked.',
    'Your teacher\'s phone broadcasts a Bluetooth beacon that changes every 10 seconds. Your phone hears it and marks you — no roll call, no QR codes.',
    Icons.sensors,
  ),
  _Slide(
    OwlMood.alert,
    'Only you can mark you.',
    'Your phone keeps a key in its secure chip and your fingerprint unlocks it. A friend with your password — or your phone — can\'t mark you.',
    Icons.fingerprint,
  ),
  _Slide(
    OwlMood.happy,
    'Know where you stand.',
    'See every class, your streaks and your percentage — and exactly how many classes you can skip and still stay above 75%.',
    Icons.insights,
  ),
];

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _page = PageController();
  int _i = 0;

  Future<void> _finish() async {
    HapticFeedback.mediumImpact();
    await (await SharedPreferences.getInstance()).setBool('onboarded', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = _i == _slides.length - 1;
    return Scaffold(
      backgroundColor: Brand.navy,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: const Text('Skip', style: TextStyle(color: Colors.white70)),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _page,
                itemCount: _slides.length,
                onPageChanged: (i) {
                  HapticFeedback.selectionClick();
                  setState(() => _i = i);
                },
                itemBuilder: (context, i) {
                  final s = _slides[i];
                  // Parallax: the owl drifts slower than the text as you swipe.
                  return AnimatedBuilder(
                    animation: _page,
                    builder: (context, _) {
                      final offset = _page.hasClients && _page.position.haveDimensions ? (_page.page ?? 0) - i : 0.0;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 30),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Transform.translate(
                              offset: Offset(offset * 120, 0),
                              child: Radar(size: 250, child: Owl(mood: s.mood, size: 160)),
                            ),
                            const SizedBox(height: 18),
                            Opacity(
                              opacity: (1 - offset.abs()).clamp(0, 1),
                              child: Column(
                                children: [
                                  Icon(s.icon, color: Brand.gold, size: 30),
                                  const SizedBox(height: 12),
                                  Text(
                                    s.title,
                                    textAlign: TextAlign.center,
                                    style: Brand.display(context, size: 30, color: Colors.white),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    s.body,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.72),
                                      fontSize: 15.5,
                                      height: 1.45,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _slides.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _i ? 26 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _i ? Brand.gold : Colors.white24,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Brand.gold, foregroundColor: Brand.navy),
                onPressed: last
                    ? _finish
                    : () => _page.nextPage(duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(last ? 'Get started' : 'Next', key: ValueKey(last)),
                ),
              ),
            ),
          ],
        ).animate().fadeIn(duration: 400.ms),
      ),
    );
  }
}
