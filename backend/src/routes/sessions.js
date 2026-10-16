import express from 'express';
import crypto from 'node:crypto';
import { query, one } from '../db.js';
import { requireRole } from '../auth.js';
import { BEACON_UUID, WINDOW_SECONDS, currentWindow, newSecret, tokenFor } from '../tokens.js';
import { emit } from '../live.js';
import { now } from '../clock.js';
import { sessionReport, persistVerdicts, randomSpotCheckTime } from '../presence.js';
import { audit, getPolicy } from '../policy.js';

export const sessionsRouter = express.Router();

// Load a session the caller is allowed to manage (its organiser, or any admin).
async function ownedSession(req) {
  const s = await one('SELECT * FROM sessions WHERE id = $1', [req.params.id]);
  if (!s) return null;
  if (req.user.role !== 'admin' && s.organiser_id !== req.user.id) return null;
  return s;
}

const publicSession = ({ secret, ...rest }) => rest; // the secret never leaves the server

// When did a beacon device (teacher phone / laptop) last fetch a token for each session?
// The dashboard can't broadcast BLE itself, so it shows whether anything is broadcasting.
const lastBeaconFetch = new Map();
const beaconActive = (id) => now() - (lastBeaconFetch.get(id) || 0) < 25_000;

// Defaults keep the teacher's flow to one tap; thresholds live under "Advanced".
sessionsRouter.post('/', requireRole('organiser'), async (req, res) => {
  const policy = await getPolicy(); // college defaults, overridable per session under 'Advanced'
  const { courseId, rssiThreshold = policy.rssiThreshold, presencePct = policy.presencePct, expectedMinutes = 50 } = req.body || {};
  const course = await one('SELECT * FROM courses WHERE id = $1 AND organiser_id = $2', [courseId, req.user.id]);
  if (!course) return res.status(404).json({ error: 'course not found' });
  const minutes = Math.min(240, Math.max(1, Number(expectedMinutes) || 50));
  const t = now();

  // Random 16-bit short code (iBeacon major), unique among active sessions. Retry on collision.
  for (let attempt = 0; attempt < 5; attempt++) {
    const shortCode = crypto.randomInt(0, 65536);
    try {
      const s = await one(
        `INSERT INTO sessions (course_id, organiser_id, short_code, secret, rssi_threshold, presence_pct, expected_minutes, started_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING *`,
        [course.id, req.user.id, shortCode, newSecret(), rssiThreshold, presencePct, minutes, new Date(t)]
      );
      // One automatic spot check at a random moment the students can't predict.
      await query('INSERT INTO spot_checks (session_id, starts_at, auto) VALUES ($1, $2, true)', [s.id, randomSpotCheckTime(t, minutes)]);
      return res.status(201).json(publicSession(s));
    } catch (e) {
      if (e.code !== '23505') throw e; // unique violation -> try another code
    }
  }
  res.status(503).json({ error: 'could not allocate short code' });
});

sessionsRouter.get('/', requireRole('organiser', 'admin'), async (req, res) => {
  const rows = await query(
    `SELECT s.id, s.course_id, c.code AS course_code, c.name AS course_name, s.short_code, s.status,
            s.started_at, s.closed_at, s.finalized_at,
            (SELECT count(*)::int FROM attendance a WHERE a.session_id = s.id AND a.status = 'present') AS present,
            (SELECT count(*)::int FROM attendance a WHERE a.session_id = s.id AND a.status = 'review') AS review
     FROM sessions s JOIN courses c ON c.id = s.course_id
     WHERE ($1::int IS NULL OR s.organiser_id = $1)
     ORDER BY s.started_at DESC LIMIT 100`,
    [req.user.role === 'admin' ? null : req.user.id]
  );
  res.json(rows);
});

// Roster with presence %, spot-check result and the verdict for every enrolled student.
sessionsRouter.get('/:id', requireRole('organiser', 'admin'), async (req, res) => {
  const s = await ownedSession(req);
  if (!s) return res.status(404).json({ error: 'session not found' });
  const course = await one('SELECT code, name FROM courses WHERE id = $1', [s.course_id]);
  res.json({ ...publicSession(s), course, beaconActive: beaconActive(s.id), ...(await sessionReport(s)) });
});

// Organiser override: mark someone present (phone died) or absent (caught proxying).
// Manual marks carry no device, so they never block a phone's one-student-per-session rule.
sessionsRouter.post('/:id/attendance', requireRole('organiser', 'admin'), async (req, res) => {
  const s = await ownedSession(req);
  if (!s) return res.status(404).json({ error: 'session not found' });
  const { studentId, status } = req.body || {};
  if (!['present', 'absent', 'excused'].includes(status))
    return res.status(400).json({ error: "status must be 'present', 'absent' or 'excused'" });
  const enrolled = await one('SELECT 1 FROM enrollments WHERE course_id = $1 AND student_id = $2', [s.course_id, studentId]);
  if (!enrolled) return res.status(404).json({ error: 'student not enrolled' });
  await setManual(s.id, studentId, status);
  const who = await one('SELECT email FROM users WHERE id = $1', [studentId]);
  const course = await one('SELECT code FROM courses WHERE id = $1', [s.course_id]);
  await audit(req.user.id, `attendance.${status}`, who?.email, { course: course?.code, session: s.id, date: s.started_at });
  emit(s.id, 'roster');
  res.json({ ok: true });
});

