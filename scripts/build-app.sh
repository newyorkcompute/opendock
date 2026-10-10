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
#   OPENDOCK_SIGN_IDENTITY  codesign identity: "Developer ID Application: … (TEAMID)" for
#                           releases, or a self-signed "OpenDock Dev" certificate for
#                           local builds (see CONTRIBUTING.md). Default "-", ad hoc.
#   SPARKLE_PUBLIC_ED_KEY   EdDSA public key stamped into SUPublicEDKey. When unset, the
#                           key is omitted and the build cannot verify updates (see RELEASING.md).
#
# These can also live in a git-ignored .env.local at the repo root (KEY=value lines);
# variables already set in the environment take precedence over the file.
#
# No Xcode project needed: Swift Package Manager produces the binary and this
# script wraps it in the bundle structure macOS expects (Info.plist, resources,
# signature). TCC permissions (Calendar etc.) are tied to the bundle identifier
# plus signature, so we always sign, even if only ad hoc. An ad-hoc signature
# changes with every build, though, so macOS re-asks for permissions after each
# reinstall; a real certificate (even self-signed) keeps them.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -f "$ROOT/.env.local" ]]; then
    # Snapshot exported OPENDOCK_* variables, source the file, then put the
    # snapshot back so the environment wins over the file.
    ENV_SNAPSHOT="$(export -p | grep -E '^declare -x (OPENDOCK_|SPARKLE_PUBLIC_ED_KEY=)' || true)"
    set -a
    # shellcheck disable=SC1091
    source "$ROOT/.env.local"
    set +a
    eval "$ENV_SNAPSHOT"
fi

CONFIG="release"
UNIVERSAL=1
for arg in "$@"; do
    case "$arg" in
        --debug)  CONFIG="debug"; UNIVERSAL=0 ;;
        --native) UNIVERSAL=0 ;;
        -h|--help) sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

