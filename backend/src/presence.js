// Presence over the whole class, spot checks and the final verdict per student.
//
// Coverage: the session is cut into 30 s buckets from start to end (or now). A student is
// "in range" for a bucket if at least one accepted sighting landed in it. Phones report
// every ~10 s, so a present student fills every bucket even if a report or two is lost.
import { query, one } from './db.js';
import { now } from './clock.js';

export const BUCKET_MS = 30_000;
export const SPOT_WINDOW_MS = 120_000; // make-up: the check stays deliverable for 2 min
export const SPOT_RESPONSE_MS = 20_000; // time to answer once the phone has received it
const GRACE_MS = 3_000; // network slack on the answer
const ABSENT_BELOW = 0.25; // marked, but in range for under a quarter of the class

const ms = (d) => (d ? new Date(d).getTime() : null);

/** Random time between 20% and 70% of the expected class length: hard to predict, never at the very start or end. */
export function randomSpotCheckTime(startMs, expectedMinutes) {
  const span = expectedMinutes * 60_000;
  return new Date(startMs + span * (0.2 + Math.random() * 0.5));
}

/**
 * Called on every accepted sighting. If a spot check is open and this student hasn't got
 * it yet, it is delivered now (their 20 s start now). Returns what the phone must answer.
 */
export async function deliverSpotCheck(sessionId, studentId, t = now()) {
  const open = await query(
    `SELECT sc.id, r.deadline, r.responded_at FROM spot_checks sc
     LEFT JOIN spot_check_results r ON r.spot_check_id = sc.id AND r.student_id = $2
     WHERE sc.session_id = $1 AND sc.starts_at <= $3 AND sc.starts_at + interval '${SPOT_WINDOW_MS / 1000} seconds' >= $3
     ORDER BY sc.starts_at`,
    [sessionId, studentId, new Date(t)]
  );
  for (const c of open) {
    if (c.responded_at) continue;
    if (!c.deadline) {
      const deadline = new Date(t + SPOT_RESPONSE_MS);
      await query(
        'INSERT INTO spot_check_results (spot_check_id, student_id, delivered_at, deadline) VALUES ($1, $2, $3, $4) ON CONFLICT DO NOTHING',
        [c.id, studentId, new Date(t), deadline]
      );
      return { id: c.id, deadline: deadline.toISOString(), secondsLeft: SPOT_RESPONSE_MS / 1000 };
    }
    if (ms(c.deadline) > t) return { id: c.id, deadline: new Date(c.deadline).toISOString(), secondsLeft: Math.ceil((ms(c.deadline) - t) / 1000) };
  }
  return null;
}

/** Records a fingerprint-signed answer. Returns an error string, or null on success. */
export async function answerSpotCheck(spotCheckId, studentId, t = now()) {
  const r = await one('SELECT * FROM spot_check_results WHERE spot_check_id = $1 AND student_id = $2', [spotCheckId, studentId]);
  if (!r) return 'no spot check was sent to you';
  if (r.responded_at) return null; // idempotent
  if (t > ms(r.deadline) + GRACE_MS) return 'too late: the 20 seconds are over';
  await query('UPDATE spot_check_results SET responded_at = $3 WHERE spot_check_id = $1 AND student_id = $2', [spotCheckId, studentId, new Date(t)]);
  return null;
}

/** One student's spot-check outcome across all checks that have opened. */
function spotStatus(checks, results, studentId, t, end) {
  let status = 'none';
  for (const c of checks) {
    const start = ms(c.starts_at);
    if (start > Math.min(t, end)) continue; // not opened yet, or scheduled after the class ended
    const r = results.find((x) => x.spot_check_id === c.id && x.student_id === studentId);
    let s;
    if (r?.responded_at) s = 'passed';
    else if (r) s = t > ms(r.deadline) + GRACE_MS ? 'failed' : 'pending';
    else s = t > start + SPOT_WINDOW_MS ? 'missed' : 'pending';
    // worst result wins: failed/missed > pending > passed > none
    const rank = { none: 0, passed: 1, pending: 2, missed: 3, failed: 3 };
    if (rank[s] > rank[status]) status = s;
  }
  return status;
}

