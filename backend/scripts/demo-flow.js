// Walks one class session against a running server (npm run dev + npm run seed first):
// organiser starts a session -> reads the beacon -> simulated phones "hear" it -> roster.
// Creates fresh demo students and a throwaway course each run, so device binding starts
// clean and real courses (CSE1001) don't fill up with demo students.
import { makeDevice } from './simDevice.js';

const BASE = process.env.API || 'http://localhost:3000';

async function api(method, path, token, body) {
  const res = await fetch(BASE + path, {
    method,
    headers: { 'content-type': 'application/json', ...(token && { authorization: `Bearer ${token}` }) },
    body: body && JSON.stringify(body),
  });
  return { status: res.status, body: await res.json() };
}
const show = (label, r) => console.log(`${label.padEnd(44)} -> ${r.status} ${JSON.stringify(r.body)}`);

const prof = (await api('POST', '/auth/login', null, { email: 'prof@proxyproof.test', password: 'password123' })).body.token;
const run = Date.now().toString(36);
const course = (await api('POST', '/courses', prof, { code: `DEMO-${run}`, name: 'Demo class' })).body;
const students = {};
for (const name of ['Aarav', 'Diya', 'Kabir']) {
  const email = `${name.toLowerCase()}-${run}@demo.test`;
  const reg = await api('POST', '/auth/register', null, { email, name, password: 'password123' });
  const phone = makeDevice(`${name}'s phone`);
  await api('POST', '/devices/register', reg.body.token, phone.registration);
  students[name] = { token: reg.body.token, phone, email };
}
await api('POST', `/courses/${course.id}/enroll`, prof, { emails: Object.values(students).map((s) => s.email) });

const session = (await api('POST', '/sessions', prof, { courseId: course.id })).body;
const b = (await api('GET', `/sessions/${session.id}/beacon`, prof)).body;
console.log(`Session ${session.id} for ${course.code}: beacon major=${b.major} minor=${b.minor}\n`);

const sight = (who, phone, over = {}, opts = {}) =>
  api('POST', '/attendance/sighting', students[who].token, phone.sighting({ major: b.major, minor: b.minor, rssi: [-61, -64, -59], ...over }, opts));

const { Aarav, Diya, Kabir } = students;
show('Aarav, in class, no fingerprint yet', await sight('Aarav', Aarav.phone));
show('Aarav, in class, fingerprint OK', await sight('Aarav', Aarav.phone, {}, { fingerprint: true }));
show('Diya, at the back (rssi ~-88)', await sight('Diya', Diya.phone, { rssi: [-88, -90, -86] }, { fingerprint: true }));
show("Kabir's login on Aarav's phone (proxy)", await sight('Kabir', Aarav.phone, {}, { fingerprint: true }));
show('Kabir, guessed/old token', await sight('Kabir', Kabir.phone, { minor: (b.minor + 1) % 65536 }, { fingerprint: true }));

console.log('\nRoster:');
for (const a of (await api('GET', `/sessions/${session.id}`, prof)).body.attendance)
  console.log(`  ${a.name.padEnd(8)} ${a.status || 'absent'}`);
await api('POST', `/sessions/${session.id}/close`, prof);
console.log('\nSession closed.');
