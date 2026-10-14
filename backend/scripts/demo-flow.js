// Walks one class session against a running server (npm run dev + npm run seed first):
// organiser starts a session -> reads the beacon -> students "hear" it -> roster.
const BASE = process.env.API || 'http://localhost:3000';

async function api(method, path, token, body) {
  const res = await fetch(BASE + path, {
    method,
    headers: { 'content-type': 'application/json', ...(token && { authorization: `Bearer ${token}` }) },
    body: body && JSON.stringify(body),
  });
  return { status: res.status, body: await res.json() };
}
const login = async (email) => (await api('POST', '/auth/login', null, { email, password: 'password123' })).body.token;
const show = (label, r) => console.log(`${label.padEnd(48)} -> ${r.status} ${JSON.stringify(r.body)}`);

const prof = await login('prof@proxyproof.test');
const [s1, s2, s3] = await Promise.all([1, 2, 3].map((i) => login(`student${i}@proxyproof.test`)));
const course = (await api('GET', '/courses', prof)).body[0];
const session = (await api('POST', '/sessions', prof, { courseId: course.id })).body;
console.log(`Started session ${session.id} for ${course.code}, short code ${session.short_code}\n`);

const b = (await api('GET', `/sessions/${session.id}/beacon`, prof)).body;
console.log(`Beacon now broadcasting: uuid=${b.uuid} major=${b.major} minor=${b.minor}\n`);

const sight = (t, over = {}) =>
  api('POST', '/attendance/sighting', t, { major: b.major, minor: b.minor, rssi: [-61, -64, -59], deviceUid: 'aarav-phone', ...over });

show('Aarav, in class (rssi ~-61)', await sight(s1));
show('Diya, at the back (rssi ~-88)', await sight(s2, { rssi: [-88, -90, -86], deviceUid: 'diya-phone' }));
show("Kabir, using Aarav's phone (proxy)", await sight(s3));
show('Kabir, guessed/old token', await sight(s3, { minor: (b.minor + 1) % 65536, deviceUid: 'kabir-phone' }));

console.log('\nRoster:');
for (const a of (await api('GET', `/sessions/${session.id}`, prof)).body.attendance)
  console.log(`  ${a.name.padEnd(8)} ${a.status || 'absent'}`);
await api('POST', `/sessions/${session.id}/close`, prof);
console.log('\nSession closed.');
