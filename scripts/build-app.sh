#!/usr/bin/env bash
# Builds OpenDock with SwiftPM and assembles a runnable, ad-hoc-signed .app bundle.
#
#   scripts/build-app.sh            # release build -> build/OpenDock.app
#   scripts/build-app.sh --debug    # debug build (faster, for iteration)
#
# No Xcode project needed: Swift Package Manager produces the binary and this
# script wraps it in the bundle structure macOS expects (Info.plist, resources,
# signature). TCC permissions (Calendar etc.) are tied to the bundle identifier
# plus signature, so we always sign, even if only ad hoc.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="release"
if [[ "${1:-}" == "--debug" ]]; then CONFIG="debug"; fi

APP_NAME="OpenDock"
VERSION="${OPENDOCK_VERSION:-0.1.0}"
BUILD_NUMBER="${OPENDOCK_BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
SIGN_IDENTITY="${OPENDOCK_SIGN_IDENTITY:--}"   # "-" = ad hoc

OUT_DIR="$ROOT/build"
APP_DIR="$OUT_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"

echo "▸ swift build ($CONFIG)"
swift build -c "$CONFIG" --product "$APP_NAME" 2>&1 | grep -v '^\[' || true
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BINARY="$BIN_DIR/$APP_NAME"
[[ -x "$BINARY" ]] || { echo "build failed: $BINARY not found"; exit 1; }

echo "▸ assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BINARY" "$CONTENTS/MacOS/$APP_NAME"

# Info.plist with version substitution.
sed -e "s/\$(VERSION)/$VERSION/g" -e "s/\$(BUILD)/$BUILD_NUMBER/g" \
    "$ROOT/App/Resources/Info.plist" > "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

# App icon, if one has been generated.
if [[ -f "$ROOT/App/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/App/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
fi

# SwiftPM resource bundles (if any target declares resources).
shopt -s nullglob
for bundle in "$BIN_DIR"/*.bundle; do
    cp -R "$bundle" "$CONTENTS/Resources/"
done
shopt -u nullglob

echo "▸ codesign ($SIGN_IDENTITY)"
codesign --force --deep --sign "$SIGN_IDENTITY" \
    --entitlements "$ROOT/App/Resources/OpenDock.entitlements" \
    --options runtime \
    "$APP_DIR" 2>&1 | grep -v 'replacing existing signature' || true

echo "✓ $APP_DIR (v$VERSION build $BUILD_NUMBER)"
