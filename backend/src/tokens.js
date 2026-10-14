// Rotating BLE token = first 16 bits of HMAC-SHA256(session_secret, window),
// window = floor(unix_seconds / 10). The window is encoded as an 8-byte big-endian
// integer so the organiser app and server can never disagree on the bytes.
import crypto from 'node:crypto';
import { now } from './clock.js';

export const WINDOW_SECONDS = 10;
// Fixed for the whole app; scanners filter on it so they ignore every other beacon.
export const BEACON_UUID = 'b55d5a77-aef8-4366-832a-9747001afeeb';

export const currentWindow = (nowMs = now()) => Math.floor(nowMs / 1000 / WINDOW_SECONDS);

export function tokenFor(secretHex, window) {
  const msg = Buffer.alloc(8);
  msg.writeBigUInt64BE(BigInt(window));
  const mac = crypto.createHmac('sha256', Buffer.from(secretHex, 'hex')).update(msg).digest();
  return mac.readUInt16BE(0);
}

// Accept current window ±1 to absorb clock skew and scan latency (~30 s total validity).
// Returns the matching window, or null.
export function matchWindow(secretHex, token, nowMs = now()) {
  const w = currentWindow(nowMs);
  for (const cand of [w, w - 1, w + 1]) {
    if (tokenFor(secretHex, cand) === token) return cand;
  }
  return null;
}

export const newSecret = () => crypto.randomBytes(32).toString('hex');
