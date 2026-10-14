# Demo video script (~3½ min)

**Setup before recording**
- Open https://proxyproof.onrender.com once to wake the free server (first load ~50 s).
- Laptop: dashboard logged in as `prof@proxyproof.test` (screen recording on).
- Teacher beacon: either the laptop (`py tools\laptop_beacon.py`) or a second phone with the APK
  logged in as `prof@`. Student: your S24 with the APK, logged in as `student1@` (Aarav).
- Phone screen recording on (Samsung: swipe down → Screen recorder), or film the phone with another camera.
- To show the "phone change" part: log in as admin in a second browser tab (`admin@proxyproof.test`).

| Time | Show | Say (one line each) |
|---|---|---|
| 0:00 | Title / README top | "ProxyProof: Bluetooth attendance that a friend can't mark for you." |
| 0:10 | Teacher taps **Start** (app) or beacon script starts; dashboard shows **Live** | "The teacher taps Start. The phone broadcasts an iBeacon whose token changes every 10 seconds — the secret stays on the server." |
| 0:30 | Student taps **Start attendance** → fingerprint prompt → green tick | "The student's phone hears it, signs the report with a hardware key, and confirms with the fingerprint once." |
| 0:45 | Dashboard row flips to **Present**, last seen ticking | "The dashboard updates live over websockets." |
| 1:00 | Dashboard **Spot check now** → phone vibrates → fingerprint → **Spot check passed** | "A random spot check: 20 seconds to prove the owner is still holding the phone in the room." |
| 1:25 | Walk away with the phone (or show "too far" message) | "Signal strength is judged on the server from the median of samples, so leaving the room shows up." |
| 1:40 | (Optional) laptop_student.py with student2 trying with a far RSSI / show error screens | "Old or guessed tokens, far-away phones and borrowed phones are all rejected." |
| 2:00 | **Close session** → summary **"X present · Y need review · Z absent"** → **Approve all** | "At the end, clear cases are decided automatically; the teacher only looks at flagged ones. 20 seconds per class." |
| 2:25 | **Export CSV** | "CSV for the register." |
| 2:35 | Student app → **My attendance** → course → **Can I bunk?** slider | "Students see their percentage and how many classes they can safely skip under the 75% rule." |
| 2:55 | Admin tab: **Device approvals** (log in as student on another phone/laptop to create one) | "A new phone — or a phone whose fingerprints changed — needs admin approval, so you can't hand your account to a friend's phone." |
| 3:15 | README threat-model table | "Every attack we considered and its defence is in the README." |
| 3:30 | End | |

**Tips**: keep the phone close to the beacon (−30 to −60 dBm). Start the student right after
starting the session so "in range %" stays high. Don't leave the session idle for long before recording.
