// v1.5: faculty Google sign-in with approval, admin powers, policy, audit, excused, announcements.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import jwt from 'jsonwebtoken';
import { initDb, closeDb } from '../src/db.js';
import { createApp } from '../src/app.js';
import { createUser } from '../src/auth.js';
import { GOOGLE_CLIENT_ID, setGoogleKeyResolverForTests } from '../src/google.js';

const { privateKey, publicKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
let server, base, admin, prof, s1, s1Id, course;

const googleToken = (email, hd) =>
  jwt.sign({ email, hd, email_verified: true, name: email.split('@')[0] }, privateKey, {
    algorithm: 'RS256',
    keyid: 'k',
    audience: GOOGLE_CLIENT_ID,
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
const login = async (email) => (await api('POST', '/auth/login', { body: { email, password: 'password123' } })).body.token;
const google = (email, hd) => api('POST', '/auth/google', { body: { idToken: googleToken(email, hd) } });

before(async () => {
  delete process.env.DATABASE_URL;
  delete process.env.PGLITE_DIR;
  setGoogleKeyResolverForTests(async () => publicKey);
  await initDb();
  server = createApp().listen(0);
  base = `http://localhost:${server.address().port}`;
  await createUser({ email: 'admin@t.test', name: 'Admin', password: 'password123', role: 'admin' });
  await createUser({ email: 'prof@t.test', name: 'Prof', password: 'password123', role: 'organiser' });
  const st = await createUser({ email: 's1@vitstudent.ac.in', name: 'S1', password: 'password123', role: 'student' });
  s1Id = st.id;
  admin = await login('admin@t.test');
  prof = await login('prof@t.test');
  s1 = await login('s1@vitstudent.ac.in');
  course = (await api('POST', '/courses', { token: prof, body: { code: 'phy9', name: 'Physics' } })).body;
  await api('POST', `/courses/${course.id}/enroll`, { token: prof, body: { emails: ['s1@vitstudent.ac.in'] } });
});

after(async () => {
  server.close();
  await closeDb();
});

test('@vit.ac.in Google sign-in creates a pending teacher until the admin approves', async () => {
  const r = await google('meena.k@vit.ac.in', 'vit.ac.in');
  assert.equal(r.status, 403);
  assert.match(r.body.error, /waiting for admin approval/);
  assert.equal((await api('GET', '/admin/overview', { token: admin })).body.totals.pending_faculty, 1);

  const people = (await api('GET', '/admin/users?q=meena', { token: admin })).body;
  assert.deepEqual([people[0].role, people[0].status], ['organiser', 'pending']);
  await api('POST', `/admin/users/${people[0].id}/status`, { token: admin, body: { status: 'active' } });

  const ok = await google('meena.k@vit.ac.in', 'vit.ac.in');
  assert.equal(ok.status, 200);
  assert.equal(ok.body.user.role, 'organiser');
  assert.equal((await api('GET', '/courses', { token: ok.body.token })).status, 200);
});

test('pre-approved faculty emails get in on first sign-in; students stay students', async () => {
  await api('POST', '/admin/faculty-allowlist', { token: admin, body: { emails: ['ravi.s@vit.ac.in'] } });
  const r = await google('ravi.s@vit.ac.in', 'vit.ac.in');
  assert.equal(r.status, 200);
  assert.equal(r.body.user.role, 'organiser');
  const st = await google('new.kid2026@vitstudent.ac.in', 'vitstudent.ac.in');
  assert.equal(st.body.user.role, 'student');
  // a personal Gmail with either hd is refused
  assert.equal((await google('ravi@gmail.com', 'vit.ac.in')).status, 403);
});

test('disabling an account locks it out immediately; re-enabling restores it', async () => {
  const outsider = await createUser({ email: 'x@t.test', name: 'X', password: 'password123', role: 'organiser' });
  const token = await login('x@t.test');
  assert.equal((await api('GET', '/courses', { token })).status, 200);
  await api('POST', `/admin/users/${outsider.id}/status`, { token: admin, body: { status: 'disabled' } });
  const r = await api('GET', '/courses', { token });
  assert.equal(r.status, 401);
  assert.equal(r.body.code, 'ACCOUNT_INACTIVE');
  assert.equal((await api('POST', '/auth/login', { body: { email: 'x@t.test', password: 'password123' } })).status, 403);
  await api('POST', `/admin/users/${outsider.id}/status`, { token: admin, body: { status: 'active' } });
  assert.equal((await api('GET', '/courses', { token })).status, 200);
  // admin can't lock themselves out
  const me = (await api('GET', '/auth/me', { token: admin })).body;
  assert.equal((await api('POST', `/admin/users/${me.id}/status`, { token: admin, body: { status: 'disabled' } })).status, 400);
});

test('college policy sets session defaults and the student rule', async () => {
  assert.equal((await api('PUT', '/admin/settings', { token: admin, body: { minAttendance: 20 } })).status, 400);
  const p = (await api('PUT', '/admin/settings', { token: admin, body: { minAttendance: 80, rssiThreshold: -70 } })).body;
  assert.deepEqual([p.minAttendance, p.rssiThreshold, p.presencePct], [80, -70, 80]);
  const s = (await api('POST', '/sessions', { token: prof, body: { courseId: course.id } })).body;
  assert.equal(s.rssi_threshold, -70);
  // excused: doesn't count against the student
  await api('POST', `/sessions/${s.id}/attendance`, { token: prof, body: { studentId: s1Id, status: 'excused' } });
  await api('POST', `/sessions/${s.id}/close`, { token: prof });
  const mine = (await api('GET', '/me/attendance', { token: s1 })).body[0];
  assert.deepEqual([mine.rule, mine.held, mine.excused, mine.counted, mine.pct], [80, 1, 1, 0, null]);
  const summary = (await api('GET', `/sessions/${s.id}`, { token: prof })).body;
  assert.equal(summary.counts.excused, 1);
});

test('teacher tools: timetable, session history, announcements', async () => {
  assert.equal(
    (await api('PUT', `/courses/${course.id}/schedule`, { token: prof, body: { schedule: [{ d: 9, s: '10:00', e: '09:00' }] } })).status,
    400
  );
  const sch = await api('PUT', `/courses/${course.id}/schedule`, {
    token: prof,
    body: { schedule: [{ d: 3, s: '14:00', e: '14:50', room: 'TT 105' }, { d: 1, s: '09:00', e: '09:50', room: 'TT 105' }] },
  });
  assert.deepEqual(sch.body.schedule.map((x) => x.d), [1, 3]);

  const hist = (await api('GET', `/courses/${course.id}/sessions`, { token: prof })).body;
  assert.equal(hist.length, 1);
  assert.deepEqual([hist[0].enrolled, hist[0].excused, hist[0].absent], [1, 1, 0]);

  assert.equal((await api('POST', `/courses/${course.id}/announcements`, { token: s1, body: { body: 'hi' } })).status, 403);
  await api('POST', `/courses/${course.id}/announcements`, { token: prof, body: { body: 'Class moved to SJT 512 today' } });
  const feed = (await api('GET', '/me/announcements', { token: s1 })).body;
  assert.equal(feed[0].body, 'Class moved to SJT 512 today');
  assert.equal(feed[0].code, 'PHY9');
});

test('admin overview, reset device, transfer, audit trail', async () => {
  const o = (await api('GET', '/admin/overview', { token: admin })).body;
  assert.ok(o.totals.students >= 2 && o.courses.some((c) => c.code === 'PHY9'));

  const r = await api('POST', `/admin/users/${s1Id}/reset-device`, { token: admin });
  assert.equal(r.status, 200);

  const ravi = (await api('GET', '/admin/users?q=ravi', { token: admin })).body[0];
  assert.equal((await api('POST', `/admin/courses/${course.id}/transfer`, { token: admin, body: { teacherId: ravi.id } })).status, 200);

  const log = (await api('GET', '/admin/audit', { token: admin })).body;
  const actions = log.map((a) => a.action);
  for (const a of ['course.transferred', 'device.reset', 'attendance.excused', 'policy.updated', 'faculty.allowlisted', 'user.disabled'])
    assert.ok(actions.includes(a), `missing ${a}`);
  assert.equal((await api('GET', '/admin/audit', { token: prof })).status, 403);
});
