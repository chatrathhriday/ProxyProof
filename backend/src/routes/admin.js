// Admin console API: institution overview, people, faculty approval, policy, audit trail.
import express from 'express';
import { query, one } from '../db.js';
import { requireRole, forgetStatus } from '../auth.js';
import { enrolInDemo } from '../demo.js';
import { audit, getPolicy, setPolicy } from '../policy.js';

export const adminRouter = express.Router();
const admin = requireRole('admin');

// One screen for the whole college: live classes now, totals, and every course's health.
adminRouter.get('/overview', admin, async (req, res) => {
  const policy = await getPolicy();
  const [totals, live, courses] = await Promise.all([
    one(`SELECT
           (SELECT count(*)::int FROM users WHERE role = 'student' AND status = 'active') AS students,
           (SELECT count(*)::int FROM users WHERE role = 'organiser' AND status = 'active') AS teachers,
           (SELECT count(*)::int FROM users WHERE role = 'organiser' AND status = 'pending') AS pending_faculty,
           (SELECT count(*)::int FROM devices WHERE status = 'pending') AS pending_devices,
           (SELECT count(*)::int FROM courses) AS courses`),
    query(
      `SELECT s.id, s.started_at, c.code, c.name, u.name AS teacher,
              (SELECT count(*)::int FROM attendance a WHERE a.session_id = s.id AND a.status = 'present') AS present,
              (SELECT count(*)::int FROM enrollments e WHERE e.course_id = s.course_id) AS enrolled
       FROM sessions s JOIN courses c ON c.id = s.course_id JOIN users u ON u.id = s.organiser_id
       WHERE s.status = 'active' ORDER BY s.started_at`
    ),
    // Per course: classes held, average attendance and defaulters (excused classes don't count).
    query(
      `WITH per_student AS (
         SELECT e.course_id, e.student_id,
                (SELECT count(*) FROM sessions s WHERE s.course_id = e.course_id AND s.status = 'closed') AS held,
                (SELECT count(*) FROM attendance a JOIN sessions s ON s.id = a.session_id
                 WHERE s.course_id = e.course_id AND s.status = 'closed' AND a.student_id = e.student_id AND a.status = 'present') AS present,
                (SELECT count(*) FROM attendance a JOIN sessions s ON s.id = a.session_id
                 WHERE s.course_id = e.course_id AND s.status = 'closed' AND a.student_id = e.student_id AND a.status = 'excused') AS excused
         FROM enrollments e)
       SELECT c.id, c.code, c.name, u.name AS teacher, count(p.student_id)::int AS students,
              COALESCE(max(p.held), 0)::int AS held,
              round(avg(CASE WHEN p.held - p.excused > 0 THEN 100.0 * p.present / (p.held - p.excused) END))::int AS avg_pct,
              count(*) FILTER (WHERE p.held - p.excused > 0 AND 100.0 * p.present / (p.held - p.excused) < $1)::int AS defaulters
       FROM courses c JOIN users u ON u.id = c.organiser_id LEFT JOIN per_student p ON p.course_id = c.id
       GROUP BY c.id, u.name ORDER BY c.code`,
      [policy.minAttendance]
    ),
  ]);
  res.json({ totals, live, courses, policy });
});

// People search across the college.
adminRouter.get('/users', admin, async (req, res) => {
  const q = `%${String(req.query.q || '').toLowerCase()}%`;
  const role = ['student', 'organiser', 'admin'].includes(req.query.role) ? req.query.role : null;
  res.json(
    await query(
      `SELECT u.id, u.email, u.name, u.role, u.status, u.created_at,
              d.model AS device, d.decided_at AS device_since,
              (SELECT count(*)::int FROM enrollments e WHERE e.student_id = u.id) AS enrolled,
              (SELECT count(*)::int FROM courses c WHERE c.organiser_id = u.id) AS teaching
       FROM users u LEFT JOIN devices d ON d.user_id = u.id AND d.status = 'approved'
       WHERE (lower(u.email) LIKE $1 OR lower(u.name) LIKE $1) AND ($2::text IS NULL OR u.role = $2)
       ORDER BY (u.status = 'pending') DESC, u.role, u.name LIMIT 200`,
      [q, role]
    )
  );
});

