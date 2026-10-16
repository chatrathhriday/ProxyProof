// College-wide policy (admin-editable) and the audit trail.
import { query, one } from './db.js';

export const DEFAULT_POLICY = { minAttendance: 75, rssiThreshold: -75, presencePct: 80 };
const LIMITS = { minAttendance: [50, 100], rssiThreshold: [-95, -50], presencePct: [50, 100] };

let cache = null;

export async function getPolicy() {
  if (cache) return cache;
  const row = await one("SELECT value FROM settings WHERE key = 'policy'");
  cache = { ...DEFAULT_POLICY, ...(row?.value || {}) };
  return cache;
}

/** Validates and saves; returns the new policy or throws a user-facing message. */
export async function setPolicy(patch) {
  const next = { ...(await getPolicy()) };
  for (const [k, [lo, hi]] of Object.entries(LIMITS)) {
    if (patch[k] === undefined) continue;
    const v = Number(patch[k]);
    if (!Number.isFinite(v) || v < lo || v > hi) throw new Error(`${k} must be between ${lo} and ${hi}`);
    next[k] = Math.round(v);
  }
  await query(
    `INSERT INTO settings (key, value) VALUES ('policy', $1)
     ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value`,
    [JSON.stringify(next)]
  );
  cache = next;
  return next;
}

export const resetPolicyCache = () => {
  cache = null;
};

/** Append one audit record. `target` is a short human-readable label. */
export const audit = (actorId, action, target, details = {}) =>
  query('INSERT INTO audit_log (actor_id, action, target, details) VALUES ($1, $2, $3, $4)', [
    actorId ?? null,
    action,
    target ?? null,
    JSON.stringify(details),
  ]);
