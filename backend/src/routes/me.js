import express from 'express';
import { query } from '../db.js';
import { requireRole } from '../auth.js';

export const meRouter = express.Router();

// A student's history per course. Only closed sessions count as "held".
// status per session: present | review (teacher hasn't decided) | absent.
// pct counts only confirmed presents, so a pending review never inflates the number
// a student uses to decide whether they can skip a class.
meRouter.get('/attendance', requireRole('student'), async (req, res) => {
  const rows = await query(
    `SELECT c.id AS course_id, c.code, c.name, s.id AS session_id, s.started_at, s.closed_at,
            COALESCE(a.status, 'absent') AS status
     FROM enrollments e
     JOIN courses c ON c.id = e.course_id
     LEFT JOIN sessions s ON s.course_id = c.id AND s.status = 'closed'
     LEFT JOIN attendance a ON a.session_id = s.id AND a.student_id = e.student_id
     WHERE e.student_id = $1
     ORDER BY c.code, s.started_at DESC`,
    [req.user.id]
  );

  const courses = new Map();
  for (const r of rows) {
    if (!courses.has(r.course_id))
      courses.set(r.course_id, { courseId: r.course_id, code: r.code, name: r.name, held: 0, present: 0, review: 0, sessions: [] });
    const c = courses.get(r.course_id);
    if (!r.session_id) continue; // course with no closed sessions yet
    c.held++;
    if (r.status === 'present') c.present++;
    if (r.status === 'review') c.review++;
    c.sessions.push({ sessionId: r.session_id, date: r.started_at, status: r.status });
  }
  // Which of my courses have a class running right now (shown as "Live" in the app).
  const live = await query(
    `SELECT s.course_id, s.started_at FROM sessions s JOIN enrollments e ON e.course_id = s.course_id
     WHERE e.student_id = $1 AND s.status = 'active'`,
    [req.user.id]
  );
  res.json(
    [...courses.values()].map((c) => ({
      ...c,
      pct: c.held ? Math.round((c.present / c.held) * 1000) / 10 : null,
      liveSince: live.find((l) => l.course_id === c.courseId)?.started_at || null,
    }))
  );
});
