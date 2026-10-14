// End-to-end API test against an in-memory PGlite database.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { initDb, closeDb } from '../src/db.js';
import { createApp } from '../src/app.js';
import { createUser } from '../src/auth.js';
import { resetLimits } from '../src/rateLimit.js';
import { tokenFor, currentWindow, matchWindow } from '../src/tokens.js';

let server, base;

async function api(method, path, { token, body } = {}) {
  const res = await fetch(base + path, {
    method,
    headers: { 'content-type': 'application/json', ...(token && { authorization: `Bearer ${token}` }) },
    body: body && JSON.stringify(body),
  });
  return { status: res.status, body: await res.json() };
}
const login = async (email) => (await api('POST', '/auth/login', { body: { email, password: 'password123' } })).body.token;

let prof, s1, s2, outsider, courseId, session, beacon;

before(async () => {
  delete process.env.DATABASE_URL;
  delete process.env.PGLITE_DIR;
  await initDb();
  server = createApp().listen(0);
  base = `http://localhost:${server.address().port}`;
  await createUser({ email: 'prof@t.test', name: 'Prof', password: 'password123', role: 'organiser' });
  prof = await login('prof@t.test');
  for (const e of ['s1', 's2', 'out']) await api('POST', '/auth/register', { body: { email: `${e}@t.test`, name: e, password: 'password123' } });
  [s1, s2, outsider] = await Promise.all(['s1', 's2', 'out'].map((e) => login(`${e}@t.test`)));
});

after(async () => {
  server.close();
  await closeDb();
});

test('roles are enforced', async () => {
  assert.equal((await api('POST', '/courses', { token: s1, body: { code: 'X', name: 'X' } })).status, 403);
  assert.equal((await api('GET', '/courses')).status, 401);
  assert.equal((await api('POST', '/auth/login', { body: { email: 's1@t.test', password: 'nope' } })).status, 401);
});

test('organiser creates course, enrolls students, starts session', async () => {
  const c = await api('POST', '/courses', { token: prof, body: { code: 'CSE1', name: 'Intro' } });
  assert.equal(c.status, 201);
  courseId = c.body.id;
  const en = await api('POST', `/courses/${courseId}/enroll`, { token: prof, body: { emails: ['s1@t.test', 's2@t.test', 'ghost@t.test'] } });
  assert.deepEqual(en.body.notFound, ['ghost@t.test']);

  const s = await api('POST', '/sessions', { token: prof, body: { courseId } });
  assert.equal(s.status, 201);
  assert.equal(s.body.secret, undefined, 'secret must never be returned');
  session = s.body;

  const b = await api('GET', `/sessions/${session.id}/beacon`, { token: prof });
  assert.equal(b.body.major, session.short_code);
  assert.ok(b.body.minor >= 0 && b.body.minor <= 65535);
  beacon = b.body;
});

const sight = (token, over = {}) =>
  api('POST', '/attendance/sighting', {
    token,
    body: { major: beacon.major, minor: beacon.minor, rssi: [-60, -62, -58], deviceUid: 'phone-A', ...over },
  });

test('valid sighting marks present', async () => {
  const r = await sight(s1);
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.status, 'present');
  const again = await sight(s1); // repeated sightings feed the timeline, don't duplicate
  assert.equal(again.status, 200);
});

test('rejects: wrong token, too far, not enrolled, unknown session', async () => {
  resetLimits();
  assert.equal((await sight(s2, { minor: (beacon.minor + 1) % 65536, deviceUid: 'phone-B' })).status, 422);
  const far = await sight(s2, { rssi: [-90, -88, -60], deviceUid: 'phone-B' }); // median -88
  assert.equal(far.status, 422);
  assert.equal(far.body.rssiMedian, -88);
  assert.equal((await sight(outsider, { deviceUid: 'phone-C' })).status, 403);
  assert.equal((await sight(s2, { major: (beacon.major + 1) % 65536, deviceUid: 'phone-B' })).status, 404);
});

test('one device cannot mark two students (proxy via borrowed phone)', async () => {
  resetLimits();
  const r = await sight(s2, { deviceUid: 'phone-A' });
  assert.equal(r.status, 409);
  // s1 also can't switch to a second phone mid-session
  assert.equal((await sight(s1, { deviceUid: 'phone-Z' })).status, 409);
});

test('freshness: window ±1 accepted, older tokens rejected', () => {
  const secret = 'ab'.repeat(32);
  const now = Date.now();
  const w = currentWindow(now);
  assert.equal(matchWindow(secret, tokenFor(secret, w), now), w);
  assert.equal(matchWindow(secret, tokenFor(secret, w - 1), now), w - 1);
  assert.equal(matchWindow(secret, tokenFor(secret, w + 1), now), w + 1);
  // A token screenshotted a minute ago (6 windows back) is dead — unless it happens to
  // collide with a live 16-bit token (~3 in 65,536), in which case acceptance is correct.
  const old = tokenFor(secret, w - 6);
  if (![w - 1, w, w + 1].some((c) => tokenFor(secret, c) === old)) assert.equal(matchWindow(secret, old, now), null);
});

test('rate limit kicks in', async () => {
  resetLimits();
  const codes = [];
  for (let i = 0; i < 12; i++) codes.push((await sight(s2, { minor: (beacon.minor + 1) % 65536, deviceUid: 'phone-B' })).status);
  assert.ok(codes.slice(0, 10).every((c) => c === 422));
  assert.equal(codes[10], 429);
});

test('session detail shows roster with statuses; close stops marking', async () => {
  resetLimits();
  const d = await api('GET', `/sessions/${session.id}`, { token: prof });
  const byName = Object.fromEntries(d.body.attendance.map((a) => [a.name, a.status]));
  assert.equal(byName.s1, 'present');
  assert.equal(byName.s2, null);

  assert.equal((await api('POST', `/sessions/${session.id}/close`, { token: prof })).body.status, 'closed');
  assert.equal((await sight(s1)).status, 404);
  assert.equal((await api('GET', `/sessions/${session.id}/beacon`, { token: prof })).status, 409);
});
