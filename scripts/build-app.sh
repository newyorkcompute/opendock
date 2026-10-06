#!/usr/bin/env bash
# Builds OpenDock with SwiftPM and assembles a runnable, signed .app bundle.
#
#   scripts/build-app.sh            # release build, universal (arm64 + x86_64) -> build/OpenDock.app
#   scripts/build-app.sh --native   # release build for this Mac's architecture only (faster)
#   scripts/build-app.sh --debug    # debug build for this Mac's architecture (fastest, for iteration)
#
# Environment:
#   OPENDOCK_VERSION        CFBundleShortVersionString, e.g. 0.1.0 (default 0.1.0)
#   OPENDOCK_BUILD          CFBundleVersion (default: commit count, so it only ever goes up)
#   OPENDOCK_SIGN_IDENTITY  codesign identity, e.g. "Developer ID Application: … (TEAMID)"
#                           (default "-", ad hoc)
#
# No Xcode project needed: Swift Package Manager produces the binary and this
# script wraps it in the bundle structure macOS expects (Info.plist, resources,
# signature). TCC permissions (Calendar etc.) are tied to the bundle identifier
# plus signature, so we always sign, even if only ad hoc.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="release"
UNIVERSAL=1
for arg in "$@"; do
    case "$arg" in
        --debug)  CONFIG="debug"; UNIVERSAL=0 ;;
        --native) UNIVERSAL=0 ;;
        -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $arg (see --help)" >&2; exit 2 ;;
    esac
done

APP_NAME="OpenDock"
VERSION="${OPENDOCK_VERSION:-0.1.0}"
BUILD_NUMBER="${OPENDOCK_BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
SIGN_IDENTITY="${OPENDOCK_SIGN_IDENTITY:--}"   # "-" = ad hoc

# Sparkle and Launch Services compare these numerically, so keep them to dot-separated integers.
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] \
    || { echo "OPENDOCK_VERSION must look like 1.2.3, got '$VERSION'" >&2; exit 1; }
[[ "$BUILD_NUMBER" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] \
    || { echo "OPENDOCK_BUILD must look like 123 or 1.2.3, got '$BUILD_NUMBER'" >&2; exit 1; }

ARCHS=()
if [[ "$UNIVERSAL" == 1 ]]; then ARCHS=(arm64 x86_64); fi
BUILD_FLAGS=(-c "$CONFIG")
for arch in ${ARCHS[@]+"${ARCHS[@]}"}; do BUILD_FLAGS+=(--arch "$arch"); done

OUT_DIR="$ROOT/build"
APP_DIR="$OUT_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"

echo "▸ swift build ($CONFIG, ${ARCHS[*]:-native})"
# Drop progress lines ("[12/80] Compiling…", "42%: …"). sed (unlike grep) never
# fails, so pipefail still reports a failed build.
swift build "${BUILD_FLAGS[@]}" --product "$APP_NAME" 2>&1 | sed -E '/^(\[[0-9]+\/[0-9]+\]|[0-9]+%: )/d'
BIN_DIR="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"
BINARY="$BIN_DIR/$APP_NAME"
[[ -x "$BINARY" ]] || { echo "build failed: $BINARY not found" >&2; exit 1; }
if [[ ${#ARCHS[@]} -gt 0 ]]; then
    "$ROOT/scripts/verify-archs.sh" "$BINARY" "${ARCHS[@]}" > /dev/null
fi

echo "▸ assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BINARY" "$CONTENTS/MacOS/$APP_NAME"

cp "$ROOT/App/Resources/Info.plist" "$CONTENTS/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$CONTENTS/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$CONTENTS/Info.plist"
plutil -lint -s "$CONTENTS/Info.plist"
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
SIGN_FLAGS=(--force --deep --sign "$SIGN_IDENTITY"
            --entitlements "$ROOT/App/Resources/OpenDock.entitlements"
            --options runtime)
# Notarization requires a secure timestamp; ad-hoc signatures can't have one.
if [[ "$SIGN_IDENTITY" == "-" ]]; then SIGN_FLAGS+=(--timestamp=none); else SIGN_FLAGS+=(--timestamp); fi
codesign "${SIGN_FLAGS[@]}" "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "✓ $APP_DIR (v$VERSION build $BUILD_NUMBER, $(lipo -archs "$CONTENTS/MacOS/$APP_NAME"))"
