import express from 'express';
import { query, one } from '../db.js';
import { requireAuth, requireRole } from '../auth.js';

export const coursesRouter = express.Router();

coursesRouter.post('/', requireRole('organiser'), async (req, res) => {
  const { code, name } = req.body || {};
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
  const rows =
    req.user.role === 'admin'
      ? await query('SELECT * FROM courses ORDER BY code')
      : await query('SELECT * FROM courses WHERE organiser_id = $1 ORDER BY code', [req.user.id]);
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

coursesRouter.get('/:id/students', requireRole('organiser', 'admin'), async (req, res) => {
  res.json(
    await query(
      `SELECT u.id, u.email, u.name FROM users u JOIN enrollments e ON e.student_id = u.id
       WHERE e.course_id = $1 ORDER BY u.name`,
      [req.params.id]
    )
  );
});
