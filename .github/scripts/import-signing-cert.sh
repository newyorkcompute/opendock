#!/usr/bin/env bash
# Imports a Developer ID Application certificate into a temporary keychain on a
# GitHub-hosted macOS runner so codesign can use it.
#
# Inputs (environment): DEVELOPER_ID_CERT_P12 (base64 of a .p12 with the certificate
# and its private key) and DEVELOPER_ID_CERT_PASSWORD.
# Writes `keychain` (delete it when done) and `identity` (SHA-1 for codesign) to $GITHUB_OUTPUT.

set -euo pipefail

: "${DEVELOPER_ID_CERT_P12:?}" "${DEVELOPER_ID_CERT_PASSWORD:?}"
TMP="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
KEYCHAIN="$TMP/signing.keychain-db"
KEYCHAIN_PASSWORD="$(uuidgen)"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then echo "keychain=$KEYCHAIN" >> "$GITHUB_OUTPUT"; fi
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"

P12="$TMP/developer-id.p12"
trap 'rm -f "$P12"' EXIT
printf '%s' "$DEVELOPER_ID_CERT_P12" | base64 --decode > "$P12"
security import "$P12" -k "$KEYCHAIN" -P "$DEVELOPER_ID_CERT_PASSWORD" -T /usr/bin/codesign
# Lets codesign use the key without a UI prompt.
security set-key-partition-list -S apple-tool:,apple:,codesign: \
    -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" > /dev/null

# Prepend to the user search list; codesign only looks in keychains on it.
EXISTING=()
while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    EXISTING+=("${line//\"/}")
done < <(security list-keychains -d user)
security list-keychains -d user -s "$KEYCHAIN" ${EXISTING[@]+"${EXISTING[@]}"}

IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" \
    | awk '/"Developer ID Application: / { print $2; exit }')"
if [[ -z "$IDENTITY" ]]; then
    echo "::error::DEVELOPER_ID_CERT_P12 has no valid 'Developer ID Application' identity"
    security find-identity -v -p codesigning "$KEYCHAIN"
    exit 1
fi
echo "Imported $(security find-identity -v -p codesigning "$KEYCHAIN" | awk -v id="$IDENTITY" '$2 == id')"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then echo "identity=$IDENTITY" >> "$GITHUB_OUTPUT"; fi
