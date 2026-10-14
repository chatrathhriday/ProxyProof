import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';

import '../api.dart';
import '../ibeacon.dart';
import '../permissions.dart';

/// Organiser's phone acts as the beacon. Every 10 s window it fetches the new token from
/// the server (it never knows the secret) and restarts the advertisement with it.
class BroadcastScreen extends StatefulWidget {
  const BroadcastScreen({super.key, required this.sessionId, required this.title});
  final int sessionId;
  final String title;

  @override
  State<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends State<BroadcastScreen> {
  final _ble = FlutterBlePeripheral();
  Timer? _tokenTimer;
  Timer? _rosterTimer;
  int? _major;
  int? _minor;
  int _present = 0;
  int _total = 0;
  String? _error;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _begin();
  }

  Future<void> _begin() async {
    final problem = await ensureBlePermissions(advertise: true);
    if (problem != null) return setState(() => _error = problem);
    await _refreshToken();
    _refreshRoster();
    _rosterTimer = Timer.periodic(const Duration(seconds: 5), (_) => _refreshRoster());
  }

  Future<void> _refreshToken() async {
    var nextIn = const Duration(seconds: 2); // retry quickly on failure
    try {
      final b = await Api.instance.get('/sessions/${widget.sessionId}/beacon');
      final minor = b['minor'] as int;
      if (minor != _minor) await _advertise(b['uuid'] as String, b['major'] as int, minor);
      setState(() {
        _major = b['major'] as int;
        _minor = minor;
        _error = null;
      });
      // Wake just after the window flips so the beacon is never more than ~0.3 s stale.
      nextIn = Duration(milliseconds: (b['msUntilNext'] as int) + 300);
    } catch (e) {
      setState(() => _error = '$e');
      if (e is ApiException && e.status == 409) return; // session closed elsewhere
    }
    if (mounted) _tokenTimer = Timer(nextIn, _refreshToken);
  }

  Future<void> _advertise(String uuid, int major, int minor) async {
    if (await _ble.isAdvertising) await _ble.stop();
    await _ble.start(
      advertiseData: AdvertiseDataCore(
        manufacturerId: IBeacon.appleCompanyId,
        manufacturerData: IBeacon.encode(uuid, major, minor),
      ),
      androidSettings: const AndroidAdvertiseSettings(
        advertiseSettings: AdvertiseSettings(
          advertiseMode: AdvertiseMode.advertiseModeLowLatency, // ~10 ads/s: fast detection
          txPowerLevel: AdvertiseTxPower.advertiseTxPowerHigh,
          connectable: false,
          timeout: 0,
        ),
      ),
    );
  }

  Future<void> _refreshRoster() async {
    try {
      final s = await Api.instance.get('/sessions/${widget.sessionId}');
      final list = s['attendance'] as List;
      if (mounted) {
        setState(() {
          _total = list.length;
          _present = list.where((a) => a['status'] == 'present').length;
        });
      }
    } catch (_) {}
  }

  Future<void> _close() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Close session?'),
        content: const Text('Students can no longer be marked after this.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Close')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _closing = true);
    try {
      await Api.instance.post('/sessions/${widget.sessionId}/close');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _closing = false;
        _error = '$e';
      });
    }
  }

  @override
  void dispose() {
    _tokenTimer?.cancel();
    _rosterTimer?.cancel();
    _ble.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(
                Icons.sensors,
                size: 96,
                color: _minor == null ? Colors.grey : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                _minor == null ? 'Starting beacon…' : 'Broadcasting',
                textAlign: TextAlign.center,
                style: t.headlineSmall,
              ),
              const SizedBox(height: 32),
              Text('$_present / $_total', textAlign: TextAlign.center, style: t.displayMedium),
              Text('students present', textAlign: TextAlign.center, style: t.bodyLarge),
              const SizedBox(height: 24),
              if (_major != null)
                Text(
                  'Code $_major · token $_minor (rotates every 10 s)',
                  textAlign: TextAlign.center,
                  style: t.bodySmall,
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              const Spacer(),
              const Text('Keep this screen open during class.', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _closing ? null : _close,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Close session'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
