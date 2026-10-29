#!/bin/zsh
# Builds Tunnels.app (with the `tunnel` CLI inside) into ./build
#   scripts/build.sh            → build/Tunnels.app and build/Tunnels.zip
#   scripts/build.sh --install  → also copies the app to ~/Applications and links `tunnel` into ~/bin
set -euo pipefail
cd "${0:A:h}/.."

# Version: the VERSION variable, else the VERSION file.
VERSION="${VERSION:-$(cat VERSION 2>/dev/null || true)}"
VERSION="${VERSION:-0.0.0}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

# Universal binaries (Apple Silicon + Intel)
swift build -c release --arch arm64 --arch x86_64
bin=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)

app=build/Tunnels.app
rm -rf "$app" build/Tunnels.zip
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/CloudBar" "$app/Contents/MacOS/Tunnels"
cp "$bin/tunnel" "$app/Contents/MacOS/tunnel"
[[ -f Resources/AppIcon.icns ]] || swift scripts/make-icon.swift Resources
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Tunnels</string>
  <key>CFBundleDisplayName</key><string>Tunnels</string>
  <key>CFBundleIdentifier</key><string>cc.hyppe.tunnels</string>
  <key>CFBundleExecutable</key><string>Tunnels</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Signing: Developer ID with hardened runtime if SIGN_IDENTITY is set (the Action sets it),
# otherwise ad-hoc for local builds. The CLI is signed first since it's nested in the bundle.
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$app/Contents/MacOS/tunnel"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$app"
else
  codesign --force --sign - "$app/Contents/MacOS/tunnel"
  codesign --force --sign - "$app"
fi

# Notarization: only when the Apple ID credentials are set (on release tags).
if [[ -n "${APPLE_ID:-}" && -n "${APPLE_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
  ditto -c -k --keepParent "$app" build/Tunnels.zip
  xcrun notarytool submit build/Tunnels.zip --apple-id "$APPLE_ID" --password "$APPLE_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" --wait
  xcrun stapler staple "$app"
  rm build/Tunnels.zip
fi

# Zip for the GitHub release / Homebrew
ditto -c -k --keepParent "$app" build/Tunnels.zip
echo "Built $app ($VERSION) and build/Tunnels.zip"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Tunnels 2>/dev/null || true
  mkdir -p ~/Applications ~/bin
  rm -rf ~/Applications/Tunnels.app
  cp -R "$app" ~/Applications/
  # ~/bin comes first in PATH; an older `tunnel` script there is kept as tunnel.old.
  if [[ -f ~/bin/tunnel && ! -L ~/bin/tunnel ]]; then mv ~/bin/tunnel ~/bin/tunnel.old; fi
  ln -sf ~/Applications/Tunnels.app/Contents/MacOS/tunnel ~/bin/tunnel
  echo "Installed ~/Applications/Tunnels.app and ~/bin/tunnel"
fi