/** Decides present / review / absent and says why, so the teacher only reads unclear cases. */
export function verdict({ status, source, coverage, spot }, presencePct) {
  if (!status) return { verdict: 'absent', reason: 'never detected' };
  if (source === 'manual') return { verdict: status, reason: 'set by teacher' };
  const pct = Math.round(coverage * 100);
  if (coverage < ABSENT_BELOW) return { verdict: 'absent', reason: `in range only ${pct}%` };
  if (spot === 'failed') return { verdict: 'review', reason: `did not answer spot check (in range ${pct}%)` };
  if (spot === 'missed') return { verdict: 'review', reason: `out of range during spot check (in range ${pct}%)` };
  if (coverage >= presencePct / 100) return { verdict: 'present', reason: `in range ${pct}%` };
  return { verdict: 'review', reason: `in range ${pct}% (needs ${presencePct}%)` };
}

/** Full roster with coverage, spot checks and verdicts, plus the summary counts. */
export async function sessionReport(s, t = now()) {
  const start = ms(s.started_at);
  const end = s.closed_at ? ms(s.closed_at) : t;
  // Rounded, not ceil: a last bucket only a few seconds old can't be filled yet and
  // shouldn't drag someone who was there all along below 100%.
  const totalBuckets = Math.max(1, Math.round((end - start) / BUCKET_MS));

  const [rows, buckets, checks, results] = await Promise.all([
    query(
      `SELECT u.id AS student_id, u.name, u.email, a.status, a.source, a.first_seen,
              sg.last_seen, sg.last_rssi, COALESCE(sg.sightings, 0)::int AS sightings
       FROM enrollments e JOIN users u ON u.id = e.student_id
       LEFT JOIN attendance a ON a.student_id = u.id AND a.session_id = $1
       LEFT JOIN LATERAL (
         SELECT max(created_at) AS last_seen, count(*) AS sightings,
                (array_agg(rssi_median ORDER BY created_at DESC))[1] AS last_rssi
         FROM sightings WHERE session_id = $1 AND student_id = u.id
       ) sg ON true
       WHERE e.course_id = $2 ORDER BY u.name`,
      [s.id, s.course_id]
    ),
    query(
      `SELECT student_id, count(DISTINCT floor(extract(epoch FROM created_at - $2::timestamptz) / ${BUCKET_MS / 1000}))::int AS n
       FROM sightings WHERE session_id = $1 AND created_at <= $3 GROUP BY student_id`,
      [s.id, s.started_at, new Date(end)]
    ),
    query('SELECT * FROM spot_checks WHERE session_id = $1 ORDER BY starts_at', [s.id]),
    query(
      'SELECT r.* FROM spot_check_results r JOIN spot_checks sc ON sc.id = r.spot_check_id WHERE sc.session_id = $1',
      [s.id]
    ),
  ]);

  const counts = { present: 0, review: 0, absent: 0, excused: 0 };
  const attendance = rows.map((r) => {
    const n = buckets.find((b) => b.student_id === r.student_id)?.n || 0;
    const coverage = Math.min(1, n / totalBuckets);
    const spot = r.status ? spotStatus(checks, results, r.student_id, t, end) : 'none';
    const v = verdict({ ...r, coverage, spot }, s.presence_pct);
    counts[v.verdict]++;
    return { ...r, coverage, spot, ...v };
  });

  const nextCheck = checks.find((c) => ms(c.starts_at) > t);
  const openCheck = checks.find((c) => ms(c.starts_at) <= t && t <= ms(c.starts_at) + SPOT_WINDOW_MS);
  return {
    attendance,
    counts,
    spotChecks: { total: checks.filter((c) => ms(c.starts_at) <= end).length, open: !!openCheck, next: nextCheck?.starts_at || null },
  };
}

/** On close: store each automatic verdict, so history and % don't need recomputing. */
export async function persistVerdicts(s) {
  const { attendance } = await sessionReport(s);
  for (const a of attendance) {
    if (a.status && a.source !== 'manual' && a.status !== a.verdict)
      await query('UPDATE attendance SET status = $3 WHERE session_id = $1 AND student_id = $2', [s.id, a.student_id, a.verdict]);
  }
}
