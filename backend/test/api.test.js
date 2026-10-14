// End-to-end API test against an in-memory PGlite database.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { initDb, closeDb } from '../src/db.js';
import { createApp } from '../src/app.js';
import { createUser } from '../src/auth.js';
import { resetLimits } from '../src/rateLimit.js';
import { tokenFor, currentWindow, matchWindow } from '../src/tokens.js';
import { makeDevice } from '../scripts/simDevice.js';

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

let prof, admin, s1, s2, outsider, courseId, session, beacon;
const phoneA = makeDevice('Phone A'); // s1's phone
const phoneB = makeDevice('Phone B'); // s2's phone
const phoneC = makeDevice('Phone C'); // outsider's phone
const phoneB2 = makeDevice('Phone B2'); // s2's replacement phone

before(async () => {
  delete process.env.DATABASE_URL;
  delete process.env.PGLITE_DIR;
  await initDb();
  server = createApp().listen(0);
  base = `http://localhost:${server.address().port}`;
  await createUser({ email: 'prof@t.test', name: 'Prof', password: 'password123', role: 'organiser' });
  await createUser({ email: 'admin@t.test', name: 'Admin', password: 'password123', role: 'admin' });
  prof = await login('prof@t.test');
  admin = await login('admin@t.test');
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
  assert.equal((await api('GET', '/devices/pending', { token: prof })).status, 403);
});

test('device binding: first phone auto-approved, phone cannot be shared', async () => {
  const r1 = await api('POST', '/devices/register', { token: s1, body: phoneA.registration });
  assert.equal(r1.status, 201);
  assert.equal(r1.body.status, 'approved');
  // idempotent
  assert.equal((await api('POST', '/devices/register', { token: s1, body: phoneA.registration })).body.status, 'approved');
  // s2 tries to register s1's phone (same keys) -> refused
  assert.equal((await api('POST', '/devices/register', { token: s2, body: phoneA.registration })).status, 409);
  assert.equal((await api('POST', '/devices/register', { token: s2, body: phoneB.registration })).body.status, 'approved');
  assert.equal((await api('POST', '/devices/register', { token: outsider, body: phoneC.registration })).body.status, 'approved');
  // garbage keys rejected
  assert.equal((await api('POST', '/devices/register', { token: s1, body: { devicePublicKey: 'abc', bioPublicKey: 'def' } })).status, 400);
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

const reading = (over = {}) => ({ major: beacon.major, minor: beacon.minor, rssi: [-60, -62, -58], ...over });
const sight = (token, phone, over = {}, opts = {}) =>
  api('POST', '/attendance/sighting', { token, body: phone.sighting(reading(over), opts) });

test('first mark needs fingerprint; later sightings only the device key', async () => {
  resetLimits();
  const noBio = await sight(s1, phoneA);
  assert.equal(noBio.status, 428);
  assert.equal(noBio.body.code, 'BIO_REQUIRED');
  const r = await sight(s1, phoneA, {}, { fingerprint: true });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.status, 'present');
  assert.equal((await sight(s1, phoneA)).status, 200);
});

test('signatures: wrong key, tampered payload, replay', async () => {
  resetLimits();
  // s1's account but signed by phone B's key (stolen password on another phone)
  assert.equal((await sight(s1, phoneB, {}, { fingerprint: true })).status, 401);
  // payload edited after signing (e.g. RSSI boosted)
  const body = phoneA.sighting(reading({ rssi: [-90] }));
  body.payload = body.payload.replace('-90', '-40');
  assert.equal((await api('POST', '/attendance/sighting', { token: s1, body })).status, 401);
  // exact same signed request sent twice
  const once = phoneA.sighting(reading());
  assert.equal((await api('POST', '/attendance/sighting', { token: s1, body: once })).status, 200);
  assert.equal((await api('POST', '/attendance/sighting', { token: s1, body: once })).status, 409);
  // old timestamp
  assert.equal((await sight(s1, phoneA, {}, { ts: Date.now() - 5 * 60_000 })).status, 422);
});

test('rejects: wrong token, too far, not enrolled, unknown session', async () => {
  resetLimits();
  const bio = { fingerprint: true };
  assert.equal((await sight(s2, phoneB, { minor: (beacon.minor + 1) % 65536 }, bio)).status, 422);
  const far = await sight(s2, phoneB, { rssi: [-90, -88, -60] }, bio); // median -88
  assert.equal(far.status, 422);
  assert.equal(far.body.rssiMedian, -88);
  assert.equal((await sight(outsider, phoneC, {}, bio)).status, 403);
  assert.equal((await sight(s2, phoneB, { major: (beacon.major + 1) % 65536 }, bio)).status, 404);
});

test('new phone needs admin approval; approval retires the old phone', async () => {
  resetLimits();
  const reg = await api('POST', '/devices/register', { token: s2, body: phoneB2.registration });
  assert.equal(reg.body.status, 'pending');
  // still marks with the old phone until approved; new phone is refused
  assert.equal((await sight(s2, phoneB2, {}, { fingerprint: true })).status, 401);

  const pending = (await api('GET', '/devices/pending', { token: admin })).body;
  assert.equal(pending.length, 1);
  assert.equal(pending[0].current_model, 'Phone B');
  assert.equal((await api('POST', `/devices/${pending[0].id}/approve`, { token: admin })).body.status, 'approved');

  assert.equal((await sight(s2, phoneB, {}, { fingerprint: true })).status, 401); // old phone now dead
  assert.equal((await sight(s2, phoneB2, {}, { fingerprint: true })).status, 200);
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
  for (let i = 0; i < 12; i++) codes.push((await sight(s2, phoneB2, { minor: (beacon.minor + 1) % 65536 })).status);
  assert.ok(codes.slice(0, 10).every((c) => c === 422), codes.join(','));
  assert.equal(codes[10], 429);
});

test('session detail shows roster with statuses; close stops marking', async () => {
  resetLimits();
  const d = await api('GET', `/sessions/${session.id}`, { token: prof });
  const byName = Object.fromEntries(d.body.attendance.map((a) => [a.name, a.status]));
  assert.equal(byName.s1, 'present');
  assert.equal(byName.s2, 'present');

  assert.equal((await api('POST', `/sessions/${session.id}/close`, { token: prof })).body.status, 'closed');
  assert.equal((await sight(s1, phoneA)).status, 404);
  assert.equal((await api('GET', `/sessions/${session.id}/beacon`, { token: prof })).status, 409);
});
