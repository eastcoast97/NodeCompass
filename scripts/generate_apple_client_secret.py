#!/usr/bin/env python3
"""
Generate an Apple client-secret JWT for Supabase's Apple OAuth provider.

Apple limits these JWTs to a **maximum 6-month lifetime**. When Supabase starts
rejecting auth attempts with an "expired" error (or ~30 days before expiry as
a safety buffer), re-run this script and paste the new JWT into:

    Supabase Dashboard → Authentication → Providers → Apple
                                         → "Secret Key (for OAuth)"

Requirements:
    pip3 install --user PyJWT cryptography

Usage:
    python3 generate_apple_client_secret.py path/to/AuthKey_<KEY_ID>.p8

The .p8 file is the one-time download you got from:
    https://developer.apple.com/account/resources/authkeys/list
Keep it in 1Password / iCloud Drive — Apple will NOT let you re-download it.
"""

import jwt
import time
import sys
import datetime
from pathlib import Path

# --- Config (update if you rotate keys / change bundle ID / team) -----------

TEAM_ID   = "XB6YUT7453"
KEY_ID    = "RUSUYGZX4G"
CLIENT_ID = "com.nodecompass.app"   # Your iOS app's bundle ID
LIFETIME_SECONDS = 15_552_000        # 180 days (Apple's hard max is 6 months)

# ---------------------------------------------------------------------------


def main() -> None:
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(1)

    key_path = Path(sys.argv[1])
    if not key_path.exists():
        sys.exit(f"Error: {key_path} not found.")

    private_key = key_path.read_text()

    now = int(time.time())
    payload = {
        "iss": TEAM_ID,
        "iat": now,
        "exp": now + LIFETIME_SECONDS,
        "aud": "https://appleid.apple.com",
        "sub": CLIENT_ID,
    }
    token = jwt.encode(
        payload,
        private_key,
        algorithm="ES256",
        headers={"kid": KEY_ID},
    )

    expiry = datetime.datetime.fromtimestamp(now + LIFETIME_SECONDS)
    print(token)
    print()
    print(f"# Expires: {expiry.strftime('%Y-%m-%d')}")
    print("# Paste the line above into:")
    print("#   Supabase → Auth → Providers → Apple → Secret Key (for OAuth)")


if __name__ == "__main__":
    main()
