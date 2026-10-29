#!/bin/zsh
# Checks a .p12 the same way the GitHub Action does: base64 round trip, import into a throwaway
# keychain with its password, and look for the Developer ID identity. Optionally uploads it.
#   scripts/check-cert.sh ~/Downloads/Certificates.p12           # check only
#   scripts/check-cert.sh ~/Downloads/Certificates.p12 --upload  # check, then set the two secrets
set -euo pipefail
P12="${1:?Usage: scripts/check-cert.sh path/to/certificate.p12 [--upload]}"
REPO=hyppe-cc/tunnels
[[ -s "$P12" ]] || { echo "✗ $P12 doesn't exist or is empty" >&2; exit 1; }

read -rs "PASSWORD?Password for $(basename "$P12"): "; echo

TMP=$(mktemp -d)
KEYCHAIN="$TMP/check.keychain"
trap 'security delete-keychain "$KEYCHAIN" 2>/dev/null || true; rm -rf "$TMP"' EXIT

# Same steps as the workflow: encode, decode, import.
base64 -i "$P12" > "$TMP/encoded"
echo "base64 length: $(wc -c < "$TMP/encoded" | tr -d ' ') characters"
base64 --decode -i "$TMP/encoded" > "$TMP/decoded.p12"
security create-keychain -p check "$KEYCHAIN"
if ! security import "$TMP/decoded.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign >/dev/null; then
  echo "✗ Import failed: wrong password, or not a .p12 export" >&2; exit 1
fi

IDENTITIES=$(security find-identity -v -p codesigning "$KEYCHAIN")
echo "$IDENTITIES" | sed -E 's/[0-9A-F]{40}/<hash>/'
if ! grep -q "Developer ID Application" <<< "$IDENTITIES"; then
  echo "✗ No 'Developer ID Application' identity with its private key in this .p12." >&2
  echo "  Export it from Keychain Access → login → My Certificates (expand it so the key is included)." >&2
  exit 1
fi
echo "✓ The certificate and password work."

if [[ "${2:-}" == "--upload" ]]; then
  gh secret set APPLE_CERTIFICATE -R "$REPO" < "$TMP/encoded"
  gh secret set APPLE_CERTIFICATE_PASSWORD -R "$REPO" --body "$PASSWORD"
  echo "✓ Uploaded APPLE_CERTIFICATE and APPLE_CERTIFICATE_PASSWORD to $REPO"
fi
