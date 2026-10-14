import express from 'express';
import { query, one } from '../db.js';
import { requireRole } from '../auth.js';
import { matchWindow } from '../tokens.js';
import { allow } from '../rateLimit.js';

export const attendanceRouter = express.Router();

const median = (xs) => {
  const s = [...xs].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : Math.round((s[m - 1] + s[m]) / 2);
};

// A student's phone reports: "I heard beacon (major, minor) with these RSSI samples".
// Each check below rejects one way of cheating; order goes cheapest-first.
attendanceRouter.post('/sighting', requireRole('student'), async (req, res) => {
  const { major, minor, rssi, deviceUid } = req.body || {};
  const studentId = req.user.id;

  if (!Number.isInteger(major) || !Number.isInteger(minor) || !Array.isArray(rssi) || rssi.length === 0 || !deviceUid)
    return res.status(400).json({ error: 'major, minor, rssi[] and deviceUid required' });

  // 1. Rate limit per device AND per account (stops token brute-forcing).
  if (!allow(`dev:${deviceUid}`) || !allow(`user:${studentId}`))
    return res.status(429).json({ error: 'too many attempts' });

  // 2. Session exists and is live.
  const session = await one(
    `SELECT s.*, c.code || ' · ' || c.name AS course FROM sessions s JOIN courses c ON c.id = s.course_id
     WHERE s.short_code = $1 AND s.status = 'active'`,
    [major]
  );
  if (!session) return res.status(404).json({ error: 'no active session for this beacon' });

  // 3. Student is registered for this course.
  const enrolled = await one('SELECT 1 FROM enrollments WHERE course_id = $1 AND student_id = $2', [
    session.course_id,
    studentId,
  ]);
  if (!enrolled) return res.status(403).json({ error: 'not enrolled in this course' });

  // 4. Token is fresh (current 10 s window ±1). A screenshot/relayed token dies in ~30 s.
  const window = matchWindow(session.secret, minor);
  if (window === null) return res.status(422).json({ error: 'stale or invalid token' });

  // 5. Physically close: median RSSI (robust to one-off spikes) must clear the threshold.
  const samples = rssi.filter(Number.isFinite).map(Math.round);
  if (samples.length === 0) return res.status(400).json({ error: 'no valid rssi samples' });
  const rssiMedian = median(samples);
  if (rssiMedian < session.rssi_threshold)
    return res.status(422).json({ error: 'too far from the beacon', rssiMedian, threshold: session.rssi_threshold });

  // 6. One device = one student per session, and a student can't swap phones mid-session.
  const existing = await one('SELECT * FROM attendance WHERE session_id = $1 AND (device_uid = $2 OR student_id = $3)', [
    session.id,
    deviceUid,
    studentId,
  ]);
  if (existing && (existing.student_id !== studentId || (existing.device_uid && existing.device_uid !== deviceUid)))
    return res.status(409).json({ error: 'device already used for another student in this session' });

  if (!existing) {
    try {
      await query(
        `INSERT INTO attendance (session_id, student_id, device_uid, status, source)
         VALUES ($1, $2, $3, 'present', 'ble')`,
        [session.id, studentId, deviceUid]
      );
    } catch (e) {
      // Lost a race with another request using the same device/student.
      if (e.code === '23505') return res.status(409).json({ error: 'device already used in this session' });
      throw e;
    }
  }

  await query('INSERT INTO sightings (session_id, student_id, time_window, rssi_median) VALUES ($1, $2, $3, $4)', [
    session.id,
    studentId,
    window,
    rssiMedian,
  ]);

  res.json({ ok: true, sessionId: session.id, course: session.course, status: existing?.status || 'present', rssiMedian });
});
