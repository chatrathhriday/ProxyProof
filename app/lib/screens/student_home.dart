import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../api.dart';
import '../device_keys.dart';
import '../ibeacon.dart';
import '../main.dart';
import '../permissions.dart';
import 'device_gate.dart';
import 'history_screen.dart';

/// Student phone scans for our beacon, collects RSSI samples, and every ~10 s sends a
/// signed report (major, latest minor, samples, timestamp). The first report in a class
/// also carries a fingerprint-key signature; the server decides whether to mark.
class StudentHome extends StatefulWidget {
  const StudentHome({super.key});

  @override
  State<StudentHome> createState() => _StudentHomeState();
}

class _Sample {
  _Sample(this.major, this.minor, this.rssi) : at = DateTime.now();
  final int major, minor, rssi;
  final DateTime at;
}

class _StudentHomeState extends State<StudentHome> {
  StreamSubscription<List<ScanResult>>? _sub;
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
  int? _lastRssi;

  Future<void> _start() async {
    final problem = await ensureBlePermissions(advertise: false);
    if (problem != null) return setState(() => _status = problem);
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
        _lastRssi = r.rssi;
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
    setState(() {
      _scanning = true;
      _status = 'Looking for your class beacon…';
    });
  }

  Future<void> _stop() async {
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
      final body = {'payload': payload, 'sig': await DeviceKeys.signDevice(payload)};
      if (!_checkedIn.contains(latest.major)) {
        setState(() => _status = 'Class found — confirm with your fingerprint');
        body['bioSig'] = await DeviceKeys.signBiometric(payload, 'Mark your attendance');
      }
      final res = await Api.instance.post('/attendance/sighting', body);
      _checkedIn.add(latest.major);
      setState(() {
        _marked = true;
        _course = res['course'] as String?;
        if (!_spotBusy) _status = 'You are marked present ✓';
      });
      final spot = res['spotCheck'];
      if (spot != null) _answerSpotCheck(spot['id'] as int, spot['secondsLeft'] as int);
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
      setState(() => _status = _friendly(e));
    } catch (e) {
      setState(() => _status = 'Network problem: $e');
    } finally {
      _reporting = false;
    }
  }

  /// Signed payloads need strictly increasing timestamps (the server's replay guard).
  int _nextTs() => _lastTs = DateTime.now().millisecondsSinceEpoch.clamp(_lastTs + 1, 1 << 53);

  /// Random spot check from the server: the owner must touch the fingerprint sensor within
  /// 20 s. The answer is signed by the fingerprint key, so only the enrolled finger works.
  Future<void> _answerSpotCheck(int id, int secondsLeft) async {
    if (_spotBusy || _spotAnswered.contains(id)) return;
    _spotBusy = true;
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
    _reportTimer?.cancel();
    _sub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Hi, ${Api.instance.user?['name'] ?? ''}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'My attendance',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HistoryScreen())),
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: () => logout(context)),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(
                _marked ? Icons.check_circle : (_scanning ? Icons.bluetooth_searching : Icons.bluetooth),
                size: 96,
                color: _marked ? Colors.green : (_scanning ? scheme.primary : Colors.grey),
              ),
              const SizedBox(height: 16),
              Text(_status, textAlign: TextAlign.center, style: t.titleLarge),
              if (_course != null) Text(_course!, textAlign: TextAlign.center, style: t.bodyLarge),
              if (_scanning && _lastRssi != null)
                Text('Signal: $_lastRssi dBm', textAlign: TextAlign.center, style: t.bodySmall),
              const Spacer(),
              FilledButton.icon(
                onPressed: _scanning ? _stop : _start,
                icon: Icon(_scanning ? Icons.stop : Icons.play_arrow),
                label: Text(_scanning ? 'Stop' : 'Start attendance'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
