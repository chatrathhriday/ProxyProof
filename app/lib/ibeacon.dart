import 'dart:typed_data';

/// iBeacon layout inside a BLE manufacturer-specific record (company id 0x004C, Apple):
///   [0x02, 0x15] [16-byte UUID] [major: 2 bytes BE] [minor: 2 bytes BE] [tx power @1 m: int8]
/// Using the standard format means iPhones (Core Location) can detect it too.
class IBeacon {
  static const appleCompanyId = 0x004C;
  static const _prefix = [0x02, 0x15];
  static const measuredPower = -59; // typical RSSI at 1 m, used by distance estimators

  static List<int> uuidBytes(String uuid) {
    final hex = uuid.replaceAll('-', '');
    return List.generate(16, (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16));
  }

  /// Manufacturer data payload (without the company id, which the BLE API takes separately).
  static Uint8List encode(String uuid, int major, int minor) => Uint8List.fromList([
    ..._prefix,
    ...uuidBytes(uuid),
    major >> 8,
    major & 0xff,
    minor >> 8,
    minor & 0xff,
    measuredPower & 0xff,
  ]);

  /// Bytes a scan filter can match on: prefix + our UUID, so we ignore every other beacon.
  static List<int> filterPrefix(String uuid) => [..._prefix, ...uuidBytes(uuid)];

  /// Returns (major, minor) if [data] is an iBeacon with [uuid], else null.
  static ({int major, int minor})? decode(List<int> data, String uuid) {
    if (data.length < 23 || data[0] != 0x02 || data[1] != 0x15) return null;
    final want = uuidBytes(uuid);
    for (var i = 0; i < 16; i++) {
      if (data[2 + i] != want[i]) return null;
    }
    return (major: (data[18] << 8) | data[19], minor: (data[20] << 8) | data[21]);
  }
}

/// Must match BEACON_UUID in backend/src/tokens.js.
const beaconUuid = 'b55d5a77-aef8-4366-832a-9747001afeeb';
