import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../api.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/owl.dart';

/// OAuth "Web application" client id: Google puts it in the ID token's `aud`, and the server
/// checks it. A public identifier, not a secret.
const _googleServerClientId = '37429262055-7u3mm2sj9takv871no63dpeikab9rj4m.apps.googleusercontent.com';
const studentDomain = 'vitstudent.ac.in';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.notice});

  /// Optional message shown on arrival, e.g. "Your session expired".
  final String? notice;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static bool _googleReady = false;
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _staff = false;
  bool _busy = false;
  late String? _error = widget.notice;
  OwlMood _mood = OwlMood.idle;

  Future<void> _done() async {
    setState(() => _mood = OwlMood.happy);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeRouter()));
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _mood = OwlMood.scanning;
    });
    try {
      await action();
      await _done();
    } on GoogleSignInException catch (e) {
      setState(() {
        _mood = OwlMood.idle;
        if (e.code != GoogleSignInExceptionCode.canceled) {
          _error = 'Google sign-in failed: ${e.description ?? e.code.name}';
        }
      });
    } catch (e) {
      setState(() {
        _mood = OwlMood.worried;
        _error = e is ApiException ? e.message : 'Can\'t reach the server. Check your internet and try again.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() => _run(() async {
    final g = GoogleSignIn.instance;
    if (!_googleReady) {
      await g.initialize(serverClientId: _googleServerClientId, hostedDomain: studentDomain);
      _googleReady = true;
    }
    await g.signOut(); // always show the account picker, so the right account is chosen
    final account = await g.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) throw ApiException(0, 'Google did not return an ID token');
    await Api.instance.googleLogin(idToken);
  });

  Future<void> _signInWithPassword() => _run(() => Api.instance.login(_email.text.trim(), _password.text));

  Future<void> _serverDialog() async {
    final c = TextEditingController(text: Api.instance.baseUrl);
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Server'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(labelText: 'API URL'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save')),
        ],
      ),
    );
    if (url != null && url.isNotEmpty) await Api.instance.setBaseUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Brand.navy,
      body: Stack(
        children: [
          // decorative glow
          Positioned(
            top: -120,
            right: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [Brand.gold.withValues(alpha: 0.25), Colors.transparent]),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: Column(
                    children: [
                      const SizedBox(height: 28),
                      Owl(
                        mood: _mood,
                        size: 150,
                      ).animate().fadeIn(duration: 500.ms).scale(begin: const Offset(0.85, 0.85)),
                      const SizedBox(height: 10),
                      Text(
                        'ProxyProof',
                        style: Brand.display(context, size: 38, color: Colors.white),
                      ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.3),
                      const SizedBox(height: 6),
                      Text(
                        'Attendance that can\'t be faked.',
                        style: TextStyle(
                          color: Brand.goldSoft.withValues(alpha: 0.9),
                          fontSize: 15,
                          letterSpacing: 0.3,
                        ),
                      ).animate().fadeIn(delay: 300.ms),
                      const SizedBox(height: 32),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Students', style: Brand.display(context, size: 22)),
                            const SizedBox(height: 4),
                            Text(
                              'Sign in with your @$studentDomain Google account.',
                              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.65)),
                            ),
                            const SizedBox(height: 16),
                            _GoogleButton(onPressed: _busy ? null : _google, busy: _busy && !_staff),
                            const SizedBox(height: 18),
                            if (_error != null)
                              Container(
                                padding: const EdgeInsets.all(12),
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: Brand.absent.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(_error!, style: const TextStyle(color: Brand.absent)),
                              ).animate().shake(hz: 3, duration: 400.ms),
                            Row(
                              children: [
                                const Expanded(child: Divider()),
                                TextButton(
                                  onPressed: () => setState(() => _staff = !_staff),
                                  child: Text(_staff ? 'Hide staff login' : 'Faculty & demo login'),
                                ),
                                const Expanded(child: Divider()),
                              ],
                            ),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                              child: !_staff
                                  ? const SizedBox(width: double.infinity)
                                  : Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        const SizedBox(height: 8),
                                        TextField(
                                          controller: _email,
                                          keyboardType: TextInputType.emailAddress,
                                          decoration: const InputDecoration(
                                            labelText: 'Email',
                                            prefixIcon: Icon(Icons.alternate_email),
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        TextField(
                                          controller: _password,
                                          obscureText: true,
                                          onSubmitted: (_) => _signInWithPassword(),
                                          decoration: const InputDecoration(
                                            labelText: 'Password',
                                            prefixIcon: Icon(Icons.lock_outline),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        FilledButton(
                                          onPressed: _busy ? null : _signInWithPassword,
                                          child: _busy && _staff
                                              ? const SizedBox.square(
                                                  dimension: 22,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2.4,
                                                    color: Colors.white,
                                                  ),
                                                )
                                              : const Text('Sign in'),
                                        ),
                                      ],
                                    ),
                            ),
                            const SizedBox(height: 12),
                            TextButton.icon(
                              onPressed: _serverDialog,
                              icon: const Icon(Icons.dns_outlined, size: 16),
                              label: const Text('Server settings'),
                              style: TextButton.styleFrom(foregroundColor: scheme.onSurface.withValues(alpha: 0.5)),
                            ),
                          ],
                        ),
                      ).animate().slideY(begin: 0.25, duration: 500.ms, curve: Curves.easeOutCubic).fadeIn(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.onPressed, required this.busy});
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFDADCE0)),
            boxShadow: Brand.softShadow(context),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
              else
                const _GoogleG(),
              const SizedBox(width: 12),
              Text(
                busy ? 'Signing in…' : 'Continue with Google',
                style: const TextStyle(color: Color(0xFF1F1F1F), fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The four-colour "G", drawn so we don't ship an image asset.
class _GoogleG extends StatelessWidget {
  const _GoogleG();

  @override
  Widget build(BuildContext context) => SizedBox.square(dimension: 22, child: CustomPaint(painter: _GPainter()));
}

class _GPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final r = Rect.fromLTWH(2, 2, s.width - 4, s.height - 4);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.width * 0.18;
    const seg = [
      (Color(0xFF4285F4), -0.25, 0.55),
      (Color(0xFF34A853), 0.3, 0.6),
      (Color(0xFFFBBC05), 0.9, 0.35),
      (Color(0xFFEA4335), 1.25, 0.6),
    ];
    for (final (c, start, sweep) in seg) {
      canvas.drawArc(r, start * 3.14159, sweep * 3.14159, false, p..color = c);
    }
    canvas.drawLine(
      Offset(s.width / 2, s.height / 2),
      Offset(s.width - 2, s.height / 2),
      p..color = const Color(0xFF4285F4),
    );
  }

  @override
  bool shouldRepaint(_) => false;
}
