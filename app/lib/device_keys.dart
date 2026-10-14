import 'package:flutter/services.dart';

/// Dart side of DeviceKeys.kt: two hardware-backed Keystore keys.
///  - device key: signs every request silently (proves *which phone*)
///  - bio key: unlocks only with a fingerprint, dies if new biometrics are enrolled
///    (proves *which person*)
class DeviceKeys {
  static const _ch = MethodChannel('proxyproof/keys');

  /// Creates the keys on first use; returns base64 SPKI public keys.
  static Future<({String device, String bio})> ensure() async {
    final m = await _ch.invokeMapMethod<String, String>('ensureKeys');
    return (device: m!['devicePublicKey']!, bio: m['bioPublicKey']!);
  }

  static Future<String> signDevice(String payload) async =>
      (await _ch.invokeMethod<String>('signDevice', {'payload': payload}))!;

  /// Shows the system fingerprint prompt. Throws PlatformException with code
  /// BIO_CANCELLED, KEY_INVALIDATED (biometrics changed) or KEY_ERROR.
  static Future<String> signBiometric(String payload, String reason) async =>
      (await _ch.invokeMethod<String>('signBiometric', {'payload': payload, 'reason': reason}))!;

  /// Deletes both keys. Next ensure() makes a new pair = a "new device" needing approval.
  static Future<void> reset() => _ch.invokeMethod('resetKeys');

  static Future<String> model() async => (await _ch.invokeMethod<String>('model')) ?? 'unknown';
}
