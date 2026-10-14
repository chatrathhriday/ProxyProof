// A software stand-in for a phone's two Keystore keys, for tests and demo scripts.
// Real phones keep these in hardware; here they're plain Node keys.
import crypto from 'node:crypto';

const spkiB64 = (key) => key.export({ type: 'spki', format: 'der' }).toString('base64');

export function makeDevice(model = 'Simulated phone') {
  const device = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const bio = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  let lastTs = 0;
  return {
    registration: { devicePublicKey: spkiB64(device.publicKey), bioPublicKey: spkiB64(bio.publicKey), model },
    /** Builds a signed sighting body. `fingerprint: true` adds the biometric-key signature. */
    sighting({ major, minor, rssi }, { fingerprint = false, ts } = {}) {
      lastTs = ts ?? Math.max(Date.now(), lastTs + 1); // strictly increasing, like the app
      const payload = JSON.stringify({ major, minor, rssi, ts: lastTs });
      const sign = (k) => crypto.sign('sha256', Buffer.from(payload), k).toString('base64');
      return { payload, sig: sign(device.privateKey), ...(fingerprint && { bioSig: sign(bio.privateKey) }) };
    },
  };
}