// Approve a faculty member, or disable/re-enable anyone (except yourself).
adminRouter.post('/users/:id/status', admin, async (req, res) => {
  const status = req.body?.status;
  if (!['active', 'disabled'].includes(status)) return res.status(400).json({ error: "status must be 'active' or 'disabled'" });
  if (Number(req.params.id) === req.user.id) return res.status(400).json({ error: 'You cannot change your own status.' });
  const u = await one('UPDATE users SET status = $2 WHERE id = $1 RETURNING id, email, role, status', [req.params.id, status]);
  if (!u) return res.status(404).json({ error: 'user not found' });
  forgetStatus(u.id);
  await audit(req.user.id, status === 'active' ? 'user.activated' : 'user.disabled', u.email, { role: u.role });
  res.json(u);
});

// Lost/changed phone: retire the bound device; the student's next phone is approved on first use.
adminRouter.post('/users/:id/reset-device', admin, async (req, res) => {
  const u = await one('SELECT email FROM users WHERE id = $1', [req.params.id]);
  if (!u) return res.status(404).json({ error: 'user not found' });
  const r = await query(
    "UPDATE devices SET status = 'revoked', decided_at = now(), decided_by = $2 WHERE user_id = $1 AND status IN ('approved', 'pending') RETURNING id",
    [req.params.id, req.user.id]
  );
  await audit(req.user.id, 'device.reset', u.email, { devices: r.length });
  res.json({ revoked: r.length });
});

// Faculty emails approved in advance.
adminRouter.get('/faculty-allowlist', admin, async (req, res) => {
  res.json(await query('SELECT email, added_at FROM faculty_allowlist ORDER BY email'));
});
adminRouter.post('/faculty-allowlist', admin, async (req, res) => {
  const emails = [...new Set((req.body?.emails || []).map((e) => String(e).toLowerCase().trim()).filter((e) => e.includes('@')))];
  for (const email of emails) {
    await query('INSERT INTO faculty_allowlist (email, added_by) VALUES ($1, $2) ON CONFLICT DO NOTHING', [email, req.user.id]);
    // already signed in and waiting? approve now
    const pending = await one("UPDATE users SET status = 'active' WHERE email = $1 AND role = 'organiser' AND status = 'pending' RETURNING id", [email]);
    if (pending) forgetStatus(pending.id);
  }
  if (emails.length) await audit(req.user.id, 'faculty.allowlisted', emails.join(', '));
  res.json({ added: emails });
});
adminRouter.post('/faculty-allowlist/remove', admin, async (req, res) => {
  await query('DELETE FROM faculty_allowlist WHERE email = $1', [String(req.body?.email || '').toLowerCase()]);
  res.json({ ok: true });
});

// Hand a course (and its future sessions) to another teacher.
adminRouter.post('/courses/:id/transfer', admin, async (req, res) => {
  const teacher = await one("SELECT id, email FROM users WHERE id = $1 AND role = 'organiser' AND status = 'active'", [req.body?.teacherId]);
  if (!teacher) return res.status(400).json({ error: 'pick an active teacher' });
  const c = await one('UPDATE courses SET organiser_id = $2 WHERE id = $1 RETURNING code', [req.params.id, teacher.id]);
  if (!c) return res.status(404).json({ error: 'course not found' });
  await query("UPDATE sessions SET organiser_id = $2 WHERE course_id = $1 AND status = 'active'", [req.params.id, teacher.id]);
  await audit(req.user.id, 'course.transferred', c.code, { to: teacher.email });
  res.json({ ok: true });
});

adminRouter.get('/audit', admin, async (req, res) => {
  const limit = Math.min(500, Number(req.query.limit) || 100);
  res.json(
    await query(
      `SELECT a.id, a.at, a.action, a.target, a.details, u.name AS actor, u.role AS actor_role
       FROM audit_log a LEFT JOIN users u ON u.id = a.actor_id ORDER BY a.at DESC, a.id DESC LIMIT $1`,
      [limit]
    )
  );
});

adminRouter.get('/settings', admin, async (req, res) => res.json(await getPolicy()));
adminRouter.put('/settings', admin, async (req, res) => {
  const before = await getPolicy();
  let after;
  try {
    after = await setPolicy(req.body || {});
  } catch (e) {
    return res.status(400).json({ error: e.message });
  }
  await audit(req.user.id, 'policy.updated', 'college policy', { before, after });
  res.json(after);
});

// Demo helper: put an existing student (e.g. a real VIT Google account) into the demo
// courses with a month of history, so their app shows a full semester.
adminRouter.post('/demo-enroll', admin, async (req, res) => {
  const email = String(req.body?.email || '').toLowerCase().trim();
  const student = await one("SELECT id, name FROM users WHERE email = $1 AND role = 'student'", [email]);
  if (!student) return res.status(404).json({ error: 'No student with that email yet — sign in once in the app first.' });
  await enrolInDemo(student.id);
  res.json({ ok: true, name: student.name });
});
