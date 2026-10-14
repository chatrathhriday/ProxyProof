"""Laptop-as-student scanner for testing with a single phone.

The phone runs the organiser app (broadcasting the iBeacon); this script uses the laptop's
Bluetooth to hear it, logs in as a student and reports signed sightings like the app does.
Its "Keystore" is two software keys saved next to this file (a real phone uses hardware).

    pip install bleak cryptography
    python tools/laptop_student.py --email student1@proxyproof.test
"""
import argparse
import asyncio
import base64
import json
import pathlib
import time
import urllib.error
import urllib.request

from bleak import BleakScanner
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec

BEACON_UUID = bytes.fromhex("b55d5a77aef84366832a9747001afeeb")  # must match backend/src/tokens.js
APPLE = 0x004C
KEY_DIR = pathlib.Path(__file__).with_name(".laptop_keys")


def call(base, path, body, token=None):
    req = urllib.request.Request(base + path, json.dumps(body).encode(), {"content-type": "application/json"})
    if token:
        req.add_header("authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        return e.code, json.load(e)


def load_key(name):
    path = KEY_DIR / f"{name}.pem"
    if path.exists():
        return serialization.load_pem_private_key(path.read_bytes(), None)
    KEY_DIR.mkdir(exist_ok=True)
    key = ec.generate_private_key(ec.SECP256R1())
    path.write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                       serialization.NoEncryption()))
    return key


def spki_b64(key):
    der = key.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
    return base64.b64encode(der).decode()


def sign(key, payload):
    return base64.b64encode(key.sign(payload.encode(), ec.ECDSA(hashes.SHA256()))).decode()


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--api", default="http://localhost:3000")
    ap.add_argument("--email", default="student1@proxyproof.test")
    ap.add_argument("--password", default="password123")
    args = ap.parse_args()

    status, res = call(args.api, "/auth/login", {"email": args.email, "password": args.password})
    if status != 200:
        raise SystemExit(f"login failed: {res}")
    token = res["token"]
    device_key, bio_key = load_key("device"), load_key("bio")
    status, dev = call(args.api, "/devices/register",
                       {"devicePublicKey": spki_b64(device_key), "bioPublicKey": spki_b64(bio_key),
                        "model": "Laptop scanner"}, token)
    print(f"Logged in as {res['user']['name']}; device {dev.get('status', dev)}. Scanning... (Ctrl+C to stop)")

    samples = []  # (time, major, minor, rssi)
    checked_in = set()  # majors where the "fingerprint" signature was already accepted

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
            samples[:] = [s for s in samples if s[0] >= cutoff]
            if not samples:
                print("  no beacon heard in the last 10 s")
                continue
            _, major, minor, _ = samples[-1]
            rssi = [s[3] for s in samples if s[1] == major][-30:]
            payload = json.dumps({"major": major, "minor": minor, "rssi": rssi, "ts": int(time.time() * 1000)})
            body = {"payload": payload, "sig": sign(device_key, payload)}
            if major not in checked_in:  # stands in for the fingerprint prompt
                body["bioSig"] = sign(bio_key, payload)
            status, res = call(args.api, "/attendance/sighting", body, token)
            if status == 200:
                checked_in.add(major)
            print(f"  heard major={major} minor={minor} ({len(rssi)} samples) -> {status} {res}")


asyncio.run(main())
