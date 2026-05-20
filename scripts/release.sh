#!/bin/bash
set -euo pipefail

# Build, sign, notarize, and publish a Forge release. Mirrors the
# tutor repo's flow (scripts/release.sh) but adapted for a Swift macOS
# app instead of an Electron app.
#
# Required env vars (loaded from .env if present):
#   APPLE_APP_SPECIFIC_PASSWORD    App-specific password from appleid.apple.com
#
# APPLE_ID, APPLE_TEAM_ID, and SIGNING_IDENTITY are hardcoded below —
# none are secret. The team ID is stamped on every signed binary, the
# Apple ID is just a login username, and the signing identity is a
# Keychain certificate name (the actual cert + private key live in the
# local Keychain, gated by macOS).

export APPLE_ID="admin@serendipityapps.com"
export APPLE_TEAM_ID="9CD626Q2L2"
export SIGNING_IDENTITY="Developer ID Application: Serendipity Apps LLC (TN) (9CD626Q2L2)"

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

: "${APPLE_APP_SPECIFIC_PASSWORD:?Set APPLE_APP_SPECIFIC_PASSWORD in .env or environment}"

PLIST="Resources/Info.plist"
ENTITLEMENTS="Resources/Forge.entitlements"
APP=".build/release/Forge.app"
RELEASE_DIR="release"

VERSION=$(plutil -extract CFBundleShortVersionString raw "$PLIST")
TAG="v${VERSION}"
APP_ZIP="${RELEASE_DIR}/Forge-${VERSION}-app.zip"   # intermediate, for .app notarization
DMG="${RELEASE_DIR}/Forge-${VERSION}.dmg"           # published artifact

if gh release view "$TAG" >/dev/null 2>&1; then
  echo "Error: GitHub release ${TAG} already exists. Bump the version (make bump-patch|minor|major) first." >&2
  exit 1
fi

echo "==> Building Forge ${VERSION}..."
swift build -c release
make bundle BUILD=.build/release

echo "==> Signing with Developer ID (hardened runtime + timestamp)..."
codesign --force --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$SIGNING_IDENTITY" \
  "$APP/Contents/MacOS/forged"
codesign --force --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$SIGNING_IDENTITY" \
  "$APP"

echo "==> Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP"

mkdir -p "$RELEASE_DIR"
rm -f "$APP_ZIP"
ditto -c -k --keepParent "$APP" "$APP_ZIP"

echo "==> Submitting .app for notarization (this may take a few minutes)..."
xcrun notarytool submit "$APP_ZIP" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --wait

echo "==> Stapling notarization ticket to .app..."
xcrun stapler staple "$APP"

echo "==> Verifying Gatekeeper acceptance of .app..."
spctl --assess --type execute --verbose=2 "$APP"

# Intermediate zip is no longer needed once .app is stapled.
rm -f "$APP_ZIP"

echo "==> Building DMG with Applications symlink..."
DMG_STAGE=$(mktemp -d)
trap 'rm -rf "$DMG_STAGE"' EXIT
ditto "$APP" "$DMG_STAGE/Forge.app"
ln -s /Applications "$DMG_STAGE/Applications"
rm -f "$DMG"
hdiutil create \
  -volname "Forge ${VERSION}" \
  -srcfolder "$DMG_STAGE" \
  -ov -format UDZO \
  "$DMG"
rm -rf "$DMG_STAGE"
trap - EXIT

echo "==> Signing DMG..."
codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG"

echo "==> Submitting DMG for notarization..."
xcrun notarytool submit "$DMG" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --wait

echo "==> Stapling notarization ticket to DMG..."
xcrun stapler staple "$DMG"

echo "==> Verifying Gatekeeper acceptance of DMG..."
spctl --assess --type install --verbose=2 "$DMG"

echo "==> Pushing HEAD so the release tag points to a reachable commit..."
git push

echo "==> Creating GitHub release ${TAG}..."
if [ -n "${RELEASE_NOTES_FILE:-}" ] && [ -f "${RELEASE_NOTES_FILE}" ]; then
  gh release create "$TAG" "$DMG" \
    --title "Forge ${VERSION}" \
    --notes-file "${RELEASE_NOTES_FILE}"
else
  gh release create "$TAG" "$DMG" \
    --title "Forge ${VERSION}" \
    --generate-notes
fi

echo
echo "==> Done. Release published at:"
gh release view "$TAG" --json url -q .url
