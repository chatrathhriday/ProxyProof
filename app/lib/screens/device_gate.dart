import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../device_keys.dart';
import '../main.dart';
import 'student_home.dart';

/// Runs after every student login: makes sure this phone has its Keystore keys and is the
/// student's approved device. First phone is approved automatically; any other phone waits
/// here until an admin approves it.
class DeviceGate extends StatefulWidget {
  const DeviceGate({super.key});

  @override
  State<DeviceGate> createState() => _DeviceGateState();
}

class _DeviceGateState extends State<DeviceGate> {
  String _message = 'Securing this phone…';
  bool _busy = true;
  bool _pending = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => _busy = true);
    try {
      final keys = await DeviceKeys.ensure();
      final res = await Api.instance.post('/devices/register', {
        'devicePublicKey': keys.device,
        'bioPublicKey': keys.bio,
        'model': await DeviceKeys.model(),
      });
      if (!mounted) return;
      if (res['status'] == 'approved') {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const StudentHome()));
        return;
      }
      setState(() {
        _pending = true;
        _message =
            'This is a new phone for your account.\n'
            'An admin needs to approve it before you can mark attendance.';
      });
    } on PlatformException catch (e) {
      setState(
        () => _message = e.code == 'NO_BIOMETRICS'
            ? 'Set up a fingerprint in your phone settings first — ProxyProof uses it to confirm it is really you.'
            : 'Key error: ${e.message}',
      );
    } catch (e) {
      setState(() => _message = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device check'),
        actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () => logout(context))],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(_pending ? Icons.hourglass_top : Icons.phonelink_lock, size: 96),
              const SizedBox(height: 16),
              Text(_message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              if (!_busy) FilledButton(onPressed: _check, child: Text(_pending ? 'Check again' : 'Retry')),
            ],
          ),
        ),
      ),
    );
  }
}
