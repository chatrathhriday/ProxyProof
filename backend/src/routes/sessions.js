import express from 'express';
import crypto from 'node:crypto';
import { query, one } from '../db.js';
import { requireRole } from '../auth.js';
import { BEACON_UUID, WINDOW_SECONDS, currentWindow, newSecret, tokenFor } from '../tokens.js';
import { emit } from '../live.js';

export const sessionsRouter = express.Router();

// Load a session the caller is allowed to manage (its organiser, or any admin).
async function ownedSession(req) {
  const s = await one('SELECT * FROM sessions WHERE id = $1', [req.params.id]);
  if (!s) return null;
  if (req.user.role !== 'admin' && s.organiser_id !== req.user.id) return null;
  return s;
}

const publicSession = ({ secret, ...rest }) => rest; // the secret never leaves the server

sessionsRouter.post('/', requireRole('organiser'), async (req, res) => {
  const { courseId, rssiThreshold = -75, presencePct = 80 } = req.body || {};
  const course = await one('SELECT * FROM courses WHERE id = $1 AND organiser_id = $2', [courseId, req.user.id]);
  if (!course) return res.status(404).json({ error: 'course not found' });

  // Random 16-bit short code (iBeacon major), unique among active sessions. Retry on collision.
  for (let attempt = 0; attempt < 5; attempt++) {
    const shortCode = crypto.randomInt(0, 65536);
    try {
      const s = await one(
        `INSERT INTO sessions (course_id, organiser_id, short_code, secret, rssi_threshold, presence_pct)
         VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
        [course.id, req.user.id, shortCode, newSecret(), rssiThreshold, presencePct]
      );
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
            s.started_at, s.closed_at,
            (SELECT count(*)::int FROM attendance a WHERE a.session_id = s.id AND a.status = 'present') AS present
     FROM sessions s JOIN courses c ON c.id = s.course_id
     WHERE ($1::int IS NULL OR s.organiser_id = $1)
     ORDER BY s.started_at DESC LIMIT 100`,
    [req.user.role === 'admin' ? null : req.user.id]
  );
  res.json(rows);
});

sessionsRouter.get('/:id', requireRole('organiser', 'admin'), async (req, res) => {
  const s = await ownedSession(req);
  if (!s) return res.status(404).json({ error: 'session not found' });
  const course = await one('SELECT code, name FROM courses WHERE id = $1', [s.course_id]);
  res.json({ ...publicSession(s), course, attendance: await roster(s) });
});

// Every enrolled student with their mark (if any) and presence stats from sightings.
function roster(s) {
  return query(
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
  );
}

// Organiser override: mark someone present (phone died) or absent (caught proxying).
// Manual marks carry no device, so they never block a phone's one-student-per-session rule.
sessionsRouter.post('/:id/attendance', requireRole('organiser', 'admin'), async (req, res) => {
  const s = await ownedSession(req);
  if (!s) return res.status(404).json({ error: 'session not found' });
  const { studentId, status } = req.body || {};
  if (!['present', 'absent'].includes(status)) return res.status(400).json({ error: "status must be 'present' or 'absent'" });
  const enrolled = await one('SELECT 1 FROM enrollments WHERE course_id = $1 AND student_id = $2', [s.course_id, studentId]);
  if (!enrolled) return res.status(404).json({ error: 'student not enrolled' });
  await query(
    `INSERT INTO attendance (session_id, student_id, status, source) VALUES ($1, $2, $3, 'manual')
     ON CONFLICT (session_id, student_id) DO UPDATE SET status = EXCLUDED.status, source = 'manual'`,
    [s.id, studentId, status]
  );
  emit(s.id, 'roster');
  res.json({ ok: true });
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
  const rows = (await roster(s)).map((r) =>
    [r.name, r.email, r.status || 'absent', r.source || '', r.first_seen, r.last_seen, r.sightings].map(cell).join(',')
  );
  const date = new Date(s.started_at).toISOString().slice(0, 10);
  res
    .type('text/csv')
    .attachment(`${course.code}-${date}-session${s.id}.csv`)
    .send(['name,email,status,source,first_seen,last_seen,sightings', ...rows].join('\n') + '\n');
});

// The organiser app polls this every few seconds and re-broadcasts major/minor.
// Only the derived 16-bit token goes over the wire, never the secret.
sessionsRouter.get('/:id/beacon', requireRole('organiser'), async (req, res) => {
  const s = await ownedSession(req);
  if (!s) return res.status(404).json({ error: 'session not found' });
  if (s.status !== 'active') return res.status(409).json({ error: 'session closed' });
  const now = Date.now();
  const window = currentWindow(now);
  res.json({
    uuid: BEACON_UUID,
    major: s.short_code,
    minor: tokenFor(s.secret, window),
    window,
    msUntilNext: (window + 1) * WINDOW_SECONDS * 1000 - now,
  });
});

sessionsRouter.post('/:id/close', requireRole('organiser', 'admin'), async (req, res) => {
  const s = await ownedSession(req);
  if (!s) return res.status(404).json({ error: 'session not found' });
  const closed = await one(
    "UPDATE sessions SET status = 'closed', closed_at = now() WHERE id = $1 AND status = 'active' RETURNING *",
    [s.id]
  );
  emit(s.id, 'roster');
  res.json(publicSession(closed || s));
});
