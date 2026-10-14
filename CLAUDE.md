# ProxyProof: BLE attendance with anti-proxy (VinnovateIT task)
Deadline: 15 Oct, 11:59 PM. Deliver: public GitHub repo, APK, demo video, README.

## Stack
- App: Flutter (Android first). Packages: flutter_ble_peripheral (broadcast),
  flutter_beacon or flutter_blue_plus (scan), local_auth (biometrics).
  Flutter SDK is already downloaded at ~/Documents/flutter_windows_3.47.3-stable.
- Backend: Node.js + Express + PostgreSQL (Supabase/Neon) + Socket.IO. Deploy on Render.
- Dashboard: simple React (Vite) web page for organisers.

## Roles
- Organiser: login, start/close session, live dashboard, manual add/remove, CSV export.
- Student: login, bound to one device, automatic marking, history + attendance %.
- Admin: approves device-change requests.

## BLE broadcast (iBeacon format, works on Android + iOS)
- Fixed app UUID. major = 16-bit session short code. minor = 16-bit rotating token.
- token = first 16 bits of HMAC-SHA256(session_secret, floor(unix_time / 10)).
- session_secret stays on the server; the organiser app fetches tokens over HTTPS.
- Server accepts the current window +/-1 and rate-limits attempts per device.

## Device binding
- On first login, generate a keypair in Android Keystore that requires biometric auth
  and is invalidated when new biometrics are enrolled.
- Server stores the public key. Every attendance request is signed (payload + timestamp).
- New device -> "pending approval" until an admin approves.

## Marking rules (server)
Accept a sighting only if: student registered, token fresh, signature valid for the
bound device, and median RSSI over recent samples >= threshold (default -75 dBm, configurable).
One device can mark only one student per session.

## Continuous presence (keep it simple for the teacher)
- Student app sends sightings every ~10 s; the server builds a presence timeline.
- Present if in range for >= 80% of the session (configurable, hidden under Advanced).
- 1 automatic random spot check per session: biometric prompt, 20 s to respond;
  a make-up check if the student returns to range within 2 min.
- Clear cases resolve automatically; only unclear cases are flagged.
- End-of-session summary: "X present / Y need review / Z absent" + [Approve all].

## Build order (one phase at a time, test each before moving on)
1. Backend: auth, roles, sessions, token generation/validation, DB schema.
2. CHECKPOINT (go/no-go by hour ~6): phone A broadcasts iBeacon,
   phone B detects it and the server marks attendance.
3. Device binding + signed requests + admin approval.
4. Live dashboard (Socket.IO), manual add/remove, close session, CSV export.
5. Presence timeline, spot check, summary screen.
6. Student history + attendance %, "can I bunk?" calculator (75% rule).
7. README with a threat-model table, iOS notes, "Teacher experience: 20 s per class"; APK; demo video.

## Rules for Claude
- Explain each design decision briefly; I need to understand it for the interview.
- Keep the UI simple and clean. Commit after every working phase.
