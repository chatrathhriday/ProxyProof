import express from 'express';
import { one } from '../db.js';
import { requireRole } from '../auth.js';
import { enrolInDemo } from '../demo.js';

export const adminRouter = express.Router();

// Demo helper: put an existing student (e.g. a real VIT Google account) into the demo
// courses with a month of history, so their app shows a full semester.
adminRouter.post('/demo-enroll', requireRole('admin'), async (req, res) => {
  const email = String(req.body?.email || '').toLowerCase().trim();
  const student = await one("SELECT id, name FROM users WHERE email = $1 AND role = 'student'", [email]);
  if (!student) return res.status(404).json({ error: 'No student with that email yet — sign in once in the app first.' });
  await enrolInDemo(student.id);
  res.json({ ok: true, name: student.name });
});
