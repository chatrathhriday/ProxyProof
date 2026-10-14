import 'package:permission_handler/permission_handler.dart';

/// Asks for everything BLE needs. Returns a human-readable problem, or null if all good.
Future<String?> ensureBlePermissions({required bool advertise}) async {
  final perms = [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    if (advertise) Permission.bluetoothAdvertise,
    Permission.locationWhenInUse, // beacon scans are location-sensitive on Android
  ];
  final results = await perms.request();
  final denied = results.entries.where((e) => !e.value.isGranted).map((e) => e.key).toList();
  if (denied.isNotEmpty) {
    if (results.values.any((s) => s.isPermanentlyDenied)) await openAppSettings();
    return 'Permission needed: ${denied.join(', ')}';
  }
  if (!await Permission.location.serviceStatus.isEnabled) {
    return 'Turn on Location — Android needs it for Bluetooth scanning.';
  }
  return null;
}
