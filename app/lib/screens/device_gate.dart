import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../api.dart';
import '../device_keys.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/owl.dart';
import 'student_shell.dart';

/// Runs after every student login: makes sure this phone has its Keystore keys and is the
/// student's approved device. First phone is approved automatically; any other phone waits
/// here until an admin approves it.
class DeviceGate extends StatefulWidget {
  const DeviceGate({super.key});

  @override
  State<DeviceGate> createState() => _DeviceGateState();
}

class _DeviceGateState extends State<DeviceGate> {
  String _title = 'Securing this phone';
  String _message = 'Creating your hardware keys…';
  OwlMood _mood = OwlMood.scanning;
  bool _busy = true;
  bool _pending = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _mood = OwlMood.scanning;
    });
    try {
      final keys = await DeviceKeys.ensure();
      final res = await Api.instance.post('/devices/register', {
        'devicePublicKey': keys.device,
        'bioPublicKey': keys.bio,
        'model': await DeviceKeys.model(),
      });
      if (!mounted) return;
      if (res['status'] == 'approved') {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const StudentShell()));
        return;
      }
      setState(() {
        _pending = true;
        _mood = OwlMood.sleeping;
        _title = 'Waiting for approval';
        _message = 'This is a new phone for your account. An admin needs to approve it before you can mark attendance.';
      });
    } on PlatformException catch (e) {
      setState(() {
        _mood = OwlMood.worried;
        _title = e.code == 'NO_BIOMETRICS' ? 'Fingerprint needed' : 'Something went wrong';
        _message = e.code == 'NO_BIOMETRICS'
            ? 'Set up a fingerprint in your phone settings first — ProxyProof uses it to confirm it is really you.'
            : 'Key error: ${e.message}';
      });
    } catch (e) {
      setState(() {
        _mood = OwlMood.worried;
        _title = 'Can\'t reach the server';
        _message = '$e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        actions: [IconButton(icon: const Icon(Icons.logout_rounded), onPressed: () => logout(context))],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              const Spacer(),
              Owl(mood: _mood, size: 170),
              const SizedBox(height: 24),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(_title, key: ValueKey(_title), style: Brand.display(context, size: 26), textAlign: TextAlign.center),
              ),
              const SizedBox(height: 10),
              Text(
                _message,
                textAlign: TextAlign.center,
                style: t.bodyLarge?.copyWith(color: t.bodyLarge?.color?.withValues(alpha: 0.7)),
              ).animate(key: ValueKey(_message)).fadeIn(),
              const Spacer(),
              if (!_busy)
                FilledButton.icon(
                  onPressed: _check,
                  icon: Icon(_pending ? Icons.refresh_rounded : Icons.replay_rounded),
                  label: Text(_pending ? 'Check again' : 'Retry'),
                ).animate().fadeIn().slideY(begin: 0.3),
            ],
          ),
        ),
      ),
    );
  }
}
