import express from 'express';
import { query, one } from '../db.js';
import { requireAuth, requireRole } from '../auth.js';

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

// Enroll existing student accounts by email. Unknown emails are reported back, not created.
coursesRouter.post('/:id/enroll', requireRole('organiser'), async (req, res) => {
  const course = await one('SELECT * FROM courses WHERE id = $1 AND organiser_id = $2', [req.params.id, req.user.id]);
  if (!course) return res.status(404).json({ error: 'course not found' });
  const emails = (req.body?.emails || []).map((e) => String(e).toLowerCase().trim());
  const enrolled = [];
  const notFound = [];
  for (const email of emails) {
    const student = await one("SELECT id FROM users WHERE email = $1 AND role = 'student'", [email]);
    if (!student) {
      notFound.push(email);
      continue;
    }
    await query('INSERT INTO enrollments VALUES ($1, $2) ON CONFLICT DO NOTHING', [course.id, student.id]);
    enrolled.push(email);
  }
  res.json({ enrolled, notFound });
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
            EXISTS (SELECT 1 FROM devices d WHERE d.user_id = u.id AND d.status = 'approved') AS has_device
     FROM users u JOIN enrollments e ON e.student_id = u.id
     WHERE e.course_id = $1 ORDER BY u.name`,
    [course.id]
  );
  res.json({ course, held, students });
});

coursesRouter.post('/:id/unenroll', requireRole('organiser'), async (req, res) => {
  const course = await one('SELECT * FROM courses WHERE id = $1 AND organiser_id = $2', [req.params.id, req.user.id]);
  if (!course) return res.status(404).json({ error: 'course not found' });
  await query('DELETE FROM enrollments WHERE course_id = $1 AND student_id = $2', [course.id, req.body?.studentId]);
  res.json({ ok: true });
});
