#!/usr/bin/env python3
"""Posts a release announcement to X (Twitter).

    VERSION=1.0.0 scripts/post-release.py            # posts
    VERSION=1.0.0 DRY_RUN=1 scripts/post-release.py  # prints the post only

Needs X_API_KEY, X_API_SECRET, X_ACCESS_TOKEN and X_ACCESS_TOKEN_SECRET from an X developer app
with Read and Write permission. Signs the request with OAuth 1.0a using only the standard library.
"""
import base64
import hashlib
import hmac
import json
import os
import secrets
import sys
import time
import urllib.parse
import urllib.request

ENDPOINT = "https://api.x.com/2/tweets"
REPO = "hyppe-cc/tunnels"


def compose(version: str) -> str:
    return (
        f"Tunnels {version} is out ☁️\n\n"
        "Share local projects on your own domain from the macOS menu bar: "
        "`tunnel link` in any folder and it's live.\n\n"
        "Powered by @Cloudflare Tunnel, built with @claudeai.\n\n"
        "brew install --cask hyppe-cc/tap/tunnels\n"
        f"https://github.com/{REPO}/releases/tag/v{version}"
    )


def quote(value: str) -> str:
    return urllib.parse.quote(value, safe="~")


def authorization(method: str, url: str, keys: dict) -> str:
    oauth = {
        "oauth_consumer_key": keys["api_key"],
        "oauth_nonce": secrets.token_hex(16),
        "oauth_signature_method": "HMAC-SHA1",
        "oauth_timestamp": str(int(time.time())),
        "oauth_token": keys["access_token"],
        "oauth_version": "1.0",
    }
    # A JSON body isn't part of the signature base string, only the OAuth parameters.
    params = "&".join(f"{quote(k)}={quote(v)}" for k, v in sorted(oauth.items()))
    base = "&".join([method, quote(url), quote(params)])
    signing_key = f"{quote(keys['api_secret'])}&{quote(keys['access_token_secret'])}"
    digest = hmac.new(signing_key.encode(), base.encode(), hashlib.sha1).digest()
    oauth["oauth_signature"] = base64.b64encode(digest).decode()
    return "OAuth " + ", ".join(f'{quote(k)}="{quote(v)}"' for k, v in sorted(oauth.items()))


def main() -> int:
    version = os.environ.get("VERSION", "").lstrip("v")
    if not version:
        print("VERSION is not set", file=sys.stderr)
        return 1
    text = compose(version)
    if os.environ.get("DRY_RUN"):
        print(text)
        return 0

    keys = {
        "api_key": os.environ.get("X_API_KEY", ""),
        "api_secret": os.environ.get("X_API_SECRET", ""),
        "access_token": os.environ.get("X_ACCESS_TOKEN", ""),
        "access_token_secret": os.environ.get("X_ACCESS_TOKEN_SECRET", ""),
    }
    if not all(keys.values()):
        print("X credentials are not set; skipping the post.")
        return 0

    request = urllib.request.Request(
        ENDPOINT,
        data=json.dumps({"text": text}).encode(),
        method="POST",
        headers={"Authorization": authorization("POST", ENDPOINT, keys), "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request) as response:
            post = json.load(response)["data"]
    except urllib.error.HTTPError as error:
        print(f"X API error {error.code}: {error.read().decode()}", file=sys.stderr)
        return 1
    print(f"Posted https://x.com/i/status/{post['id']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