const setManual = (sessionId, studentId, status) =>
  query(
    `INSERT INTO attendance (session_id, student_id, status, source) VALUES ($1, $2, $3, 'manual')
     ON CONFLICT (session_id, student_id) DO UPDATE SET status = EXCLUDED.status, source = 'manual'`,
    [sessionId, studentId, status]
  );

// "Spot check now" button: opens a check immediately (in addition to the automatic one).
sessionsRouter.post('/:id/spot-check', requireRole('organiser', 'admin'), async (req, res) => {
  const s = await ownedSession(req);
  if (!s) return res.status(404).json({ error: 'session not found' });
  if (s.status !== 'active') return res.status(409).json({ error: 'session closed' });
  const c = await one('INSERT INTO spot_checks (session_id, starts_at, auto) VALUES ($1, $2, false) RETURNING id, starts_at', [
    s.id,
    new Date(now()),
  ]);
  emit(s.id, 'roster');
  res.status(201).json(c);
});

// End-of-class "Approve all": every case still flagged for review becomes present.
// (The teacher fixes the few they disagree with first, using Mark present/absent.)
sessionsRouter.post('/:id/approve-all', requireRole('organiser', 'admin'), async (req, res) => {
  const s = await ownedSession(req);
  if (!s) return res.status(404).json({ error: 'session not found' });
  if (s.status !== 'closed') return res.status(409).json({ error: 'close the session first' });
  const { attendance } = await sessionReport(s);
  const flagged = attendance.filter((a) => a.verdict === 'review');
  for (const a of flagged) await setManual(s.id, a.student_id, 'present');
  await query('UPDATE sessions SET finalized_at = $2 WHERE id = $1', [s.id, new Date(now())]);
  if (flagged.length) await audit(req.user.id, 'attendance.approve_all', `session ${s.id}`, { count: flagged.length });
  emit(s.id, 'roster');
  res.json({ approved: flagged.length });
});

// CSV for the college register. Cells starting with = + - @ are prefixed with ' so
// a student named "=HYPERLINK(...)" can't run a formula in the teacher's Excel.
sessionsRouter.get('/:id/export.csv', requireRole('organiser', 'admin'), async (req, res) => {
  const s = await ownedSession(req);
  if (!s) return res.status(404).json({ error: 'session not found' });
  const course = await one('SELECT code FROM courses WHERE id = $1', [s.course_id]);
  const cell = (v) => {
    let t = v == null ? '' : v instanceof Date ? v.toISOString() : String(v);
    if (/^[=+\-@]/.test(t)) t = `'${t}`;
    return /[",\n]/.test(t) ? `"${t.replace(/"/g, '""')}"` : t;
  };
  const { attendance } = await sessionReport(s);
  const rows = attendance.map((r) =>
    [r.name, r.email, r.verdict, r.source || '', Math.round(r.coverage * 100), r.spot, r.reason, r.first_seen, r.last_seen]
      .map(cell)
      .join(',')
  );
  const date = new Date(s.started_at).toISOString().slice(0, 10);
  res
    .type('text/csv')
    .attachment(`${course.code}-${date}-session${s.id}.csv`)
    .send(['name,email,status,source,in_range_pct,spot_check,reason,first_seen,last_seen', ...rows].join('\n') + '\n');
});

// The organiser app polls this every few seconds and re-broadcasts major/minor.
// Only the derived 16-bit token goes over the wire, never the secret.
sessionsRouter.get('/:id/beacon', requireRole('organiser'), async (req, res) => {
  const s = await ownedSession(req);
  if (!s) return res.status(404).json({ error: 'session not found' });
  if (s.status !== 'active') return res.status(409).json({ error: 'session closed' });
  const t = now();
  const window = currentWindow(t);
  if (!beaconActive(s.id)) emit(s.id, 'roster'); // dashboard: "broadcasting" turns on
  lastBeaconFetch.set(s.id, t);
  res.json({
    uuid: BEACON_UUID,
    major: s.short_code,
    minor: tokenFor(s.secret, window),
    window,
    msUntilNext: (window + 1) * WINDOW_SECONDS * 1000 - t,
  });
});

sessionsRouter.post('/:id/close', requireRole('organiser', 'admin'), async (req, res) => {
  const s = await ownedSession(req);
  if (!s) return res.status(404).json({ error: 'session not found' });
  const closed = await one(
    "UPDATE sessions SET status = 'closed', closed_at = $2 WHERE id = $1 AND status = 'active' RETURNING *",
    [s.id, new Date(now())]
  );
  if (closed) await persistVerdicts(closed);
  emit(s.id, 'roster');
  res.json(publicSession(closed || s));
});
