// Demo data: 1 admin, 1 organiser, 3 students, 1 course with everyone enrolled.
// All passwords are "password123" — demo accounts only.
// Run directly (`npm run seed`) or on server start with SEED_DEMO=true (Render free tier has no shell).
// Idempotent: existing users and the course are left as they are.
import 'dotenv/config';
import { pathToFileURL } from 'node:url';
import { initDb, one, query, closeDb } from './db.js';
import { createUser } from './auth.js';
import { seedDemoCourses, enrolInDemo } from './demo.js';

async function upsertUser(email, name, role) {
  return (await one('SELECT * FROM users WHERE email = $1', [email])) ||
    createUser({ email, name, password: 'password123', role });
}

export async function seedDemo() {
  await upsertUser('admin@proxyproof.test', 'Admin', 'admin');
  const prof = await upsertUser('prof@proxyproof.test', 'Prof. Sharma', 'organiser');
  const students = [];
  for (const [i, name] of ['Aarav', 'Diya', 'Kabir'].entries())
    students.push(await upsertUser(`student${i + 1}@proxyproof.test`, name, 'student'));

  const course =
    (await one("SELECT * FROM courses WHERE code = 'CSE1001'")) ||
    (await one("INSERT INTO courses (code, name, organiser_id) VALUES ('CSE1001', 'Intro to Programming', $1) RETURNING *", [prof.id]));
  for (const s of students)
    await query('INSERT INTO enrollments VALUES ($1, $2) ON CONFLICT DO NOTHING', [course.id, s.id]);
  // A fuller semester: six timetabled courses with four weeks of past classes.
  await seedDemoCourses(prof.id);
  for (const s of students) await enrolInDemo(s.id);
  console.log('Seeded: admin@ / prof@ / student1..3@proxyproof.test (password123)');
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  await initDb();
  await seedDemo();
  await closeDb();
}
