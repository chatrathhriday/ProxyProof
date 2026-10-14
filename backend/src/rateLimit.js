// In-memory sliding-window limiter. Why it matters: the token is only 16 bits, so
// without a limit an attacker could brute-force 65,536 guesses. At 10 tries/min/device
// with 3 valid tokens at any moment (window ±1), ~5 guesses per 30 s succeed with ~1 in 4,400 odds.
// (In-memory is fine for one Render instance; a multi-instance deploy would use Redis.)
import { now as clockNow } from './clock.js';

const hits = new Map();

export function allow(key, limit = 10, windowMs = 60_000, now = clockNow()) {
  const recent = (hits.get(key) || []).filter((t) => now - t < windowMs);
  if (recent.length >= limit) {
    hits.set(key, recent);
    return false;
  }
  recent.push(now);
  hits.set(key, recent);
  return true;
}

export const resetLimits = () => hits.clear();
