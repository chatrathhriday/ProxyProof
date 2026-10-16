import express from 'express';
import { query, one } from '../db.js';
import { requireAuth, requireRole } from '../auth.js';
import { audit, getPolicy } from '../policy.js';

export const coursesRouter = express.Router();

coursesRouter.post('/', requireRole('organiser'), async (req, res) => {
  const code = String(req.body?.code || '').trim().toUpperCase();
  const name = String(req.body?.name || '').trim();
  if (!code || !name) return res.status(400).json({ error: 'code and name required' });
  const exists = await one('SELECT 1 FROM courses WHERE code = $1', [code]);
  if (exists) return res.status(409).json({ error: 'course code taken' });
  res.status(201).json(
    await one('INSERT INTO courses (code, name, organiser_id) VALUES ($1, $2, $3) RETURNING *', [code, name, req.user.id])
  );
});

// Organisers see the courses they teach; students see the ones they're enrolled in.
coursesRouter.get('/', requireAuth, async (req, res) => {
  if (req.user.role === 'student') {
    return res.json(
      await query(
        `SELECT c.* FROM courses c JOIN enrollments e ON e.course_id = c.id
         WHERE e.student_id = $1 ORDER BY c.code`,
        [req.user.id]
      )
    );
  }
  const rows = await query(
    `SELECT c.*, (SELECT count(*)::int FROM enrollments e WHERE e.course_id = c.id) AS students
     FROM courses c WHERE ($1::int IS NULL OR c.organiser_id = $1) ORDER BY c.code`,
    [req.user.role === 'admin' ? null : req.user.id]
  );
  res.json(rows);
});

// Enroll students by email. Existing accounts are enrolled now; emails that haven't signed in
// yet become invites, claimed automatically on that student's first Google sign-in.
coursesRouter.post('/:id/enroll', requireRole('organiser'), async (req, res) => {
  const course = await one('SELECT * FROM courses WHERE id = $1 AND organiser_id = $2', [req.params.id, req.user.id]);
  if (!course) return res.status(404).json({ error: 'course not found' });
  const emails = [...new Set((req.body?.emails || []).map((e) => String(e).toLowerCase().trim()))];
  const enrolled = [];
  const invited = [];
  const notFound = []; // not an email address at all
  const suggestions = []; // probable typos of an existing student's email
  for (const email of emails) {
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      notFound.push(email);
      continue;
    }
    const student = await one("SELECT id FROM users WHERE email = $1 AND role = 'student'", [email]);
    if (student) {
      await query('INSERT INTO enrollments VALUES ($1, $2) ON CONFLICT DO NOTHING', [course.id, student.id]);
      enrolled.push(email);
    } else {
      // Typo guard: "lakshyadaga2026@" vs the real "lakshya.daga2026@" are different addresses,
      // so an invite would never be claimed. If an existing student matches once dots are
      // ignored, suggest them instead of silently inviting the misspelling.
      const [local, domain] = email.split('@');
      const near = await one(
        "SELECT email FROM users WHERE role = 'student' AND split_part(email, '@', 2) = $1 AND replace(split_part(email, '@', 1), '.', '') = $2",
        [domain, local.replace(/\./g, '')]
      );
      if (near) {
        suggestions.push({ typed: email, existing: near.email });
        continue;
      }
      await query('INSERT INTO enrollment_invites VALUES ($1, $2) ON CONFLICT DO NOTHING', [course.id, email]);
      invited.push(email);
    }
  }
  res.json({ enrolled, invited, notFound, suggestions });
});

// Course roster with each student's attendance over closed sessions and their phone status.
coursesRouter.get('/:id/students', requireRole('organiser', 'admin'), async (req, res) => {
  const course = await one('SELECT * FROM courses WHERE id = $1', [req.params.id]);
  if (!course || (req.user.role !== 'admin' && course.organiser_id !== req.user.id))
    return res.status(404).json({ error: 'course not found' });
  const held = (await one("SELECT count(*)::int AS n FROM sessions WHERE course_id = $1 AND status = 'closed'", [course.id])).n;
  const students = await query(
    `SELECT u.id, u.email, u.name,
            (SELECT count(*)::int FROM attendance a JOIN sessions s ON s.id = a.session_id
             WHERE a.student_id = u.id AND s.course_id = $1 AND s.status = 'closed' AND a.status = 'present') AS present,
            (SELECT count(*)::int FROM attendance a JOIN sessions s ON s.id = a.session_id
             WHERE a.student_id = u.id AND s.course_id = $1 AND s.status = 'closed' AND a.status = 'excused') AS excused,
            EXISTS (SELECT 1 FROM devices d WHERE d.user_id = u.id AND d.status = 'approved') AS has_device
     FROM users u JOIN enrollments e ON e.student_id = u.id
     WHERE e.course_id = $1 ORDER BY u.name`,
    [course.id]
  );
  const invites = (await query('SELECT email FROM enrollment_invites WHERE course_id = $1 ORDER BY email', [course.id])).map(
    (r) => r.email
  );
  res.json({ course, held, students, invites, rule: (await getPolicy()).minAttendance });
});

