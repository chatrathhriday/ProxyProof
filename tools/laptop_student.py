"""Laptop-as-student scanner for testing with a single phone.

The phone runs the organiser app (broadcasting the iBeacon); this script uses the laptop's
Bluetooth to hear it, logs in as a student and reports sightings exactly like the app does.

    pip install bleak
    python tools/laptop_student.py --email student1@proxyproof.test
"""
import argparse
import asyncio
import json
import time
import urllib.error
import urllib.request

from bleak import BleakScanner

BEACON_UUID = bytes.fromhex("b55d5a77aef84366832a9747001afeeb")  # must match backend/src/tokens.js
APPLE = 0x004C


def call(base, path, body, token=None):
    req = urllib.request.Request(base + path, json.dumps(body).encode(), {"content-type": "application/json"})
    if token:
        req.add_header("authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        return e.code, json.load(e)


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--api", default="http://localhost:3000")
    ap.add_argument("--email", default="student1@proxyproof.test")
    ap.add_argument("--password", default="password123")
    ap.add_argument("--device", default="laptop-scanner")
    args = ap.parse_args()

    status, res = call(args.api, "/auth/login", {"email": args.email, "password": args.password})
    if status != 200:
        raise SystemExit(f"login failed: {res}")
    token = res["token"]
    print(f"Logged in as {res['user']['name']}. Scanning... (Ctrl+C to stop)")

    samples = []  # (time, major, minor, rssi)

    def on_adv(device, adv):
        data = adv.manufacturer_data.get(APPLE)
        if not data or len(data) < 23 or data[0:2] != b"\x02\x15" or data[2:18] != BEACON_UUID:
            return
        major, minor = int.from_bytes(data[18:20], "big"), int.from_bytes(data[20:22], "big")
        samples.append((time.time(), major, minor, adv.rssi))

    async with BleakScanner(on_adv):
        while True:
            await asyncio.sleep(10)
            cutoff = time.time() - 10
            recent = [s for s in samples if s[0] >= cutoff]
            samples[:] = recent
            if not recent:
                print("  no beacon heard in the last 10 s")
                continue
            _, major, minor, _ = recent[-1]
            rssi = [s[3] for s in recent if s[1] == major][-30:]
            status, res = call(args.api, "/attendance/sighting",
                               {"major": major, "minor": minor, "rssi": rssi, "deviceUid": args.device}, token)
            print(f"  heard major={major} minor={minor} ({len(rssi)} samples) -> {status} {res}")


asyncio.run(main())
