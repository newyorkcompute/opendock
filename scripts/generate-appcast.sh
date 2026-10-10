#!/usr/bin/env bash
# Signs build/dist/OpenDock-*.zip with Sparkle's EdDSA key and writes build/dist/appcast.xml.
#
#   SPARKLE_PRIVATE_KEY       contents of the file from `generate_keys -x` (one base64 line).
#                             When unset, this script warns and exits 0 so a release can
#                             still publish without an appcast. See RELEASING.md.
#   OPENDOCK_RELEASE_VERSION  version in the zip name, including a pre-release suffix.
#   RELEASE_TAG               git tag (v1.2.3). Defaults to v$OPENDOCK_RELEASE_VERSION.
#
# The tool version must match Package.swift's Sparkle dependency. Enclosure URLs point at
# the GitHub release asset for RELEASE_TAG. GitHub's /releases/latest/download/appcast.xml
# (SUFeedURL) then serves whichever release is the latest non-prerelease.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Keep in lockstep with Package.swift.
SPARKLE_VERSION="2.10.0"

if [[ -f "$ROOT/.env.local" ]]; then
    ENV_SNAPSHOT="$(export -p | grep -E '^declare -x SPARKLE_PRIVATE_KEY=' || true)"
    set -a
    # shellcheck disable=SC1091
    source "$ROOT/.env.local"
    set +a
    eval "$ENV_SNAPSHOT"
fi

grep -q "exact: \"${SPARKLE_VERSION}\"" "$ROOT/Package.swift" \
    || { echo "Sparkle ${SPARKLE_VERSION} in this script does not match Package.swift" >&2; exit 1; }

write_signed() {
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        echo "signed=$1" >> "$GITHUB_OUTPUT"
    fi
}

PRIVATE="$(printf '%s' "${SPARKLE_PRIVATE_KEY:-}" | tr -d '[:space:]')"
if [[ -z "$PRIVATE" ]]; then
    echo "warning: SPARKLE_PRIVATE_KEY is not set. Skipping Sparkle appcast signing." >&2
    echo "warning: this release will publish without appcast.xml, so Sparkle will not offer it as an update." >&2
    echo "warning: generate the key once and add the secret when it exists (see RELEASING.md)." >&2
    echo "::warning title=Sparkle::SPARKLE_PRIVATE_KEY is not set; skipping appcast signing. The release still publishes, without appcast.xml."
    write_signed false
    exit 0
fi

DIST="$ROOT/build/dist"
[[ -d "$DIST" ]] || { echo "no $DIST (run scripts/package-app.sh first)" >&2; exit 1; }

if [[ -n "${RELEASE_TAG:-}" ]]; then
    TAG="$RELEASE_TAG"
else
    TAG="v${OPENDOCK_RELEASE_VERSION:?set OPENDOCK_RELEASE_VERSION or RELEASE_TAG}"
fi
REPO="${GITHUB_REPOSITORY:-newyorkcompute/opendock}"
PREFIX="https://github.com/${REPO}/releases/download/${TAG}/"
LINK="https://github.com/${REPO}"
NOTES="https://github.com/${REPO}/releases/tag/${TAG}"

KEY_FILE="$(mktemp)"
chmod 600 "$KEY_FILE"
printf '%s' "$PRIVATE" > "$KEY_FILE"
TMP=""
STAGE=""
cleanup() {
    rm -f "$KEY_FILE"
    if [[ -n "$TMP" ]]; then rm -rf "$TMP"; fi
    if [[ -n "$STAGE" ]]; then rm -rf "$STAGE"; fi
}
trap cleanup EXIT

TOOL=""
if [[ -d "$ROOT/.build/artifacts" ]]; then
    TOOL="$(find "$ROOT/.build/artifacts" -type f -path '*/bin/generate_appcast' -print -quit || true)"
fi
if [[ -z "$TOOL" || ! -x "$TOOL" ]]; then
    TMP="$(mktemp -d)"
    echo "▸ downloading Sparkle ${SPARKLE_VERSION} generate_appcast"
    curl -fsSL -o "$TMP/sparkle.zip" \
        "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-for-Swift-Package-Manager.zip"
    unzip -q "$TMP/sparkle.zip" -d "$TMP"
    TOOL="$TMP/bin/generate_appcast"
fi
[[ -x "$TOOL" ]] || { echo "generate_appcast is not executable ($TOOL)" >&2; exit 1; }

ZIP="$(find "$DIST" -maxdepth 1 -name 'OpenDock-*.zip' -print -quit)"
[[ -n "$ZIP" ]] || { echo "release zip is missing in $DIST" >&2; exit 1; }
# Sign a copy. generate_appcast can move archives it no longer needs into old_updates/,
# and it should not see the checksum file next to the zip.
STAGE="$(mktemp -d)"
cp "$ZIP" "$STAGE/"

echo "▸ generate_appcast ($TAG)"
"$TOOL" \
    --ed-key-file "$KEY_FILE" \
    --download-url-prefix "$PREFIX" \
    --full-release-notes-url "$NOTES" \
    --link "$LINK" \
    -o "$DIST/appcast.xml" \
    "$STAGE"

[[ -f "$DIST/appcast.xml" ]] || { echo "generate_appcast did not write $DIST/appcast.xml" >&2; exit 1; }
(cd "$DIST" && shasum -a 256 -c "$(basename "$ZIP").sha256")
grep -q 'sparkle:edSignature' "$DIST/appcast.xml" \
    || { echo "appcast.xml has no sparkle:edSignature" >&2; exit 1; }
grep -F -q "$PREFIX" "$DIST/appcast.xml" \
    || { echo "appcast.xml enclosure URL does not start with $PREFIX" >&2; exit 1; }
echo "✓ $DIST/appcast.xml"
write_signed true