coursesRouter.post('/:id/unenroll', requireRole('organiser'), async (req, res) => {
  const course = await one('SELECT * FROM courses WHERE id = $1 AND organiser_id = $2', [req.params.id, req.user.id]);
  if (!course) return res.status(404).json({ error: 'course not found' });
  if (req.body?.email) await query('DELETE FROM enrollment_invites WHERE course_id = $1 AND email = $2', [course.id, req.body.email]);
  else await query('DELETE FROM enrollments WHERE course_id = $1 AND student_id = $2', [course.id, req.body?.studentId]);
  res.json({ ok: true });
});

// The course's teacher (or an admin) — shared guard for the course tools below.
async function myCourse(req) {
  const c = await one('SELECT * FROM courses WHERE id = $1', [req.params.id]);
  return c && (req.user.role === 'admin' || c.organiser_id === req.user.id) ? c : null;
}

// Weekly timetable: [{ d: 1..7, s: "HH:MM", e: "HH:MM", room }].
coursesRouter.put('/:id/schedule', requireRole('organiser', 'admin'), async (req, res) => {
  const course = await myCourse(req);
  if (!course) return res.status(404).json({ error: 'course not found' });
  const hhmm = /^([01]\d|2[0-3]):[0-5]\d$/;
  const slots = (Array.isArray(req.body?.schedule) ? req.body.schedule : []).map((s) => ({
    d: Number(s.d),
    s: String(s.s),
    e: String(s.e),
    room: String(s.room || '').slice(0, 40),
  }));
  if (slots.length > 20 || slots.some((s) => !(s.d >= 1 && s.d <= 7) || !hhmm.test(s.s) || !hhmm.test(s.e) || s.e <= s.s))
    return res.status(400).json({ error: 'each slot needs a day 1-7 and start < end as HH:MM' });
  slots.sort((a, b) => a.d - b.d || a.s.localeCompare(b.s));
  await query('UPDATE courses SET schedule = $2 WHERE id = $1', [course.id, JSON.stringify(slots)]);
  res.json({ schedule: slots });
});

// Past classes with their outcome, oldest first, for history lists and the trend chart.
coursesRouter.get('/:id/sessions', requireRole('organiser', 'admin'), async (req, res) => {
  const course = await myCourse(req);
  if (!course) return res.status(404).json({ error: 'course not found' });
  const rows = await query(
    `SELECT s.id, s.started_at, s.closed_at, s.finalized_at,
            (SELECT count(*)::int FROM enrollments e WHERE e.course_id = s.course_id) AS enrolled,
            count(a.*) FILTER (WHERE a.status = 'present')::int AS present,
            count(a.*) FILTER (WHERE a.status = 'review')::int AS review,
            count(a.*) FILTER (WHERE a.status = 'excused')::int AS excused
     FROM sessions s LEFT JOIN attendance a ON a.session_id = s.id
     WHERE s.course_id = $1 AND s.status = 'closed'
     GROUP BY s.id ORDER BY s.started_at`,
    [course.id]
  );
  res.json(rows.map((r) => ({ ...r, absent: Math.max(0, r.enrolled - r.present - r.review - r.excused) })));
});

// Announcements: short notices students see on their Today screen.
coursesRouter.get('/:id/announcements', requireAuth, async (req, res) => {
  const ok =
    (await myCourse(req)) ||
    (await one('SELECT 1 FROM enrollments WHERE course_id = $1 AND student_id = $2', [req.params.id, req.user.id]));
  if (!ok) return res.status(404).json({ error: 'course not found' });
  res.json(
    await query(
      `SELECT a.id, a.body, a.created_at, u.name AS author FROM announcements a JOIN users u ON u.id = a.author_id
       WHERE a.course_id = $1 ORDER BY a.created_at DESC LIMIT 30`,
      [req.params.id]
    )
  );
});

coursesRouter.post('/:id/announcements', requireRole('organiser', 'admin'), async (req, res) => {
  const course = await myCourse(req);
  if (!course) return res.status(404).json({ error: 'course not found' });
  const body = String(req.body?.body || '').trim();
  if (!body || body.length > 500) return res.status(400).json({ error: 'write 1-500 characters' });
  const a = await one('INSERT INTO announcements (course_id, author_id, body) VALUES ($1, $2, $3) RETURNING *', [
    course.id,
    req.user.id,
    body,
  ]);
  await audit(req.user.id, 'announcement.posted', course.code, { body: body.slice(0, 80) });
  res.status(201).json(a);
});

coursesRouter.post('/:id/announcements/:aid/delete', requireRole('organiser', 'admin'), async (req, res) => {
  const course = await myCourse(req);
  if (!course) return res.status(404).json({ error: 'course not found' });
  await query('DELETE FROM announcements WHERE id = $1 AND course_id = $2', [req.params.aid, course.id]);
  res.json({ ok: true });
});