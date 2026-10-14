-- ProxyProof schema. Idempotent: safe to run on every startup.

CREATE TABLE IF NOT EXISTS users (
  id            SERIAL PRIMARY KEY,
  email         TEXT UNIQUE NOT NULL,
  name          TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  role          TEXT NOT NULL CHECK (role IN ('student', 'organiser', 'admin')),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS courses (
  id           SERIAL PRIMARY KEY,
  code         TEXT UNIQUE NOT NULL,          -- e.g. "CSE1001"
  name         TEXT NOT NULL,
  organiser_id INT NOT NULL REFERENCES users(id)
);

-- "Student registered" = enrolled in the session's course.
CREATE TABLE IF NOT EXISTS enrollments (
  course_id  INT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  student_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  PRIMARY KEY (course_id, student_id)
);

-- One approved device per student (Phase 3 fills public_key / approval flow).
CREATE TABLE IF NOT EXISTS devices (
  id          SERIAL PRIMARY KEY,
  user_id     INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_uid  TEXT NOT NULL,                  -- stable install id reported by the app
  public_key  TEXT,                           -- PEM/base64 of the Keystore public key
  status      TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'revoked')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  decided_at  TIMESTAMPTZ,
  decided_by  INT REFERENCES users(id)
);
CREATE UNIQUE INDEX IF NOT EXISTS one_approved_device_per_user
  ON devices(user_id) WHERE status = 'approved';
-- Phase 3: two Keystore keys per phone. public_key = "device key" (signs every request,
-- no prompt); bio_public_key = "fingerprint key" (biometric-gated, dies on new enrolment).
-- device_uid = sha256(device public key), so the id can't be faked without the key.
ALTER TABLE devices ADD COLUMN IF NOT EXISTS bio_public_key TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS model TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS last_ts BIGINT NOT NULL DEFAULT 0;  -- replay guard
CREATE INDEX IF NOT EXISTS devices_by_uid ON devices(device_uid);

CREATE TABLE IF NOT EXISTS sessions (
  id             SERIAL PRIMARY KEY,
  course_id      INT NOT NULL REFERENCES courses(id),
  organiser_id   INT NOT NULL REFERENCES users(id),
  short_code     INT NOT NULL CHECK (short_code BETWEEN 0 AND 65535),  -- iBeacon major
  secret         TEXT NOT NULL,               -- hex, never leaves the server
  status         TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'closed')),
  rssi_threshold INT NOT NULL DEFAULT -75,
  presence_pct   INT NOT NULL DEFAULT 80,
  started_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  closed_at      TIMESTAMPTZ
);
-- A short code only has to be unique among sessions that are currently broadcasting.
CREATE UNIQUE INDEX IF NOT EXISTS active_short_code
  ON sessions(short_code) WHERE status = 'active';

CREATE TABLE IF NOT EXISTS attendance (
  id          SERIAL PRIMARY KEY,
  session_id  INT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  student_id  INT NOT NULL REFERENCES users(id),
  device_uid  TEXT,                           -- NULL for manual marks
  status      TEXT NOT NULL CHECK (status IN ('present', 'review', 'absent')),
  source      TEXT NOT NULL DEFAULT 'ble' CHECK (source IN ('ble', 'manual')),
  first_seen  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (session_id, student_id)
);
-- Anti-proxy: one phone can mark only one student per session.
CREATE UNIQUE INDEX IF NOT EXISTS one_device_per_session
  ON attendance(session_id, device_uid) WHERE device_uid IS NOT NULL;

-- Phase 5: presence over the whole class + spot checks.
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS expected_minutes INT NOT NULL DEFAULT 50;
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS finalized_at TIMESTAMPTZ;  -- teacher pressed "Approve all"

-- A spot check opens at starts_at. Each marked student gets it with their next sighting
-- (delivered_at) and must answer with a fingerprint signature before deadline (+20 s).
-- Students out of range when it opens can still get it for 2 minutes: the make-up check.
CREATE TABLE IF NOT EXISTS spot_checks (
  id         SERIAL PRIMARY KEY,
  session_id INT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  starts_at  TIMESTAMPTZ NOT NULL,
  auto       BOOLEAN NOT NULL DEFAULT true
);
CREATE TABLE IF NOT EXISTS spot_check_results (
  spot_check_id INT NOT NULL REFERENCES spot_checks(id) ON DELETE CASCADE,
  student_id    INT NOT NULL REFERENCES users(id),
  delivered_at  TIMESTAMPTZ NOT NULL,
  deadline      TIMESTAMPTZ NOT NULL,
  responded_at  TIMESTAMPTZ,
  PRIMARY KEY (spot_check_id, student_id)
);

-- Every accepted sighting; the presence timeline is built from these.
CREATE TABLE IF NOT EXISTS sightings (
  id          BIGSERIAL PRIMARY KEY,
  session_id  INT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  student_id  INT NOT NULL REFERENCES users(id),
  time_window BIGINT NOT NULL,                -- floor(unix/10) the token belonged to
  rssi_median INT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS sightings_by_session ON sightings(session_id, student_id);
