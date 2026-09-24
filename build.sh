#!/bin/bash
# Builds PassboltBar.app into ./dist/
#   ./build.sh           signed with Kumpan's Developer ID if installed, else ad-hoc
#   ./build.sh release   also notarizes, staples and zips for distribution
#                        (needs the "PassboltBar" notarytool keychain profile; CI sets NOTARY_KEYCHAIN)
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-$(cat VERSION)}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGN_ID="Developer ID Application: Kumpan Grafisk Form AB (NH4M8452G6)"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/PassboltBar"
APP=".build/PassboltBar.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/PassboltBar"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>se.kumpan.passboltbar</string>
  <key>CFBundleName</key><string>PassboltBar</string>
  <key>CFBundleExecutable</key><string>PassboltBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSCameraUsageDescription</key><string>Scan your authenticator app's QR code to set up two-factor sign-in.</string>
</dict>
</plist>
PLIST

if security find-identity -v -p codesigning | grep -q "$SIGN_ID"; then
  # Hardened runtime is required for notarization; it blocks the camera unless entitled.
  cat > .build/entitlements.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.device.camera</key><true/>
</dict>
</plist>
PLIST
  codesign --force --options runtime --timestamp --entitlements .build/entitlements.plist -s "$SIGN_ID" "$APP"
else
  [[ "${1:-}" == "release" ]] && { echo "Developer ID certificate not found; can't make a release." >&2; exit 1; }
  echo "Developer ID certificate not found – signing ad-hoc (works on this Mac only)."
  codesign --force --deep -s - "$APP"
fi

mkdir -p dist
rm -rf dist/PassboltBar.app
cp -R "$APP" dist/

if [[ "${1:-}" == "release" ]]; then
  ZIP="dist/PassboltBar-$VERSION.zip"
  ditto -c -k --keepParent dist/PassboltBar.app "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile PassboltBar ${NOTARY_KEYCHAIN:+--keychain "$NOTARY_KEYCHAIN"} --wait
  xcrun stapler staple dist/PassboltBar.app
  rm "$ZIP"
  ditto -c -k --keepParent dist/PassboltBar.app "$ZIP" # re-zip with the stapled ticket
  spctl --assess --type execute -v dist/PassboltBar.app
  echo "Release ready: $ZIP"
else
  echo "Built dist/PassboltBar.app"
fi
