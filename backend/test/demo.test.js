// Demo semester: timetabled courses, past classes, history for a newly enrolled student.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { initDb, closeDb, one } from '../src/db.js';
import { createApp } from '../src/app.js';
import { createUser } from '../src/auth.js';
import { DEMO_COURSES, seedDemoCourses } from '../src/demo.js';

let server, base, admin, student;

async function api(method, path, { token, body } = {}) {
  const res = await fetch(base + path, {
    method,
    headers: { 'content-type': 'application/json', ...(token && { authorization: `Bearer ${token}` }) },
    body: body && JSON.stringify(body),
  });
  return { status: res.status, body: await res.json() };
}
const login = async (email) => (await api('POST', '/auth/login', { body: { email, password: 'password123' } })).body.token;

before(async () => {
  delete process.env.DATABASE_URL;
  delete process.env.PGLITE_DIR;
  await initDb();
  server = createApp().listen(0);
  base = `http://localhost:${server.address().port}`;
  const prof = await createUser({ email: 'p@t.test', name: 'P', password: 'password123', role: 'organiser' });
  await createUser({ email: 'a@t.test', name: 'Admin', password: 'password123', role: 'admin' });
  await createUser({ email: 'riya@vitstudent.ac.in', name: 'Riya', password: 'password123', role: 'student' });
  await seedDemoCourses(prof.id);
  await seedDemoCourses(prof.id); // idempotent
  admin = await login('a@t.test');
  student = await login('riya@vitstudent.ac.in');
});

after(async () => {
  server.close();
  await closeDb();
});

test('demo courses get timetables and about four weeks of past classes', async () => {
  const n = (await one("SELECT count(*)::int AS n FROM courses")).n;
  assert.equal(n, DEMO_COURSES.length);
  const sessions = (await one('SELECT count(*)::int AS n FROM sessions WHERE demo')).n;
  // 13 weekly slots x 4 weeks = 52 (give or take one week boundary)
  assert.ok(sessions >= 44 && sessions <= 56, `sessions=${sessions}`);
});

test('admin enrols a student into the demo semester with history', async () => {
  assert.equal((await api('POST', '/admin/demo-enroll', { token: student, body: { email: 'x' } })).status, 403);
  assert.equal((await api('POST', '/admin/demo-enroll', { token: admin, body: { email: 'nobody@vitstudent.ac.in' } })).status, 404);
  assert.equal((await api('POST', '/admin/demo-enroll', { token: admin, body: { email: 'riya@vitstudent.ac.in' } })).status, 200);

  const courses = (await api('GET', '/me/attendance', { token: student })).body;
  assert.equal(courses.length, DEMO_COURSES.length);
  for (const c of courses) {
    assert.ok(c.held >= 3, `${c.code} held ${c.held}`);
    assert.ok(c.schedule.length >= 1 && c.schedule[0].room, 'timetable included');
    assert.ok(Number.isInteger(c.streak) && c.streak <= c.held);
  }
  const phy = courses.find((c) => c.code === 'PHY1701');
  const dsa = courses.find((c) => c.code === 'CSE2001');
  assert.ok(phy.pct < dsa.pct, 'physics is the weak subject in the demo');
});
