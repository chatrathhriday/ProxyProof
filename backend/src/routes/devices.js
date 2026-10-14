import express from 'express';
import { query, one } from '../db.js';
import { requireRole } from '../auth.js';
import { parsePublicKey, fingerprint } from '../signing.js';

export const devicesRouter = express.Router();

const view = (d) => ({ id: d.id, status: d.status, model: d.model, deviceUid: d.device_uid, createdAt: d.created_at });

// Called by the student app after every login. Idempotent.
//  - first phone ever          -> approved automatically ("bind on first login")
//  - same phone, same keys     -> whatever it already is
//  - any other phone / new keys (e.g. fingerprints changed, keys wiped) -> pending admin approval
//  - phone already bound to someone else -> refused (one phone can't serve two students)
devicesRouter.post('/register', requireRole('student'), async (req, res) => {
  const { devicePublicKey, bioPublicKey, model } = req.body || {};
  if (!parsePublicKey(devicePublicKey || '') || !parsePublicKey(bioPublicKey || ''))
    return res.status(400).json({ error: 'devicePublicKey and bioPublicKey must be base64 P-256 SPKI keys' });
  const uid = fingerprint(devicePublicKey);
  const userId = req.user.id;

  const taken = await one(
    "SELECT 1 FROM devices WHERE device_uid = $1 AND user_id <> $2 AND status IN ('approved', 'pending')",
    [uid, userId]
  );
  if (taken) return res.status(409).json({ error: 'This phone is already registered to another student.' });

  const mine = await one(
    "SELECT * FROM devices WHERE device_uid = $1 AND user_id = $2 AND status <> 'revoked' ORDER BY id DESC LIMIT 1",
    [uid, userId]
  );
  if (mine) return res.json(view(mine));

  const hasApproved = await one("SELECT 1 FROM devices WHERE user_id = $1 AND status = 'approved'", [userId]);
  // A newer pending request replaces an older one, so admins only see the latest.
  await query("UPDATE devices SET status = 'revoked', decided_at = now() WHERE user_id = $1 AND status = 'pending'", [userId]);
  const d = await one(
    `INSERT INTO devices (user_id, device_uid, public_key, bio_public_key, model, status, decided_at)
     VALUES ($1, $2, $3, $4, $5, $6, CASE WHEN $6 = 'approved' THEN now() END) RETURNING *`,
    [userId, uid, devicePublicKey, bioPublicKey, String(model || 'unknown').slice(0, 80), hasApproved ? 'pending' : 'approved']
  );
  res.status(201).json(view(d));
});

devicesRouter.get('/pending', requireRole('admin'), async (req, res) => {
  res.json(
    await query(
      `SELECT d.id, d.model, d.created_at, u.id AS user_id, u.name, u.email,
              cur.model AS current_model, cur.decided_at AS current_since
       FROM devices d JOIN users u ON u.id = d.user_id
       LEFT JOIN devices cur ON cur.user_id = d.user_id AND cur.status = 'approved'
       WHERE d.status = 'pending' ORDER BY d.created_at`
    )
  );
});

// Approving a new phone retires the old one: a student is bound to exactly one device.
devicesRouter.post('/:id/approve', requireRole('admin'), async (req, res) => {
  const d = await one("SELECT * FROM devices WHERE id = $1 AND status = 'pending'", [req.params.id]);
  if (!d) return res.status(404).json({ error: 'no such pending device' });
  await query("UPDATE devices SET status = 'revoked', decided_at = now(), decided_by = $2 WHERE user_id = $1 AND status = 'approved'", [
    d.user_id,
    req.user.id,
  ]);
  const updated = await one(
    "UPDATE devices SET status = 'approved', decided_at = now(), decided_by = $2 WHERE id = $1 RETURNING *",
    [d.id, req.user.id]
  );
  res.json(view(updated));
});

devicesRouter.post('/:id/reject', requireRole('admin'), async (req, res) => {
  const updated = await one(
    "UPDATE devices SET status = 'revoked', decided_at = now(), decided_by = $2 WHERE id = $1 AND status = 'pending' RETURNING *",
    [req.params.id, req.user.id]
  );
  if (!updated) return res.status(404).json({ error: 'no such pending device' });
  res.json(view(updated));
});
