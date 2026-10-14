// Stateless JWT auth. The token carries {id, role}; requireRole() gates routes.
import express from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { one } from './db.js';

const SECRET = () => process.env.JWT_SECRET || 'dev-only-secret-change-me';

export const signJwt = (user) =>
  jwt.sign({ id: user.id, role: user.role, name: user.name }, SECRET(), { expiresIn: '12h' });

export const verifyJwt = (token) => jwt.verify(token, SECRET());

export function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'missing token' });
  try {
    req.user = verifyJwt(token);
    next();
  } catch {
    res.status(401).json({ error: 'invalid token' });
  }
}

export const requireRole = (...roles) => [
  requireAuth,
  (req, res, next) => (roles.includes(req.user.role) ? next() : res.status(403).json({ error: 'forbidden' })),
];

export async function createUser({ email, name, password, role }) {
  const hash = await bcrypt.hash(password, 10);
  return one(
    'INSERT INTO users (email, name, password_hash, role) VALUES ($1, $2, $3, $4) RETURNING id, email, name, role',
    [email.toLowerCase().trim(), name, hash, role]
  );
}

export const authRouter = express.Router();

// Self-registration is students only; organisers/admins are created by seed/admin.
authRouter.post('/register', async (req, res) => {
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
  const { password_hash, ...safe } = user;
  res.json({ token: signJwt(user), user: safe });
});

authRouter.get('/me', requireAuth, async (req, res) => {
  res.json(await one('SELECT id, email, name, role FROM users WHERE id = $1', [req.user.id]));
});

// Admin can create organisers (and other admins).
authRouter.post('/users', requireRole('admin'), async (req, res) => {
  const { email, name, password, role } = req.body || {};
  if (!['student', 'organiser', 'admin'].includes(role)) return res.status(400).json({ error: 'bad role' });
  res.status(201).json(await createUser({ email, name, password, role }));
});
