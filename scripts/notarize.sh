#!/usr/bin/env bash
# Notarizes a Developer ID-signed app bundle with Apple and staples the ticket to it.
#
#   scripts/notarize.sh [build/OpenDock.app]
#
# Build the app first with OPENDOCK_SIGN_IDENTITY set to a "Developer ID Application"
# identity; ad-hoc signed apps are rejected. Credentials, first complete set wins:
#
#   NOTARY_KEYCHAIN_PROFILE                         profile saved with `xcrun notarytool store-credentials`
#   NOTARY_API_KEY_PATH, NOTARY_API_KEY_ID,         App Store Connect API key (.p8 file)
#     NOTARY_API_ISSUER_ID
#   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD     Apple ID with an app-specific password

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT/build/OpenDock.app}"
[[ -d "$APP" ]] || { echo "no app bundle at $APP (run scripts/build-app.sh first)" >&2; exit 1; }

if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    AUTH=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
elif [[ -n "${NOTARY_API_KEY_PATH:-}" && -n "${NOTARY_API_KEY_ID:-}" && -n "${NOTARY_API_ISSUER_ID:-}" ]]; then
    AUTH=(--key "$NOTARY_API_KEY_PATH" --key-id "$NOTARY_API_KEY_ID" --issuer "$NOTARY_API_ISSUER_ID")
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
    AUTH=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD")
else
    echo "no notarization credentials set (see the header of $0)" >&2
    exit 1
fi

if codesign -dvv "$APP" 2>&1 | grep -q '^Signature=adhoc'; then
    echo "$APP is ad-hoc signed; rebuild with OPENDOCK_SIGN_IDENTITY set to a Developer ID identity" >&2
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# notarytool takes a zip, but the ticket gets stapled to the app itself.
ditto -c -k --keepParent "$APP" "$WORK/upload.zip"

echo "▸ notarytool submit (waits for Apple, usually a few minutes)"
xcrun notarytool submit "$WORK/upload.zip" "${AUTH[@]}" \
    --wait --timeout 30m --output-format json > "$WORK/result.json" || true
cat "$WORK/result.json"; echo
STATUS="$(plutil -extract status raw -o - "$WORK/result.json" 2>/dev/null || echo unknown)"
SUBMISSION="$(plutil -extract id raw -o - "$WORK/result.json" 2>/dev/null || true)"

if [[ "$STATUS" != "Accepted" ]]; then
    echo "notarization failed: status '$STATUS'" >&2
    if [[ -n "$SUBMISSION" ]]; then
        xcrun notarytool log "$SUBMISSION" "${AUTH[@]}" >&2 || true
    fi
    exit 1
fi

echo "▸ stapler staple"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

echo "✓ notarized $APP"
