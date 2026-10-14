// Signature checks for device-bound requests.
// The phone signs the *exact bytes* of a JSON string (`payload`) and sends that string,
// not an object. The server verifies those bytes and only then parses them, so there's
// no "canonical JSON" ambiguity between Dart and Node.
import crypto from 'node:crypto';

/** Parses a base64 X.509 SubjectPublicKeyInfo (what Android's key.public.encoded gives). */
export function parsePublicKey(b64) {
  try {
    const key = crypto.createPublicKey({ key: Buffer.from(b64, 'base64'), format: 'der', type: 'spki' });
    const d = key.asymmetricKeyDetails;
    return key.asymmetricKeyType === 'ec' && d?.namedCurve === 'prime256v1' ? key : null;
  } catch {
    return null;
  }
}

/** Stable device id: first 128 bits of sha256(device public key). */
export const fingerprint = (b64) => crypto.createHash('sha256').update(Buffer.from(b64, 'base64')).digest('hex').slice(0, 32);

/** ECDSA P-256 / SHA-256, DER-encoded signature (Java's default "SHA256withECDSA" output). */
export function verify(publicKeyB64, payload, sigB64) {
  const key = parsePublicKey(publicKeyB64 || '');
  if (!key || typeof payload !== 'string' || typeof sigB64 !== 'string') return false;
  try {
    return crypto.verify('sha256', Buffer.from(payload, 'utf8'), key, Buffer.from(sigB64, 'base64'));
  } catch {
    return false;
  }
}

export const MAX_CLOCK_SKEW_MS = 60_000;
