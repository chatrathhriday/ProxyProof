// Demo data so the app looks like a real semester: six courses with timetables and four weeks
// of past classes. Generated history is flagged `sessions.demo = true` and its attendance rows
// are 'manual' (there are no raw sightings behind them), so it never mixes with real marking.
import crypto from 'node:crypto';
import { query, one } from './db.js';
import { newSecret } from './tokens.js';

// rate = how often demo students attend; PHY1701 deliberately sits below the 75% rule.
export const DEMO_COURSES = [
  { code: 'CSE1001', name: 'Intro to Programming', rate: 0.9, slots: [[1, '09:00', 'SJT 304'], [3, '09:00', 'SJT 304'], [5, '09:00', 'SJT 304']] },
  { code: 'MAT2002', name: 'Discrete Mathematics', rate: 0.85, slots: [[2, '11:00', 'MB 210'], [4, '11:00', 'MB 210']] },
  { code: 'PHY1701', name: 'Engineering Physics', rate: 0.66, slots: [[1, '14:00', 'TT 105'], [4, '14:00', 'TT 105']] },
  { code: 'ECE2001', name: 'Digital Logic Design', rate: 0.8, slots: [[3, '10:00', 'SMV 118'], [5, '10:00', 'SMV 118']] },
  { code: 'CSE2001', name: 'Data Structures', rate: 0.93, slots: [[2, '08:00', 'SJT 512'], [4, '08:00', 'SJT 512'], [6, '08:00', 'SJT 512']] },
  { code: 'HUM1021', name: 'Ethics and Values', rate: 0.78, slots: [[3, '15:00', 'AB1 201']] },
];

const plus50 = (hhmm) => {
  const [h, m] = hhmm.split(':').map(Number);
  const t = h * 60 + m + 50;
  return `${String(Math.floor(t / 60)).padStart(2, '0')}:${String(t % 60).padStart(2, '0')}`;
};
const scheduleOf = (c) => c.slots.map(([d, s, room]) => ({ d, s, e: plus50(s), room }));

// Stable "random": the same student/session pair always gets the same outcome.
const roll = (a, b) => crypto.createHash('sha256').update(`${a}:${b}`).digest().readUInt32BE(0) / 2 ** 32;

/** Class start times (IST timetable) for the last `days` days, oldest first, excluding today. */
function pastSlots(course, days = 28, now = Date.now()) {
  const IST = 5.5 * 3600_000;
  const out = [];
  for (let back = days; back >= 1; back--) {
    const dayIst = new Date(now + IST - back * 86400_000);
    const dow = dayIst.getUTCDay() || 7; // 1..7, Monday = 1
    for (const [d, s] of course.slots) {
      if (d !== dow) continue;
      const [h, m] = s.split(':').map(Number);
      const startUtc = Date.UTC(dayIst.getUTCFullYear(), dayIst.getUTCMonth(), dayIst.getUTCDate(), h, m) - IST;
      out.push(new Date(startUtc));
    }
  }
  return out;
}

/** Creates the demo courses (with timetables) and their past classes. Idempotent. */
export async function seedDemoCourses(organiserId) {
  for (const c of DEMO_COURSES) {
    let course = await one('SELECT * FROM courses WHERE code = $1', [c.code]);
    if (!course)
      course = await one('INSERT INTO courses (code, name, organiser_id, schedule) VALUES ($1, $2, $3, $4) RETURNING *', [
        c.code,
        c.name,
        organiserId,
        JSON.stringify(scheduleOf(c)),
      ]);
    else await query('UPDATE courses SET schedule = $2 WHERE id = $1', [course.id, JSON.stringify(scheduleOf(c))]);

    for (const start of pastSlots(c)) {
      // skip if any session (real or demo) already exists within an hour of this slot
      const exists = await one(
        "SELECT 1 FROM sessions WHERE course_id = $1 AND started_at BETWEEN $2::timestamptz - interval '1 hour' AND $2::timestamptz + interval '1 hour'",
        [course.id, start]
      );
      if (exists) continue;
      await query(
        `INSERT INTO sessions (course_id, organiser_id, short_code, secret, status, started_at, closed_at, finalized_at, demo, expected_minutes)
         VALUES ($1, $2, $3, $4, 'closed', $5, $6, $6, true, 50)`,
        [course.id, course.organiser_id, crypto.randomInt(0, 65536), newSecret(), start, new Date(start.getTime() + 50 * 60_000)]
      );
    }
  }
}

/** Enrols a student in every demo course and gives them a realistic attendance history. */
export async function enrolInDemo(studentId) {
  for (const c of DEMO_COURSES) {
    const course = await one('SELECT id FROM courses WHERE code = $1', [c.code]);
    if (!course) continue;
    await query('INSERT INTO enrollments VALUES ($1, $2) ON CONFLICT DO NOTHING', [course.id, studentId]);
    const sessions = await query("SELECT id FROM sessions WHERE course_id = $1 AND demo AND status = 'closed'", [course.id]);
    for (const s of sessions) {
      if (roll(studentId, s.id) > c.rate) continue; // absent = no attendance row
      await query(
        `INSERT INTO attendance (session_id, student_id, status, source) VALUES ($1, $2, 'present', 'manual')
         ON CONFLICT (session_id, student_id) DO NOTHING`,
        [s.id, studentId]
      );
    }
  }
}
