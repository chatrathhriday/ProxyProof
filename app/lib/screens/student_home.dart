import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../api.dart';
import '../ibeacon.dart';
import '../main.dart';
import '../permissions.dart';

/// Student phone scans for our beacon, collects RSSI samples, and every ~10 s reports
/// (major, latest minor, samples) to the server, which decides whether to mark.
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
  bool _scanning = false;
  bool _reportedOnce = false;
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
      _status = 'Looking for your class beaconâ€¦';
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
    final cutoff = DateTime.now().subtract(const Duration(seconds: 10));
    _samples.removeWhere((s) => s.at.isBefore(cutoff));
    if (_samples.isEmpty) {
      if (_scanning) setState(() => _status = 'No class beacon nearby.');
      return;
    }
    final latest = _samples.last; // newest token for the beacon we heard most recently
    final rssi = _samples.where((s) => s.major == latest.major).map((s) => s.rssi).toList();
    try {
      final res = await Api.instance.post('/attendance/sighting', {
        'major': latest.major,
        'minor': latest.minor,
        'rssi': rssi.length > 30 ? rssi.sublist(rssi.length - 30) : rssi,
        'deviceUid': Api.instance.deviceUid,
      });
      setState(() {
        _marked = true;
        _course = res['course'] as String?;
        _status = 'You are marked present âœ“';
      });
    } catch (e) {
      setState(() => _status = e is ApiException ? _friendly(e) : 'Network problem: $e');
    }
  }

  String _friendly(ApiException e) => switch (e.status) {
        422 when e.message.contains('far') => 'Move closer to the front â€” signal too weak.',
        422 => 'Beacon code expired, retryingâ€¦',
        403 => 'You are not enrolled in this class.',
        404 => 'This class session has ended.',
        409 => 'This phone was already used for someone else in this class.',
        429 => 'Slow down â€” too many attempts.',
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
        actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () => logout(context))],
      ),
      body: SafeArea(child: Padding(
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
      )),
    );
  }
}
