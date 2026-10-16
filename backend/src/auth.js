// JWT auth. The token carries {id, role}; requireRole() gates routes. Account status is
// re-checked on every request (cached briefly), so disabling someone takes effect at once.
import express from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import crypto from 'node:crypto';
import { one, query } from './db.js';
import { verifyGoogleIdToken, STUDENT_DOMAIN, FACULTY_DOMAIN } from './google.js';
import { audit } from './policy.js';

const SECRET = () => process.env.JWT_SECRET || 'dev-only-secret-change-me';

// Students stay signed in on their phone for 30 days (the phone itself is bound by hardware
// keys + fingerprint, so a long session isn't the weak point). Staff sessions stay short.
export const signJwt = (user) =>
  jwt.sign({ id: user.id, role: user.role, name: user.name }, SECRET(), {
    expiresIn: user.role === 'student' ? '30d' : '12h',
  });

export const verifyJwt = (token) => jwt.verify(token, SECRET());

// id -> { status, role, at }. 10 s is short enough that a disable feels instant.
const statusCache = new Map();
export const forgetStatus = (id) => statusCache.delete(Number(id));

async function currentStatus(id) {
  const hit = statusCache.get(id);
  if (hit && Date.now() - hit.at < 10_000) return hit;
  const u = await one('SELECT status, role FROM users WHERE id = $1', [id]);
  const entry = { status: u?.status || 'missing', role: u?.role, at: Date.now() };
  statusCache.set(id, entry);
  return entry;
}

export async function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'missing token' });
  try {
    req.user = verifyJwt(token);
  } catch {
    return res.status(401).json({ error: 'invalid token' });
  }
  const s = await currentStatus(req.user.id);
  if (s.status !== 'active') return res.status(401).json({ error: `account ${s.status}`, code: 'ACCOUNT_INACTIVE' });
  next();
}

export const requireRole = (...roles) => [
  requireAuth,
  (req, res, next) => (roles.includes(req.user.role) ? next() : res.status(403).json({ error: 'forbidden' })),
];

export async function createUser({ email, name, password, role, status = 'active' }) {
  const hash = await bcrypt.hash(password, 10);
  return one(
    'INSERT INTO users (email, name, password_hash, role, status) VALUES ($1, $2, $3, $4, $5) RETURNING id, email, name, role, status',
    [email.toLowerCase().trim(), name, hash, role, status]
  );
}

const inactiveMessage = (u) =>
  u.status === 'pending'
    ? 'Your faculty account is waiting for admin approval.'
    : 'This account has been disabled. Contact the admin.';

export const authRouter = express.Router();

// Students and faculty join with "Sign in with Google" (college domains only). Password
// sign-up is switched off in production and only kept for local tests.
authRouter.post('/register', async (req, res) => {
  if (process.env.ALLOW_PASSWORD_SIGNUP !== 'true')
    return res.status(403).json({ error: `Students sign in with their @${STUDENT_DOMAIN} Google account.` });
  const { email, name, password } = req.body || {};
  if (!email || !name || !password || password.length < 6)
    return res.status(400).json({ error: 'email, name and password (6+ chars) required' });
  const exists = await one('SELECT 1 FROM users WHERE email = $1', [email.toLowerCase().trim()]);
  if (exists) return res.status(409).json({ error: 'email already registered' });
  const user = await createUser({ email, name, password, role: 'student' });
  res.status(201).json({ token: signJwt(user), user });
});

authRouter.post('/login', async (req, res) => {
  const { email, password } = req.body || {};
  const user = await one('SELECT * FROM users WHERE email = $1', [(email || '').toLowerCase().trim()]);
  if (!user || !(await bcrypt.compare(password || '', user.password_hash)))
    return res.status(401).json({ error: 'wrong email or password' });
  if (user.status !== 'active') return res.status(403).json({ error: inactiveMessage(user), code: 'ACCOUNT_INACTIVE' });
  const { password_hash, ...safe } = user;
  res.json({ token: signJwt(user), user: safe });
});

// One Google button, routed by the account's verified Workspace domain:
//   @vitstudent.ac.in -> student (created on first sign-in, course invites claimed)
//   @vit.ac.in        -> faculty (created 'pending' unless the admin pre-approved the email)
authRouter.post('/google', async (req, res) => {
  let profile;
  try {
    profile = await verifyGoogleIdToken(String(req.body?.idToken || ''));
  } catch (e) {
    return res.status(403).json({ error: e.message || 'Google sign-in failed' });
  }
  const role = profile.domain === FACULTY_DOMAIN ? 'organiser' : 'student';
  let user = await one('SELECT id, email, name, role, status FROM users WHERE email = $1', [profile.email]);
  if (user && user.role !== role)
    return res.status(403).json({ error: 'This email already has a different kind of account. Contact the admin.' });

  if (!user) {
    let status = 'active';
    if (role === 'organiser') {
      const allowed = await one('SELECT 1 FROM faculty_allowlist WHERE email = $1', [profile.email]);
      status = allowed ? 'active' : 'pending';
    }
    // Random unusable password: these accounts can only ever log in through Google.
    user = await createUser({ ...profile, password: crypto.randomBytes(32).toString('hex'), role, status });
    if (role === 'organiser') await audit(user.id, status === 'active' ? 'faculty.joined' : 'faculty.requested', user.email);
  }
  if (user.status !== 'active') return res.status(403).json({ error: inactiveMessage(user), code: 'ACCOUNT_INACTIVE' });

  if (role === 'student') {
    await query(
      `INSERT INTO enrollments (course_id, student_id)
       SELECT course_id, $2 FROM enrollment_invites WHERE email = $1 ON CONFLICT DO NOTHING`,
      [profile.email, user.id]
    );
    await query('DELETE FROM enrollment_invites WHERE email = $1', [profile.email]);
  }
  res.json({ token: signJwt(user), user });
});

authRouter.get('/me', requireAuth, async (req, res) => {
  res.json(await one('SELECT id, email, name, role, status FROM users WHERE id = $1', [req.user.id]));
});

// Admin can create organisers (and other admins) with a password.
authRouter.post('/users', requireRole('admin'), async (req, res) => {
  const { email, name, password, role } = req.body || {};
  if (!['student', 'organiser', 'admin'].includes(role)) return res.status(400).json({ error: 'bad role' });
  if (!email || !name || !password || password.length < 6)
    return res.status(400).json({ error: 'email, name and password (6+ chars) required' });
  const u = await createUser({ email, name, password, role });
  await audit(req.user.id, 'user.created', u.email, { role });
  res.status(201).json(u);
});
