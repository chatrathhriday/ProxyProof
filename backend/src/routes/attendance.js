import express from 'express';
import { query, one } from '../db.js';
import { requireRole } from '../auth.js';
import { matchWindow } from '../tokens.js';
import { allow } from '../rateLimit.js';
import { verify, MAX_CLOCK_SKEW_MS } from '../signing.js';
import { emit } from '../live.js';
import { now } from '../clock.js';
import { deliverSpotCheck, answerSpotCheck } from '../presence.js';

export const attendanceRouter = express.Router();

const median = (xs) => {
  const s = [...xs].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : Math.round((s[m - 1] + s[m]) / 2);
};

/**
 * Shared front door for every request a phone signs. Body: { payload: "<JSON string>", sig, bioSig? }.
 * Checks rate limit, approved device, device-key signature, timestamp freshness and replay.
 * Returns { device, body } or sends the error response and returns null.
 */
async function signedRequest(req, res) {
  const studentId = req.user.id;
  // Rate limit per account first (stops token brute-forcing); per device once we know it.
  if (!allow(`user:${studentId}`)) return void res.status(429).json({ error: 'too many attempts' });

  const { payload, sig } = req.body || {};
  const device = await one("SELECT * FROM devices WHERE user_id = $1 AND status = 'approved'", [studentId]);
  if (!device) return void res.status(403).json({ error: 'device not approved', code: 'DEVICE_NOT_APPROVED' });
  if (!verify(device.public_key, payload, sig))
    return void res.status(401).json({ error: 'bad device signature', code: 'BAD_SIGNATURE' });
  if (!allow(`dev:${device.device_uid}`)) return void res.status(429).json({ error: 'too many attempts' });

  let body;
  try {
    body = JSON.parse(payload);
  } catch {
    return void res.status(400).json({ error: 'payload is not JSON' });
  }
  // Fresh and not replayed: timestamp near server time and newer than the last one we saw.
  if (!Number.isInteger(body.ts) || Math.abs(now() - body.ts) > MAX_CLOCK_SKEW_MS)
    return void res.status(422).json({ error: 'clock skew too large' });
  if (body.ts <= Number(device.last_ts)) return void res.status(409).json({ error: 'replayed request' });
  await query('UPDATE devices SET last_ts = $2 WHERE id = $1', [device.id, body.ts]);
  return { device, body };
}

// "I heard beacon (major, minor) with these RSSI samples."
//   payload = {"major":..,"minor":..,"rssi":[..],"ts":<unix ms>}
//   bioSig  = fingerprint-key signature over payload (needed for the first mark in a session)
// Each check rejects one way of cheating; order goes cheapest-first.
attendanceRouter.post('/sighting', requireRole('student'), async (req, res) => {
  const studentId = req.user.id;
  const signed = await signedRequest(req, res);
  if (!signed) return;
  const { device, body } = signed;
  const { major, minor, rssi } = body;
  if (!Number.isInteger(major) || !Number.isInteger(minor) || !Array.isArray(rssi) || rssi.length === 0)
    return res.status(400).json({ error: 'payload needs major, minor, rssi[] and ts' });

  // Session exists and is live.
  const session = await one(
    `SELECT s.*, c.code || ' · ' || c.name AS course FROM sessions s JOIN courses c ON c.id = s.course_id
     WHERE s.short_code = $1 AND s.status = 'active'`,
    [major]
  );
  if (!session) return res.status(404).json({ error: 'no active session for this beacon' });

  // Student is registered for this course.
  const enrolled = await one('SELECT 1 FROM enrollments WHERE course_id = $1 AND student_id = $2', [
    session.course_id,
    studentId,
  ]);
  if (!enrolled) return res.status(403).json({ error: 'not enrolled in this course' });

  // BLE token is fresh (current 10 s window ±1). A screenshot/relayed token dies in ~30 s.
  const window = matchWindow(session.secret, minor);
  if (window === null) return res.status(422).json({ error: 'stale or invalid token' });

  // Physically close: median RSSI (robust to one-off spikes) must clear the threshold.
  const samples = rssi.filter(Number.isFinite).map(Math.round);
  if (samples.length === 0) return res.status(400).json({ error: 'no valid rssi samples' });
  const rssiMedian = median(samples);
  if (rssiMedian < session.rssi_threshold)
    return res.status(422).json({ error: 'too far from the beacon', rssiMedian, threshold: session.rssi_threshold });

  // One device = one student per session (device_uid is derived from the device key).
  const existing = await one('SELECT * FROM attendance WHERE session_id = $1 AND (device_uid = $2 OR student_id = $3)', [
    session.id,
    device.device_uid,
    studentId,
  ]);
  if (existing && (existing.student_id !== studentId || (existing.device_uid && existing.device_uid !== device.device_uid)))
    return res.status(409).json({ error: 'device already used for another student in this session' });

  if (!existing) {
    // First mark in a session needs the owner's fingerprint (fingerprint-key signature).
    // Later sightings only need the device key, so there's no prompt every 10 s.
    if (!verify(device.bio_public_key, req.body.payload, req.body.bioSig))
      return res.status(428).json({ error: 'fingerprint check-in required', code: 'BIO_REQUIRED' });
    try {
      await query(
        `INSERT INTO attendance (session_id, student_id, device_uid, status, source, first_seen)
         VALUES ($1, $2, $3, 'present', 'ble', $4)`,
        [session.id, studentId, device.device_uid, new Date(now())]
      );
    } catch (e) {
      // Lost a race with another request using the same device/student.
      if (e.code === '23505') return res.status(409).json({ error: 'device already used in this session' });
      throw e;
    }
    emit(session.id, 'roster');
  }

  // Each accepted sighting is one dot on the presence timeline.
  await query('INSERT INTO sightings (session_id, student_id, time_window, rssi_median, created_at) VALUES ($1, $2, $3, $4, $5)', [
    session.id,
    studentId,
    window,
    rssiMedian,
    new Date(now()),
  ]);
  emit(session.id, 'seen', { studentId, at: new Date(now()).toISOString(), rssi: rssiMedian });

  // If a spot check is open, the reply carries it; the phone then asks for the fingerprint.
  const spotCheck = await deliverSpotCheck(session.id, studentId);
  if (spotCheck?.secondsLeft === 20) emit(session.id, 'roster');

  res.json({
    ok: true,
    sessionId: session.id,
    course: session.course,
    status: existing?.status || 'present',
    rssiMedian,
    spotCheck,
  });
});

// Answer to a spot check: payload = {"spotCheckId":..,"ts":..}, signed by BOTH keys.
// The fingerprint-key signature is the proof that the owner is still holding the phone.
attendanceRouter.post('/spot-check', requireRole('student'), async (req, res) => {
  const signed = await signedRequest(req, res);
  if (!signed) return;
  const { device, body } = signed;
  if (!Number.isInteger(body.spotCheckId)) return res.status(400).json({ error: 'payload needs spotCheckId' });
  if (!verify(device.bio_public_key, req.body.payload, req.body.bioSig))
    return res.status(401).json({ error: 'fingerprint signature required', code: 'BIO_REQUIRED' });
  const err = await answerSpotCheck(body.spotCheckId, req.user.id);
  if (err) return res.status(422).json({ error: err });
  const sc = await one('SELECT session_id FROM spot_checks WHERE id = $1', [body.spotCheckId]);
  emit(sc.session_id, 'roster');
  res.json({ ok: true });
});
