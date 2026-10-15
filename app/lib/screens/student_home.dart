import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../api.dart';
import '../background.dart';
import '../device_keys.dart';
import '../ibeacon.dart';
import '../main.dart';
import '../permissions.dart';
import '../theme.dart';
import '../widgets/owl.dart';
import '../widgets/ui.dart';
import 'device_gate.dart';

/// Student phone scans for our beacon, collects RSSI samples, and every ~10 s sends a
/// signed report (major, latest minor, samples, timestamp). The first report in a class
/// also carries a fingerprint-key signature; the server decides whether to mark.
/// Keeps running with the screen locked via a foreground service (see background.dart).
class StudentHome extends StatefulWidget {
  const StudentHome({super.key, this.onOpenClasses});
  final VoidCallback? onOpenClasses;

  @override
  State<StudentHome> createState() => _StudentHomeState();
}

class _Sample {
  _Sample(this.major, this.minor, this.rssi) : at = DateTime.now();
  final int major, minor, rssi;
  final DateTime at;
}

class _StudentHomeState extends State<StudentHome> with WidgetsBindingObserver {
  StreamSubscription<List<ScanResult>>? _sub;
  // Fingerprint prompts can only show while the app is on screen. In the background we
  // notify + vibrate and keep what's pending until the student opens the app.
  bool _inForeground = true;
  ({int id, DateTime deadline})? _pendingSpot;
  Timer? _reportTimer;
  final _samples = <_Sample>[];
  final _checkedIn = <int>{}; // session codes (majors) where the fingerprint was accepted
  bool _scanning = false;
  bool _reportedOnce = false;
  bool _reporting = false; // one report at a time (the fingerprint prompt can take a while)
  bool _spotBusy = false; // spot-check prompt on screen
  final _spotAnswered = <int>{};
  int _lastTs = 0;
  String _status = 'Tap Start when you are in class.';
  String? _course;
  bool _marked = false;
  // Live signal in its own notifier: ~10 updates/s repaint one label, not the whole screen.
  final _rssi = ValueNotifier<int?>(null);
  bool _problem = false; // owl looks worried
  List _live = const []; // my courses with a class running now

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadLive();
  }

  Future<void> _loadLive() async {
    final cached = Api.instance.cached('/me/attendance');
    if (cached is List) setState(() => _live = cached.where((c) => c['liveSince'] != null).toList());
    try {
      final fresh = await Api.instance.get('/me/attendance') as List;
      if (mounted) setState(() => _live = fresh.where((c) => c['liveSince'] != null).toList());
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _inForeground = state == AppLifecycleState.resumed;
    if (!_inForeground || !_scanning) return;
    // Back on screen: answer a waiting spot check, or do the fingerprint check-in now.
    final spot = _pendingSpot;
    if (spot != null && spot.deadline.isAfter(DateTime.now())) {
      _answerSpotCheck(spot.id, spot.deadline.difference(DateTime.now()).inSeconds);
    } else {
      _pendingSpot = null;
      _report();
    }
  }

  Future<void> _start() async {
    final problem = await ensureBlePermissions(advertise: false);
    if (problem != null) {
      return setState(() {
        _status = problem;
        _problem = true;
      });
    }
    await Background.requestPermissions();
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (_) {
        return setState(() => _status = 'Turn on Bluetooth.');
      }
    }

    _sub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final data = r.advertisementData.manufacturerData[IBeacon.appleCompanyId];
        final b = data == null ? null : IBeacon.decode(data, beaconUuid);
        if (b == null) continue;
        _samples.add(_Sample(b.major, b.minor, r.rssi));
        _rssi.value = r.rssi;
      }
      // First report as soon as we have a few samples, so marking feels instant.
      if (!_reportedOnce && _samples.length >= 3) {
        _reportedOnce = true;
        _report();
      }
    });

    // Filter in the Bluetooth chip by Apple id + iBeacon prefix + our UUID: we only ever
    // wake for our own beacon. continuousUpdates gives repeated RSSI readings per device.
    await FlutterBluePlus.startScan(
      withMsd: [MsdFilter(IBeacon.appleCompanyId, data: IBeacon.filterPrefix(beaconUuid))],
      continuousUpdates: true,
      androidUsesFineLocation: true,
      androidScanMode: AndroidScanMode.lowLatency,
    );
    _reportTimer = Timer.periodic(const Duration(seconds: 10), (_) => _report());
    await Background.start();
    setState(() {
      _scanning = true;
      _problem = false;
      _status = 'Looking for your class beacon…';
    });
  }

  Future<void> _stop() async {
    await Background.stop();
    _pendingSpot = null;
    _reportTimer?.cancel();
    await _sub?.cancel();
    await FlutterBluePlus.stopScan();
    _samples.clear();
    _reportedOnce = false;
    setState(() {
      _scanning = false;
      _status = 'Stopped.';
    });
  }

  Future<void> _report() async {
    if (_reporting) return;
    final cutoff = DateTime.now().subtract(const Duration(seconds: 10));
    _samples.removeWhere((s) => s.at.isBefore(cutoff));
    if (_samples.isEmpty) {
      if (_scanning) setState(() => _status = 'No class beacon nearby.');
      return;
    }
    _reporting = true;
    final latest = _samples.last; // newest token for the beacon we heard most recently
    final rssi = _samples.where((s) => s.major == latest.major).map((s) => s.rssi).toList();
    // The exact string we sign is the string we send; the server verifies these bytes.
    final payload = jsonEncode({
      'major': latest.major,
      'minor': latest.minor,
      'rssi': rssi.length > 30 ? rssi.sublist(rssi.length - 30) : rssi,
      'ts': _nextTs(),
    });
    try {
      final firstMark = !_checkedIn.contains(latest.major);
      if (firstMark && !_inForeground) {
        // The check-in needs a fingerprint, which needs the app on screen.
        setState(() => _status = 'Class found — confirm with your fingerprint');
        await Background.update('Class found — tap to check in', 'Open ProxyProof and confirm with your fingerprint.');
        return;
      }
      final body = {'payload': payload, 'sig': await DeviceKeys.signDevice(payload)};
      if (firstMark) {
        setState(() => _status = 'Class found — confirm with your fingerprint');
        body['bioSig'] = await DeviceKeys.signBiometric(payload, 'Mark your attendance');
      }
      final res = await Api.instance.post('/attendance/sighting', body);
      _checkedIn.add(latest.major);
      setState(() {
        _marked = true;
        _problem = false;
        _course = res['course'] as String?;
        if (!_spotBusy) _status = 'You are marked present ✓';
      });
      if (firstMark) _notifyNormal();
      final spot = res['spotCheck'];
      if (spot != null) _onSpotCheck(spot['id'] as int, spot['secondsLeft'] as int);
    } on PlatformException catch (e) {
      if (e.code == 'KEY_INVALIDATED') return _deviceChanged();
      setState(
        () => _status = e.code == 'BIO_CANCELLED'
            ? 'Fingerprint needed to mark attendance. Will ask again in 10 s.'
            : 'Key error: ${e.message}',
      );
    } on ApiException catch (e) {
      if (e.code == 'BIO_REQUIRED') _checkedIn.remove(latest.major); // ask again next round
      if (e.code == 'DEVICE_NOT_APPROVED' || e.code == 'BAD_SIGNATURE') return _deviceChanged();
      setState(() {
        _status = _friendly(e);
        _problem = true;
      });
    } catch (e) {
      setState(() {
        _status = 'Network problem. Retrying…';
        _problem = true;
      });
    } finally {
      _reporting = false;
    }
  }

  /// Signed payloads need strictly increasing timestamps (the server's replay guard).
  int _nextTs() => _lastTs = DateTime.now().millisecondsSinceEpoch.clamp(_lastTs + 1, 1 << 53);

  Future<void> _notifyNormal() => Background.update(
    'ProxyProof is taking attendance',
    _course == null ? 'You can lock your phone.' : 'Marked present · $_course. You can lock your phone.',
  );

  /// A spot check arrived. On screen: prompt now. In the background: buzz + wake the screen
  /// + change the notification, and prompt as soon as the student opens the app.
  void _onSpotCheck(int id, int secondsLeft) {
    if (_spotAnswered.contains(id)) return;
    if (_inForeground) {
      _answerSpotCheck(id, secondsLeft);
      return;
    }
    if (_pendingSpot?.id == id) return; // already notified (the reply repeats it until answered)
    _pendingSpot = (id: id, deadline: DateTime.now().add(Duration(seconds: secondsLeft)));
    setState(() => _status = 'Spot check! Open the app within $secondsLeft s');
    Background.update(
      'Spot check! Tap within $secondsLeft s',
      'Confirm with your fingerprint that you are still in class.',
    );
    FlutterForegroundTask.wakeUpScreen();
  }

  /// Random spot check from the server: the owner must touch the fingerprint sensor within
  /// 20 s. The answer is signed by the fingerprint key, so only the enrolled finger works.
  Future<void> _answerSpotCheck(int id, int secondsLeft) async {
    if (_spotBusy || _spotAnswered.contains(id)) return;
    _spotBusy = true;
    _pendingSpot = null;
    HapticFeedback.heavyImpact();
    setState(() => _status = 'Spot check! Confirm within $secondsLeft s');
    try {
      final payload = jsonEncode({'spotCheckId': id, 'ts': _nextTs()});
      final body = {
        'payload': payload,
        'sig': await DeviceKeys.signDevice(payload),
        'bioSig': await DeviceKeys.signBiometric(payload, 'Spot check — confirm you are still in class'),
      };
      await Api.instance.post('/attendance/spot-check', body);
      _spotAnswered.add(id);
      setState(() => _status = 'Spot check passed ✓');
    } on PlatformException catch (e) {
      if (e.code == 'KEY_INVALIDATED') return _deviceChanged();
      setState(() => _status = 'Spot check not confirmed. It will ask again if there is still time.');
    } on ApiException catch (e) {
      if (e.status == 422) _spotAnswered.add(id); // too late; stop asking
      setState(() => _status = 'Spot check: ${e.message}');
    } catch (e) {
      setState(() => _status = 'Network problem: $e');
    } finally {
      _spotBusy = false;
      _notifyNormal();
    }
  }

  /// Keys no longer valid (new fingerprint enrolled) or device revoked: start over with
  /// fresh keys, which the server treats as a new phone needing admin approval.
  Future<void> _deviceChanged() async {
    await _stop();
    await DeviceKeys.reset();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const DeviceGate()));
  }

  String _friendly(ApiException e) => switch (e.status) {
    422 when e.message.contains('far') => 'Move closer to the front — signal too weak.',
    422 => 'Beacon code expired, retrying…',
    428 => 'Fingerprint needed — will ask again.',
    403 => 'You are not enrolled in this class.',
    404 => 'This class session has ended.',
    409 => 'This phone was already used for someone else in this class.',
    429 => 'Slow down — too many attempts.',
    _ => e.message,
  };

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reportTimer?.cancel();
    _sub?.cancel();
    FlutterBluePlus.stopScan();
    Background.stop();
    _rssi.dispose();
    super.dispose();
  }

  OwlMood get _mood {
    if (_spotBusy || _pendingSpot != null) return OwlMood.alert;
    if (_problem) return OwlMood.worried;
    if (_marked) return OwlMood.happy;
    if (_scanning) return OwlMood.scanning;
    return OwlMood.sleeping;
  }

  String get _firstName => '${Api.instance.user?['name'] ?? ''}'.split(' ').first;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = t.bodyMedium?.color?.withValues(alpha: 0.65);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _loadLive,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_greeting(), style: t.bodyMedium?.copyWith(color: muted)),
                        Text(_firstName, style: Brand.display(context, size: 30)),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Log out',
                    icon: const Icon(Icons.logout_rounded),
                    onPressed: () => logout(context),
                  ),
                ],
              ).animate().fadeIn(duration: 300.ms),
              const SizedBox(height: 18),
              HeroPanel(
                child: Column(
                  children: [
                    Radar(
                      active: _scanning && !_marked,
                      size: 230,
                      child: Owl(mood: _mood, size: 150),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      transitionBuilder: (c, a) => FadeTransition(
                        opacity: a,
                        child: SlideTransition(
                          position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a),
                          child: c,
                        ),
                      ),
                      child: Text(
                        _status,
                        key: ValueKey(_status),
                        textAlign: TextAlign.center,
                        style: Brand.display(context, size: 22, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_course != null) Pill(_course!, color: Brand.goldSoft, icon: Icons.class_outlined),
                    if (_scanning)
                      ValueListenableBuilder<int?>(
                        valueListenable: _rssi,
                        builder: (_, v, _) => v == null
                            ? const SizedBox(height: 22)
                            : Padding(padding: const EdgeInsets.only(top: 10), child: _SignalBars(v)),
                      ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _scanning ? Colors.white.withValues(alpha: 0.12) : Brand.gold,
                          foregroundColor: _scanning ? Colors.white : Brand.navy,
                        ),
                        onPressed: _scanning ? _stop : _start,
                        icon: Icon(_scanning ? Icons.stop_rounded : Icons.fingerprint),
                        label: Text(_scanning ? 'Stop' : 'Start attendance'),
                      ),
                    ),
                    if (_scanning)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          'You can lock your phone — attendance keeps running.',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12.5),
                        ),
                      ),
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.06),
              SectionTitle(
                'Live now',
                trailing: TextButton(onPressed: widget.onOpenClasses, child: const Text('All classes')),
              ),
              if (_live.isEmpty)
                _InfoCard(
                  icon: Icons.nights_stay_outlined,
                  text: 'None of your classes are running right now. When one starts, it shows up here.',
                )
              else
                ...[
                  for (final c in _live)
                    _InfoCard(
                      icon: Icons.sensors,
                      title: '${c['code']} · ${c['name']}',
                      text: 'Class in progress — tap Start attendance when you are in the room.',
                      trailing: const Pill('LIVE', color: Brand.absent, pulse: true),
                    ),
                ].staggered(),
              const SizedBox(height: 8),
              _InfoCard(
                icon: Icons.verified_user_outlined,
                title: 'How you are checked',
                text:
                    'Your phone hears the class beacon, signs each report with a key locked in its secure chip, '
                    'and your fingerprint confirms it is you. Stay in range for most of the class.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening');
  }
}

/// Four bars + dBm, coloured by whether the signal clears the default threshold.
class _SignalBars extends StatelessWidget {
  const _SignalBars(this.rssi);
  final int rssi;

  @override
  Widget build(BuildContext context) {
    final level = rssi >= -55 ? 4 : (rssi >= -65 ? 3 : (rssi >= -75 ? 2 : 1));
    final color = rssi >= -75 ? Brand.goldSoft : const Color(0xFFFF8A7A);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 1; i <= 4; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 5,
            height: 5.0 + i * 4,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: i <= level ? color : Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        const SizedBox(width: 8),
        Text(
          '$rssi dBm',
          style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.text, this.title, this.trailing});
  final IconData icon;
  final String text;
  final String? title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Brand.gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Brand.gold, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null) Text(title!, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    if (title != null) const SizedBox(height: 3),
                    Text(text, style: t.bodyMedium?.copyWith(color: t.bodyMedium?.color?.withValues(alpha: 0.7))),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}
