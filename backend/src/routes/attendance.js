import express from 'express';
import { query, one } from '../db.js';
import { requireRole } from '../auth.js';
import { matchWindow } from '../tokens.js';
import { allow } from '../rateLimit.js';
import { verify, MAX_CLOCK_SKEW_MS } from '../signing.js';
import { emit } from '../live.js';

export const attendanceRouter = express.Router();

const median = (xs) => {
  const s = [...xs].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : Math.round((s[m - 1] + s[m]) / 2);
};

// Body: { payload: "<JSON string>", sig, bioSig? }
//   payload = {"major":..,"minor":..,"rssi":[..],"ts":<unix ms>}
//   sig     = device key signature over payload (every request)
//   bioSig  = fingerprint key signature over payload (needed for the first mark in a session)
// Each check below rejects one way of cheating; order goes cheapest-first.
attendanceRouter.post('/sighting', requireRole('student'), async (req, res) => {
  const studentId = req.user.id;

  // 1. Rate limit per account (stops token brute-forcing). Per-device limit follows below.
  if (!allow(`user:${studentId}`)) return res.status(429).json({ error: 'too many attempts' });

  // 2. Request comes from this student's approved phone: valid device-key signature.
  const { payload, sig, bioSig } = req.body || {};
  const device = await one("SELECT * FROM devices WHERE user_id = $1 AND status = 'approved'", [studentId]);
  if (!device) return res.status(403).json({ error: 'device not approved', code: 'DEVICE_NOT_APPROVED' });
  if (!verify(device.public_key, payload, sig))
    return res.status(401).json({ error: 'bad device signature', code: 'BAD_SIGNATURE' });
  if (!allow(`dev:${device.device_uid}`)) return res.status(429).json({ error: 'too many attempts' });

  let body;
  try {
    body = JSON.parse(payload);
  } catch {
    return res.status(400).json({ error: 'payload is not JSON' });
  }
  const { major, minor, rssi, ts } = body;
  if (!Number.isInteger(major) || !Number.isInteger(minor) || !Array.isArray(rssi) || rssi.length === 0 || !Number.isInteger(ts))
    return res.status(400).json({ error: 'payload needs major, minor, rssi[] and ts' });

  // 3. Fresh and not replayed: timestamp near server time and newer than the last one we saw.
  if (Math.abs(Date.now() - ts) > MAX_CLOCK_SKEW_MS) return res.status(422).json({ error: 'clock skew too large' });
  if (ts <= Number(device.last_ts)) return res.status(409).json({ error: 'replayed request' });
  await query('UPDATE devices SET last_ts = $2 WHERE id = $1', [device.id, ts]);

  // 4. Session exists and is live.
  const session = await one(
    `SELECT s.*, c.code || ' · ' || c.name AS course FROM sessions s JOIN courses c ON c.id = s.course_id
     WHERE s.short_code = $1 AND s.status = 'active'`,
    [major]
  );
  if (!session) return res.status(404).json({ error: 'no active session for this beacon' });

  // 5. Student is registered for this course.
  const enrolled = await one('SELECT 1 FROM enrollments WHERE course_id = $1 AND student_id = $2', [
    session.course_id,
    studentId,
  ]);
  if (!enrolled) return res.status(403).json({ error: 'not enrolled in this course' });

  // 6. BLE token is fresh (current 10 s window ±1). A screenshot/relayed token dies in ~30 s.
  const window = matchWindow(session.secret, minor);
  if (window === null) return res.status(422).json({ error: 'stale or invalid token' });

  // 7. Physically close: median RSSI (robust to one-off spikes) must clear the threshold.
  const samples = rssi.filter(Number.isFinite).map(Math.round);
  if (samples.length === 0) return res.status(400).json({ error: 'no valid rssi samples' });
  const rssiMedian = median(samples);
  if (rssiMedian < session.rssi_threshold)
    return res.status(422).json({ error: 'too far from the beacon', rssiMedian, threshold: session.rssi_threshold });

  // 8. One device = one student per session (device_uid is derived from the device key).
  const existing = await one('SELECT * FROM attendance WHERE session_id = $1 AND (device_uid = $2 OR student_id = $3)', [
    session.id,
    device.device_uid,
    studentId,
  ]);
  if (existing && (existing.student_id !== studentId || (existing.device_uid && existing.device_uid !== device.device_uid)))
    return res.status(409).json({ error: 'device already used for another student in this session' });

  if (!existing) {
    // 9. First mark in a session needs the owner's fingerprint (fingerprint-key signature).
    //    Later sightings only need the device key, so there's no prompt every 10 s.
    if (!verify(device.bio_public_key, payload, bioSig))
      return res.status(428).json({ error: 'fingerprint check-in required', code: 'BIO_REQUIRED' });
    try {
      await query(
        `INSERT INTO attendance (session_id, student_id, device_uid, status, source)
         VALUES ($1, $2, $3, 'present', 'ble')`,
        [session.id, studentId, device.device_uid]
      );
    } catch (e) {
      // Lost a race with another request using the same device/student.
      if (e.code === '23505') return res.status(409).json({ error: 'device already used in this session' });
      throw e;
    }
    emit(session.id, 'roster');
  }

  await query('INSERT INTO sightings (session_id, student_id, time_window, rssi_median) VALUES ($1, $2, $3, $4)', [
    session.id,
    studentId,
    window,
    rssiMedian,
  ]);
  emit(session.id, 'seen', { studentId, at: new Date().toISOString(), rssi: rssiMedian });

  res.json({ ok: true, sessionId: session.id, course: session.course, status: existing?.status || 'present', rssiMedian });
});
