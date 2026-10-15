import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';

import '../api.dart';
import '../ibeacon.dart';
import '../permissions.dart';
import '../theme.dart';
import '../widgets/owl.dart';
import '../widgets/ui.dart';
import 'summary_screen.dart';

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
  bool _spotOpen = false;

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
          _spotOpen = s['spotChecks']?['open'] == true;
        });
      }
    } catch (_) {}
  }

  Future<void> _spotCheck() async {
    try {
      await Api.instance.post('/sessions/${widget.sessionId}/spot-check');
      setState(() => _spotOpen = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Spot check sent — students have 20 s to confirm with their fingerprint.')),
        );
      }
    } catch (e) {
      setState(() => _error = '$e');
    }
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
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => SummaryScreen(sessionId: widget.sessionId, title: widget.title),
          ),
        );
      }
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
    final on = _minor != null;
    return Scaffold(
      backgroundColor: Brand.navy,
      appBar: AppBar(
        foregroundColor: Colors.white,
        title: Text(widget.title, style: Brand.display(context, size: 22, color: Colors.white)),
        actions: [
          if (on)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Pill('ON AIR', color: Brand.gold, pulse: true),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: Radar(
                  active: on,
                  size: 280,
                  child: Owl(mood: on ? (_spotOpen ? OwlMood.alert : OwlMood.scanning) : OwlMood.sleeping, size: 160),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                on ? 'Broadcasting' : 'Starting beacon…',
                textAlign: TextAlign.center,
                style: Brand.display(context, size: 24, color: Colors.white),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: _present.toDouble()),
                    duration: const Duration(milliseconds: 500),
                    builder: (_, v, _) =>
                        Text('${v.round()}', style: Brand.display(context, size: 64, color: Brand.goldSoft)),
                  ),
                  Text(' / $_total', style: Brand.display(context, size: 28, color: Colors.white54)),
                ],
              ),
              const Text(
                'students marked',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 14),
              if (_major != null)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        'code $_major · token $_minor · rotates every 10 s',
                        key: ValueKey(_minor),
                        style: const TextStyle(color: Colors.white60, fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                    ),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFFF8A7A)),
                  ),
                ),
              const Spacer(),
              const Text(
                'Keep this screen open during class.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Brand.goldSoft,
                  side: BorderSide(color: Brand.gold.withValues(alpha: 0.6)),
                ),
                onPressed: !on || _spotOpen ? null : _spotCheck,
                icon: const Icon(Icons.fingerprint),
                label: Text(_spotOpen ? 'Spot check running…' : 'Spot check now'),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Brand.gold, foregroundColor: Brand.navy),
                onPressed: _closing ? null : _close,
                icon: const Icon(Icons.flag_rounded),
                label: const Text('Close session & review'),
              ),
            ].animate(interval: 40.ms).fadeIn(duration: 300.ms),
          ),
        ),
      ),
    );
  }
}
