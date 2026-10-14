// In-memory sliding-window limiter. Why it matters: the token is only 16 bits, so
// without a limit an attacker could brute-force 65,536 guesses. At 10 tries/min/device
// and a ~30 s validity window, the odds of a lucky guess are ~5 in 65,536 per window.
// (In-memory is fine for one Render instance; a multi-instance deploy would use Redis.)
const hits = new Map();

export function allow(key, limit = 10, windowMs = 60_000, now = Date.now()) {
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
