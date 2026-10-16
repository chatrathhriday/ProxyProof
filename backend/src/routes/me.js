import express from 'express';
import { query } from '../db.js';
import { requireRole } from '../auth.js';
import { getPolicy } from '../policy.js';

export const meRouter = express.Router();

// A student's history per course. Only closed sessions count as "held".
// status per session: present | review (teacher hasn't decided) | excused | absent.
// pct = present / (held - excused): an excused class (medical leave, on duty) neither
// helps nor hurts. Pending reviews never inflate the number a student uses to plan.
meRouter.get('/attendance', requireRole('student'), async (req, res) => {
  const policy = await getPolicy();
  const rows = await query(
    `SELECT c.id AS course_id, c.code, c.name, c.schedule, s.id AS session_id, s.started_at, s.closed_at,
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
      courses.set(r.course_id, {
        courseId: r.course_id,
        code: r.code,
        name: r.name,
        schedule: r.schedule || [],
        held: 0,
        present: 0,
        review: 0,
        excused: 0,
        sessions: [],
      });
    const c = courses.get(r.course_id);
    if (!r.session_id) continue; // course with no closed sessions yet
    c.held++;
    if (r.status === 'present') c.present++;
    if (r.status === 'review') c.review++;
    if (r.status === 'excused') c.excused++;
    c.sessions.push({ sessionId: r.session_id, date: r.started_at, status: r.status });
  }
  // Which of my courses have a class running right now (shown as "Live" in the app).
  const live = await query(
    `SELECT s.course_id, s.started_at FROM sessions s JOIN enrollments e ON e.course_id = s.course_id
     WHERE e.student_id = $1 AND s.status = 'active'`,
    [req.user.id]
  );
  res.json(
    [...courses.values()].map((c) => {
      const counted = c.held - c.excused;
      // classes attended in a row, newest first; excused classes don't break a streak
      const ordered = c.sessions.filter((s) => s.status !== 'excused');
      const firstMiss = ordered.findIndex((s) => s.status !== 'present');
      return {
        ...c,
        counted,
        rule: policy.minAttendance,
        pct: counted > 0 ? Math.round((c.present / counted) * 1000) / 10 : null,
        streak: firstMiss === -1 ? ordered.length : firstMiss,
        liveSince: live.find((l) => l.course_id === c.courseId)?.started_at || null,
      };
    })
  );
});

// Latest notices from the teachers of my courses (shown on the Today screen).
meRouter.get('/announcements', requireRole('student'), async (req, res) => {
  res.json(
    await query(
      `SELECT a.id, a.body, a.created_at, c.code, c.name AS course, u.name AS author
       FROM announcements a JOIN courses c ON c.id = a.course_id JOIN users u ON u.id = a.author_id
       JOIN enrollments e ON e.course_id = a.course_id AND e.student_id = $1
       WHERE a.created_at > now() - interval '14 days'
       ORDER BY a.created_at DESC LIMIT 10`,
      [req.user.id]
    )
  );
});
