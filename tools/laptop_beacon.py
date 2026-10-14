"""Laptop-as-organiser beacon for testing the student app on a single phone.

Logs in as the organiser, starts a session (or resumes one) and broadcasts the rotating
iBeacon from the laptop's Bluetooth, fetching each new token from the server.

    python tools/laptop_beacon.py --course CSE1001
"""
import argparse
import asyncio
import json
import urllib.error
import urllib.request

from winrt.windows.devices.bluetooth.advertisement import (
    BluetoothLEAdvertisementPublisher,
    BluetoothLEManufacturerData,
)
from winrt.windows.storage.streams import DataWriter

APPLE = 0x004C


def call(base, method, path, token=None, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(base + path, data, {"content-type": "application/json"}, method=method)
    if token:
        req.add_header("authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        return e.code, json.load(e)


def ibeacon_publisher(uuid, major, minor):
    payload = bytes([0x02, 0x15]) + bytes.fromhex(uuid.replace("-", "")) + \
        major.to_bytes(2, "big") + minor.to_bytes(2, "big") + (-59 & 0xFF).to_bytes(1, "big")
    writer = DataWriter()
    writer.write_bytes(payload)
    md = BluetoothLEManufacturerData()
    md.company_id = APPLE
    md.data = writer.detach_buffer()
    pub = BluetoothLEAdvertisementPublisher()
    pub.advertisement.manufacturer_data.append(md)
    return pub


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--api", default="http://localhost:3000")
    ap.add_argument("--email", default="prof@proxyproof.test")
    ap.add_argument("--password", default="password123")
    ap.add_argument("--course", default="CSE1001")
    args = ap.parse_args()

    _, res = call(args.api, "POST", "/auth/login", body={"email": args.email, "password": args.password})
    token = res["token"]
    _, courses = call(args.api, "GET", "/courses", token)
    course = next(c for c in courses if c["code"] == args.course)
    _, sessions = call(args.api, "GET", "/sessions", token)
    live = next((s for s in sessions if s["course_id"] == course["id"] and s["status"] == "active"), None)
    session = live or call(args.api, "POST", "/sessions", token, {"courseId": course["id"]})[1]
    print(f"Session {session['id']} ({args.course}) {'resumed' if live else 'started'}. Ctrl+C to stop.")

    pub = None
    try:
        while True:
            status, b = call(args.api, "GET", f"/sessions/{session['id']}/beacon", token)
            if status != 200:
                raise SystemExit(f"beacon error: {b}")
            if pub:
                pub.stop()
            pub = ibeacon_publisher(b["uuid"], b["major"], b["minor"])
            pub.start()
            await asyncio.sleep(0.5)
            print(f"  broadcasting major={b['major']} minor={b['minor']} status={pub.status}")
            await asyncio.sleep(b["msUntilNext"] / 1000 + 0.3)
    finally:
        if pub:
            pub.stop()


asyncio.run(main())