# The Now Playing helper: a dylib the app runs inside /usr/bin/perl (see Sources/NowPlayingHelper).
# Built separately because the app must not link it.
HELPER_PRODUCT="OpenDockNowPlayingHelper"
HELPER_LIB="lib$HELPER_PRODUCT.dylib"
echo "▸ swift build ($HELPER_PRODUCT)"
swift build "${BUILD_FLAGS[@]}" --product "$HELPER_PRODUCT" 2>&1 | sed -E '/^(\[[0-9]+\/[0-9]+\]|[0-9]+%: )/d'
HELPER_BINARY="$BIN_DIR/$HELPER_LIB"
[[ -f "$HELPER_BINARY" ]] || { echo "build failed: $HELPER_BINARY not found" >&2; exit 1; }
if [[ ${#ARCHS[@]} -gt 0 ]]; then
    "$ROOT/scripts/verify-archs.sh" "$HELPER_BINARY" "${ARCHS[@]}" > /dev/null
fi

# Copies Sparkle.framework from SwiftPM's downloaded xcframework into Contents/Frameworks.
# The framework already contains Autoupdate, Updater.app, and the XPC services.
embed_sparkle() {
    local bin_dir="$1"
    local frameworks_dir="$2"
    local scratch="$bin_dir"
    local framework=""
    for _ in 1 2 3 4 5 6; do
        if [[ -d "$scratch/artifacts" ]]; then
            framework="$(find "$scratch/artifacts" -type d -path '*/macos-arm64_x86_64/Sparkle.framework' -print -quit)"
            break
        fi
        scratch="$(dirname "$scratch")"
        [[ "$scratch" == "/" ]] && break
    done
    [[ -n "$framework" && -d "$framework/Versions/B" ]] \
        || { echo "Sparkle.framework not found under $bin_dir (did swift build fetch Sparkle 2.10.0?)" >&2; exit 1; }
    echo "▸ embedding Sparkle.framework"
    ditto "$framework" "$frameworks_dir/Sparkle.framework"
}

# SUPublicEDKey comes from the environment, never from the repo. An empty value is removed
# so the plist doesn't keep the unsubstituted $(SPARKLE_PUBLIC_ED_KEY) placeholder.
stamp_sparkle_public_key() {
    local plist="$1"
    local public_key="${SPARKLE_PUBLIC_ED_KEY:-}"
    public_key="${public_key//[[:space:]]/}"
    if [[ -z "$public_key" ]]; then
        plutil -remove SUPublicEDKey "$plist"
        echo "warning: SPARKLE_PUBLIC_ED_KEY is unset; this build cannot verify Sparkle updates (see RELEASING.md)" >&2
        return
    fi
    local pattern='^[A-Za-z0-9+/]+=*$'
    # Bash 3.2 (macOS /bin/bash) mishandles an unquoted `+` on the right of =~.
    [[ "$public_key" =~ $pattern ]] \
        || { echo "SPARKLE_PUBLIC_ED_KEY is not base64" >&2; exit 1; }
    plutil -replace SUPublicEDKey -string "$public_key" "$plist"
}

# The SwiftPM binary loads Sparkle via @rpath. Point that at Contents/Frameworks and drop
# any absolute build-directory rpath so a shipped app doesn't look back into .build.
add_framework_rpath() {
    local bin="$1"
    local rpath="@executable_path/../Frameworks"
    local existing path
    existing="$(otool -l "$bin" | awk '/cmd LC_RPATH/{found=1; next} found && /path /{print $2; found=0}')"
    if ! grep -qx "$rpath" <<< "$existing"; then
        install_name_tool -add_rpath "$rpath" "$bin"
    fi
    while IFS= read -r path; do
        [[ -z "$path" ]] && continue
        case "$path" in
            *"/artifacts/"*|*"/.build/"*)
                install_name_tool -delete_rpath "$path" "$bin"
                ;;
        esac
    done <<< "$existing"
    if ! otool -L "$bin" | grep -q '@rpath/Sparkle.framework/'; then
        echo "OpenDock is not linked with @rpath/Sparkle.framework:" >&2
        otool -L "$bin" >&2
        exit 1
    fi
}

# Signs Sparkle's nested code with the same identity as the app, without the app's entitlements.
sign_sparkle() {
    local root="$CONTENTS/Frameworks/Sparkle.framework"
    local version_b="$root/Versions/B"
    codesign "$@" "$version_b/XPCServices/Downloader.xpc"
    codesign "$@" "$version_b/XPCServices/Installer.xpc"
    codesign "$@" "$version_b/Autoupdate"
    codesign "$@" "$version_b/Updater.app"
    codesign "$@" "$root"
}

verify_sparkle_bundle() {
    local app="$1"
    local plist="$app/Contents/Info.plist"
    local root="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
    [[ -x "$root/Autoupdate" ]] || { echo "Sparkle Autoupdate is missing" >&2; exit 1; }
    [[ -d "$root/Updater.app" ]] || { echo "Sparkle Updater.app is missing" >&2; exit 1; }
    [[ -d "$root/XPCServices/Installer.xpc" ]] || { echo "Sparkle Installer.xpc is missing" >&2; exit 1; }
    [[ -d "$root/XPCServices/Downloader.xpc" ]] || { echo "Sparkle Downloader.xpc is missing" >&2; exit 1; }
    local feed
    feed="$(plutil -extract SUFeedURL raw -o - "$plist")"
    [[ "$feed" == "https://github.com/newyorkcompute/opendock/releases/latest/download/appcast.xml" ]] \
        || { echo "SUFeedURL is '$feed'" >&2; exit 1; }
    if plutil -extract SUPublicEDKey raw -o - "$plist" >/dev/null 2>&1; then
        local key
        key="$(plutil -extract SUPublicEDKey raw -o - "$plist")"
        [[ -n "$key" && "$key" != '$(SPARKLE_PUBLIC_ED_KEY)' ]] \
            || { echo "SUPublicEDKey is empty or unsubstituted" >&2; exit 1; }
    fi
    local sandbox_key
    for sandbox_key in SUEnableInstallerLauncherService SUEnableDownloaderService; do
        if plutil -extract "$sandbox_key" raw -o - "$plist" >/dev/null 2>&1; then
            echo "$sandbox_key must not be set; OpenDock is not sandboxed" >&2
            exit 1
        fi
    done
}

echo "▸ assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BINARY" "$CONTENTS/MacOS/$APP_NAME"

mkdir -p "$CONTENTS/Frameworks"
cp "$HELPER_BINARY" "$CONTENTS/Frameworks/$HELPER_LIB"
embed_sparkle "$BIN_DIR" "$CONTENTS/Frameworks"

cp "$ROOT/App/Resources/Info.plist" "$CONTENTS/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$CONTENTS/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$CONTENTS/Info.plist"
stamp_sparkle_public_key "$CONTENTS/Info.plist"
plutil -lint -s "$CONTENTS/Info.plist"
add_framework_rpath "$CONTENTS/MacOS/$APP_NAME"
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
IDENTITY_NAME="-"
if [[ "$SIGN_IDENTITY" != "-" ]]; then
    # `security find-identity` prints one `N) <SHA-1> "<name>"` line per identity
    # usable for code signing; OPENDOCK_SIGN_IDENTITY may be either field.
    IDENTITY_LINE="$(security find-identity -v -p codesigning \
        | grep -F -e " $SIGN_IDENTITY \"" -e "\"$SIGN_IDENTITY\"" | head -n 1 || true)"
    if [[ -z "$IDENTITY_LINE" ]]; then
        echo "no valid code-signing identity '$SIGN_IDENTITY' in the keychain search list" >&2
        echo "(security find-identity -v -p codesigning lists the usable ones; see CONTRIBUTING.md)" >&2
        exit 1
    fi
    IDENTITY_NAME="$(sed -E 's/^[^"]*"([^"]*)".*$/\1/' <<< "$IDENTITY_LINE")"
fi
# The hardened runtime works with any signature, so it's always on: local builds
# then behave like notarized releases.
NESTED_FLAGS=(--force --sign "$SIGN_IDENTITY" --options runtime)
APP_FLAGS=(--force --sign "$SIGN_IDENTITY"
           --entitlements "$ROOT/App/Resources/OpenDock.entitlements"
           --options runtime)
# Notarization requires a secure timestamp from Apple's server. Ad-hoc signatures
# can't carry one, and a local self-signed identity doesn't need one (nor the
# network access it takes), so only Developer ID signatures get it.
if [[ "$IDENTITY_NAME" == "Developer ID"* ]]; then
    NESTED_FLAGS+=(--timestamp)
    APP_FLAGS+=(--timestamp)
else
    NESTED_FLAGS+=(--timestamp=none)
    APP_FLAGS+=(--timestamp=none)
fi
# Inside-out. `--deep` on the app would re-sign Sparkle's XPC services and
# Autoupdate with the app's entitlements. Sign each nested item, then the app.
codesign "${NESTED_FLAGS[@]}" "$CONTENTS/Frameworks/$HELPER_LIB"
sign_sparkle "${NESTED_FLAGS[@]}"
shopt -s nullglob
for bundle in "$CONTENTS/Resources/"*.bundle; do
    codesign "${NESTED_FLAGS[@]}" "$bundle"
done
shopt -u nullglob
codesign "${APP_FLAGS[@]}" "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
verify_sparkle_bundle "$APP_DIR"

echo "✓ $APP_DIR (v$VERSION build $BUILD_NUMBER, $(lipo -archs "$CONTENTS/MacOS/$APP_NAME"))"

