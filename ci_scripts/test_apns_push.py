#!/usr/bin/env python3
"""
Send a test APNs push notification to a device.

Requirements:
    pip3 install PyJWT cryptography

Usage:
    python3 test_apns_push.py \
        --key-file /path/to/AuthKey_XXXXXXXXXX.p8 \
        --key-id XXXXXXXXXX \
        --team-id XXXXXXXXXX \
        --bundle-id org.your.bundle.id \
        --device-token <token from Xcode console>

To get the device token, look for this line in the Xcode console after launch:
    "successfully registered for vanilla push notifications"
Add a temp log in PushRegistrationManager.swift:didReceiveVanillaPushToken to print tokenData.toHex()
"""

import argparse
import json
import subprocess
import sys
import time

try:
    import jwt
except ImportError:
    print("Missing dependency. Run: pip3 install PyJWT cryptography")
    sys.exit(1)


APNS_HOST = "https://api.push.apple.com"
APNS_HOST_SANDBOX = "https://api.development.push.apple.com"


def make_jwt(key_file: str, key_id: str, team_id: str) -> str:
    with open(key_file) as f:
        key = f.read()
    return jwt.encode(
        {"iss": team_id, "iat": int(time.time())},
        key,
        algorithm="ES256",
        headers={"kid": key_id},
    )


def send_push(
    token: str,
    bundle_id: str,
    auth_jwt: str,
    title: str,
    body: str,
    sandbox: bool,
) -> None:
    host = APNS_HOST_SANDBOX if sandbox else APNS_HOST
    url = f"{host}/3/device/{token}"

    payload = json.dumps({
        "aps": {
            "alert": {"title": title, "body": body},
            "sound": "default",
        }
    })

    # urllib doesn't support HTTP/2; use curl which does on macOS
    cmd = [
        "curl", "--http2", "--silent", "--write-out", "\nHTTP_STATUS:%{http_code}",
        "-X", "POST", url,
        "-H", f"authorization: bearer {auth_jwt}",
        "-H", f"apns-topic: {bundle_id}",
        "-H", "apns-push-type: alert",
        "-H", "content-type: application/json",
        "-d", payload,
    ]

    result = subprocess.run(cmd, capture_output=True, text=True)
    output = result.stdout

    if "HTTP_STATUS:" in output:
        body_part, status_part = output.rsplit("\nHTTP_STATUS:", 1)
        status = int(status_part.strip())
        body_part = body_part.strip()

        if status == 200:
            print("Push sent successfully (HTTP 200)")
        else:
            print(f"APNs error (HTTP {status}): {body_part}")
            if status == 400:
                print("Tip: 'BadDeviceToken' means the token is wrong or for a different environment (sandbox vs production).")
            elif status == 403:
                print("Tip: 'InvalidProviderToken' means your .p8 key, key ID, or team ID is wrong.")
            elif status == 410:
                print("Tip: 'Unregistered' means the device token is no longer valid.")
            sys.exit(1)
    else:
        print(f"curl error: {result.stderr or output}")
        sys.exit(1)


def main() -> None:
    parser = argparse.ArgumentParser(description="Send a test APNs push notification.")
    parser.add_argument("--key-file", required=True, help="Path to .p8 APNs auth key")
    parser.add_argument("--key-id", required=True, help="10-char Key ID from Apple Developer Portal")
    parser.add_argument("--team-id", required=True, help="10-char Team ID from Apple Developer Portal")
    parser.add_argument("--bundle-id", required=True, help="App bundle ID (e.g. org.example.signal)")
    parser.add_argument("--device-token", required=True, help="Hex device push token from Xcode console")
    parser.add_argument("--title", default="Test Push", help="Notification title")
    parser.add_argument("--body", default="APNs push is working.", help="Notification body")
    parser.add_argument("--sandbox", action="store_true", help="Use sandbox APNs endpoint (for dev builds)")
    ns = parser.parse_args()

    auth_jwt = make_jwt(ns.key_file, ns.key_id, ns.team_id)
    send_push(
        token=ns.device_token,
        bundle_id=ns.bundle_id,
        auth_jwt=auth_jwt,
        title=ns.title,
        body=ns.body,
        sandbox=ns.sandbox,
    )


if __name__ == "__main__":
    main()
