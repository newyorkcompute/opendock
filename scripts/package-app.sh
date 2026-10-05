#!/usr/bin/env bash
# Zips build/OpenDock.app for distribution and writes its SHA-256 checksum.
#
#   scripts/package-app.sh    # -> build/dist/OpenDock-<version>.zip and .zip.sha256
#
# Run after scripts/build-app.sh (and scripts/notarize.sh, so the zip holds the
# stapled app). The version in the file name comes from the bundle's
# CFBundleShortVersionString unless OPENDOCK_RELEASE_VERSION overrides it,
# e.g. with a pre-release suffix like 0.2.0-beta.1.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="OpenDock"
APP="$ROOT/build/$APP_NAME.app"
DIST="$ROOT/build/dist"

[[ -d "$APP" ]] || { echo "no app bundle at $APP (run scripts/build-app.sh first)" >&2; exit 1; }
codesign --verify --deep --strict "$APP"

VERSION="${OPENDOCK_RELEASE_VERSION:-$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")}"
ZIP="$APP_NAME-$VERSION.zip"

rm -rf "$DIST"
mkdir -p "$DIST"

# ditto (not zip) keeps the extended attributes, symlinks, and signature intact.
ditto -c -k --keepParent "$APP" "$DIST/$ZIP"
(cd "$DIST" && shasum -a 256 "$ZIP" > "$ZIP.sha256")

echo "✓ $DIST/$ZIP"
cat "$DIST/$ZIP.sha256"
