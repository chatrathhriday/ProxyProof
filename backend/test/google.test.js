// Google sign-in: tokens are signed here with a test RSA key standing in for Google's.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import jwt from 'jsonwebtoken';
import { initDb, closeDb } from '../src/db.js';
import { createApp } from '../src/app.js';
import { createUser } from '../src/auth.js';
import { GOOGLE_CLIENT_ID, setGoogleKeyResolverForTests } from '../src/google.js';

const { privateKey, publicKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
let server, base;

const googleToken = (claims, { key = privateKey, aud = GOOGLE_CLIENT_ID } = {}) =>
  jwt.sign({ email_verified: true, ...claims }, key, {
    algorithm: 'RS256',
    keyid: 'test-kid',
    audience: aud,
    issuer: 'https://accounts.google.com',
    expiresIn: '5m',
  });

async function api(method, path, { token, body } = {}) {
  const res = await fetch(base + path, {
    method,
    headers: { 'content-type': 'application/json', ...(token && { authorization: `Bearer ${token}` }) },
    body: body && JSON.stringify(body),
  });
  return { status: res.status, body: await res.json() };
}
const google = (idToken) => api('POST', '/auth/google', { body: { idToken } });

before(async () => {
  delete process.env.DATABASE_URL;
  delete process.env.PGLITE_DIR;
  delete process.env.ALLOW_PASSWORD_SIGNUP;
  setGoogleKeyResolverForTests(async () => publicKey);
  await initDb();
  server = createApp().listen(0);
  base = `http://localhost:${server.address().port}`;
});

after(async () => {
  server.close();
  await closeDb();
});

test('password sign-up is closed; students must use Google', async () => {
  const r = await api('POST', '/auth/register', { body: { email: 'x@vitstudent.ac.in', name: 'X', password: 'password123' } });
  assert.equal(r.status, 403);
  assert.match(r.body.error, /vitstudent\.ac\.in/);
});

test('VIT Google account signs in, gets an account and claims course invites', async () => {
  await createUser({ email: 'prof@vit.test', name: 'Prof', password: 'password123', role: 'organiser' });
  const prof = (await api('POST', '/auth/login', { body: { email: 'prof@vit.test', password: 'password123' } })).body.token;
  const course = (await api('POST', '/courses', { token: prof, body: { code: 'MAT1', name: 'Maths' } })).body;
  const inv = await api('POST', `/courses/${course.id}/enroll`, { token: prof, body: { emails: ['riya.s2024@vitstudent.ac.in'] } });
  assert.deepEqual(inv.body.invited, ['riya.s2024@vitstudent.ac.in']);

  const r = await google(googleToken({ email: 'Riya.S2024@vitstudent.ac.in', hd: 'vitstudent.ac.in', name: 'Riya S' }));
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.user.role, 'student');
  const mine = (await api('GET', '/courses', { token: r.body.token })).body;
  assert.deepEqual(mine.map((c) => c.code), ['MAT1'], 'invite turned into an enrolment');

  // second sign-in reuses the account
  const again = await google(googleToken({ email: 'riya.s2024@vitstudent.ac.in', hd: 'vitstudent.ac.in' }));
  assert.equal(again.body.user.id, r.body.user.id);
});

test('rejects personal Gmail, wrong domain, unverified email, wrong audience, forged signature', async () => {
  assert.equal((await google(googleToken({ email: 'riya@gmail.com' }))).status, 403);
  assert.equal((await google(googleToken({ email: 'a@vitstudent.ac.in.evil.com', hd: 'evil.com' }))).status, 403);
  assert.equal((await google(googleToken({ email: 'a@vitstudent.ac.in' }))).status, 403, 'no hd claim');
  assert.equal(
    (await google(googleToken({ email: 'a@vitstudent.ac.in', hd: 'vitstudent.ac.in', email_verified: false }))).status,
    403
  );
  assert.equal((await google(googleToken({ email: 'a@vitstudent.ac.in', hd: 'vitstudent.ac.in' }, { aud: 'other-app' }))).status, 403);
  const attacker = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 }).privateKey;
  assert.equal(
    (await google(googleToken({ email: 'a@vitstudent.ac.in', hd: 'vitstudent.ac.in' }, { key: attacker }))).status,
    403
  );
  assert.equal((await google('not-a-jwt')).status, 403);
});

test('staff emails cannot be taken over through Google', async () => {
  await createUser({ email: 'dean@vitstudent.ac.in', name: 'Odd staff', password: 'password123', role: 'organiser' });
  const r = await google(googleToken({ email: 'dean@vitstudent.ac.in', hd: 'vitstudent.ac.in' }));
  assert.equal(r.status, 403);
});
