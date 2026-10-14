// Simulates a 10-minute class in fast-forward (shared clock), with five students:
//   Alice  stays all class, answers the spot check           -> present
//   Bob    leaves after 2 minutes                            -> absent (in range 20%)
//   Carol  stays all class, ignores the spot check           -> needs review
//   Dave   steps out when the check opens, back within 2 min,
//          answers the make-up check                         -> present
//   Eve    never comes                                       -> absent
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { initDb, closeDb } from '../src/db.js';
import { createApp } from '../src/app.js';
import { createUser } from '../src/auth.js';
import { advance, now, resetClock } from '../src/clock.js';
import { makeDevice } from '../scripts/simDevice.js';

let server, base, prof, session;
const students = {};

async function api(method, path, { token, body } = {}) {
  const res = await fetch(base + path, {
    method,
    headers: { 'content-type': 'application/json', ...(token && { authorization: `Bearer ${token}` }) },
    body: body && JSON.stringify(body),
  });
  return { status: res.status, body: await res.json() };
}

before(async () => {
  delete process.env.DATABASE_URL;
  delete process.env.PGLITE_DIR;
  resetClock();
  await initDb();
  server = createApp().listen(0);
  base = `http://localhost:${server.address().port}`;
  await createUser({ email: 'prof@t.test', name: 'Prof', password: 'password123', role: 'organiser' });
  prof = (await api('POST', '/auth/login', { body: { email: 'prof@t.test', password: 'password123' } })).body.token;
  const course = (await api('POST', '/courses', { token: prof, body: { code: 'PHY1', name: 'Physics' } })).body;
  for (const name of ['Alice', 'Bob', 'Carol', 'Dave', 'Eve']) {
    const email = `${name.toLowerCase()}@t.test`;
    const token = (await api('POST', '/auth/register', { body: { email, name, password: 'password123' } })).body.token;
    const phone = makeDevice(`${name}'s phone`);
    await api('POST', '/devices/register', { token, body: phone.registration });
    students[name] = { token, phone, email };
  }
  await api('POST', `/courses/${course.id}/enroll`, { token: prof, body: { emails: Object.values(students).map((s) => s.email) } });
  session = (await api('POST', '/sessions', { token: prof, body: { courseId: course.id, expectedMinutes: 50 } })).body;
});

after(async () => {
  server.close();
  await closeDb();
  resetClock();
});

async function sight(name, opts = {}) {
  const b = (await api('GET', `/sessions/${session.id}/beacon`, { token: prof })).body;
  const s = students[name];
  return api('POST', '/attendance/sighting', {
    token: s.token,
    body: s.phone.sighting({ major: b.major, minor: b.minor, rssi: [-60, -61, -59] }, { clock: now, ...opts }),
  });
}

const answer = (name, id) =>
  api('POST', '/attendance/spot-check', { token: students[name].token, body: students[name].phone.spotCheck(id, { clock: now }) });

test('a 10-minute class resolves into present / review / absent', async () => {
  // tick = 10 s; 60 ticks = 10 minutes. Spot check opens at tick 36 (6:00).
  const inRange = {
    Alice: () => true,
    Bob: (t) => t < 12,
    Carol: () => true,
    Dave: (t) => t < 36 || t >= 45,
  };
  const pending = {}; // name -> spot check id delivered but not yet answered

  for (let tick = 0; tick < 60; tick++) {
    if (tick === 36) assert.equal((await api('POST', `/sessions/${session.id}/spot-check`, { token: prof })).status, 201);
    for (const [name, here] of Object.entries(inRange)) {
      if (!here(tick)) continue;
      const r = await sight(name, { fingerprint: tick === 0 });
      assert.equal(r.status, 200, `${name} tick ${tick}: ${JSON.stringify(r.body)}`);
      if (r.body.spotCheck && !pending[name]) pending[name] = r.body.spotCheck.id;
    }
    // Alice answers at once; Dave answers his make-up when it reaches him; Carol never does.
    for (const name of ['Alice', 'Dave']) {
      if (pending[name]) {
        assert.equal((await answer(name, pending[name])).status, 200, `${name} answer`);
        pending[name] = null;
        students[name].answered = tick;
      }
    }
    advance(10_000);
  }

  assert.equal(students.Alice.answered, 36);
  assert.equal(students.Dave.answered, 45, 'Dave got the make-up check when he came back');
  assert.ok(pending.Carol, 'Carol received the check');
  // Carol answering after 20 s is too late
  assert.equal((await answer('Carol', pending.Carol)).status, 422);

  const live = (await api('GET', `/sessions/${session.id}`, { token: prof })).body;
  const by = Object.fromEntries(live.attendance.map((a) => [a.name, a]));
  assert.equal(by.Alice.spot, 'passed');
  assert.equal(by.Carol.spot, 'failed');
  assert.equal(by.Dave.spot, 'passed');

  await api('POST', `/sessions/${session.id}/close`, { token: prof });
  const report = (await api('GET', `/sessions/${session.id}`, { token: prof })).body;
  const v = Object.fromEntries(report.attendance.map((a) => [a.name, a.verdict]));
  assert.deepEqual(v, { Alice: 'present', Bob: 'absent', Carol: 'review', Dave: 'present', Eve: 'absent' });
  assert.deepEqual(report.counts, { present: 2, review: 1, absent: 2 });
  const reasons = Object.fromEntries(report.attendance.map((a) => [a.name, a.reason]));
  assert.match(reasons.Bob, /in range only 2\d%|in range only 1\d%/);
  assert.match(reasons.Carol, /did not answer spot check/);
  assert.equal(reasons.Eve, 'never detected');
});

test('spot-check answers need the fingerprint signature', async () => {
  const s = students.Alice;
  const deviceOnly = s.phone.spotCheck(1, { clock: now });
  delete deviceOnly.bioSig; // a tampered app that skips the fingerprint prompt
  const r = await api('POST', '/attendance/spot-check', { token: s.token, body: deviceOnly });
  assert.equal(r.status, 401);
  assert.equal(r.body.code, 'BIO_REQUIRED');
});

test('Approve all turns review cases into present and finalises', async () => {
  const r = await api('POST', `/sessions/${session.id}/approve-all`, { token: prof });
  assert.equal(r.body.approved, 1);
  const report = (await api('GET', `/sessions/${session.id}`, { token: prof })).body;
  assert.deepEqual(report.counts, { present: 3, review: 0, absent: 2 });
  assert.ok(report.finalized_at);
  const csv = await (await fetch(`${base}/sessions/${session.id}/export.csv`, { headers: { authorization: `Bearer ${prof}` } })).text();
  assert.match(csv, /\nCarol,carol@t\.test,present,manual,100,failed,set by teacher/);
});

test('student history: held sessions, presents, percentage', async () => {
  const mine = async (name) => (await api('GET', '/me/attendance', { token: students[name].token })).body[0];
  const alice = await mine('Alice');
  assert.deepEqual([alice.code, alice.held, alice.present, alice.review, alice.pct], ['PHY1', 1, 1, 0, 100]);
  assert.equal(alice.sessions[0].status, 'present');
  const bob = await mine('Bob');
  assert.deepEqual([bob.held, bob.present, bob.pct], [1, 0, 0]);
  assert.equal(bob.sessions[0].status, 'absent');
  assert.equal((await api('GET', '/me/attendance', { token: prof })).status, 403);
});
