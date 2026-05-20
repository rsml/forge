#!/bin/bash
set -euo pipefail

# Bump the semver version stored in Resources/Info.plist.
# Usage: scripts/bump-version.sh {major|minor|patch}

BUMP="${1:-}"
case "$BUMP" in
  major|minor|patch) ;;
  *)
    echo "Usage: $0 {major|minor|patch}" >&2
    exit 1
    ;;
esac

PLIST="Resources/Info.plist"

CURRENT=$(plutil -extract CFBundleShortVersionString raw "$PLIST")
# Pad to X.Y.Z so partial versions like "0.1" work.
IFS='.' read -r MAJOR MINOR PATCH _ <<< "${CURRENT}.0.0"
MAJOR=${MAJOR:-0}
MINOR=${MINOR:-0}
PATCH=${PATCH:-0}

case "$BUMP" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
esac

NEW="${MAJOR}.${MINOR}.${PATCH}"
plutil -replace CFBundleShortVersionString -string "$NEW" "$PLIST"

# CFBundleVersion is a monotonic build number; bump it alongside.
BUILD=$(plutil -extract CFBundleVersion raw "$PLIST")
NEW_BUILD=$((BUILD + 1))
plutil -replace CFBundleVersion -string "$NEW_BUILD" "$PLIST"

echo "Version bumped: ${CURRENT} -> ${NEW} (build ${BUILD} -> ${NEW_BUILD})"

# Commit only Info.plist — leaves any other staged/unstaged changes alone.
git commit "$PLIST" -m "chore(release): bump version to ${NEW}"
