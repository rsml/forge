#!/bin/bash
set -euo pipefail

# Build, sign, notarize, and publish a Forge release. Mirrors the
# tutor repo's flow (scripts/release.sh) but adapted for a Swift macOS
# app instead of an Electron app.
#
# Required env vars (loaded from .env if present):
#   APPLE_APP_SPECIFIC_PASSWORD    App-specific password from appleid.apple.com
#   SIGNING_IDENTITY               e.g. "Developer ID Application: Name (TEAMID)"
#
# APPLE_ID and APPLE_TEAM_ID are hardcoded below — neither is secret
# (the team ID is stamped on every signed binary, and the Apple ID is
# just a login username).

export APPLE_ID="admin@serendipityapps.com"
export APPLE_TEAM_ID="9CD626Q2L2"

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

: "${APPLE_APP_SPECIFIC_PASSWORD:?Set APPLE_APP_SPECIFIC_PASSWORD in .env or environment}"
: "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY in .env or environment}"

PLIST="Resources/Info.plist"
ENTITLEMENTS="Resources/Forge.entitlements"
APP=".build/release/Forge.app"
RELEASE_DIR="release"

VERSION=$(plutil -extract CFBundleShortVersionString raw "$PLIST")
TAG="v${VERSION}"
ZIP="${RELEASE_DIR}/Forge-${VERSION}.zip"

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
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Submitting for notarization (this may take a few minutes)..."
xcrun notarytool submit "$ZIP" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --wait

echo "==> Stapling notarization ticket..."
xcrun stapler staple "$APP"

# Re-zip so the published artifact contains the stapled ticket.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Verifying Gatekeeper acceptance..."
spctl --assess --type execute --verbose=2 "$APP"

echo "==> Pushing HEAD so the release tag points to a reachable commit..."
git push

echo "==> Creating GitHub release ${TAG}..."
if [ -n "${RELEASE_NOTES_FILE:-}" ] && [ -f "${RELEASE_NOTES_FILE}" ]; then
  gh release create "$TAG" "$ZIP" \
    --title "Forge ${VERSION}" \
    --notes-file "${RELEASE_NOTES_FILE}"
else
  gh release create "$TAG" "$ZIP" \
    --title "Forge ${VERSION}" \
    --generate-notes
fi

echo
echo "==> Done. Release published at:"
gh release view "$TAG" --json url -q .url
