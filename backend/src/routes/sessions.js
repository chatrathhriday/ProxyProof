import express from 'express';
import crypto from 'node:crypto';
import { query, one } from '../db.js';
import { requireRole } from '../auth.js';
import { BEACON_UUID, WINDOW_SECONDS, currentWindow, newSecret, tokenFor } from '../tokens.js';

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
  const attendance = await query(
    `SELECT u.id AS student_id, u.name, u.email, a.status, a.source, a.first_seen
     FROM enrollments e JOIN users u ON u.id = e.student_id
     LEFT JOIN attendance a ON a.student_id = u.id AND a.session_id = $1
     WHERE e.course_id = $2 ORDER BY u.name`,
    [s.id, s.course_id]
  );
  res.json({ ...publicSession(s), attendance });
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
  res.json(publicSession(closed || s));
});
