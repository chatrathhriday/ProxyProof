// A software stand-in for a phone's two Keystore keys, for tests and demo scripts.
// Real phones keep these in hardware; here they're plain Node keys.
import crypto from 'node:crypto';

const spkiB64 = (key) => key.export({ type: 'spki', format: 'der' }).toString('base64');

export function makeDevice(model = 'Simulated phone') {
  const device = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const bio = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  let lastTs = 0;
  const signed = (data, { fingerprint = false, ts, clock = Date.now } = {}) => {
    lastTs = ts ?? Math.max(clock(), lastTs + 1); // strictly increasing, like the app
    const payload = JSON.stringify({ ...data, ts: lastTs });
    const sign = (k) => crypto.sign('sha256', Buffer.from(payload), k).toString('base64');
    return { payload, sig: sign(device.privateKey), ...(fingerprint && { bioSig: sign(bio.privateKey) }) };
  };
  return {
    registration: { devicePublicKey: spkiB64(device.publicKey), bioPublicKey: spkiB64(bio.publicKey), model },
    /** Signed sighting body. `fingerprint: true` adds the biometric-key signature. */
    sighting: ({ major, minor, rssi }, opts) => signed({ major, minor, rssi }, opts),
    /** Signed spot-check answer (always needs the fingerprint). */
    spotCheck: (spotCheckId, opts) => signed({ spotCheckId }, { fingerprint: true, ...opts }),
  };
}
