#!/usr/bin/env bash
# Resolves the EdDSA public key stamped into the app as SUPublicEDKey.
#
# SPARKLE_PUBLIC_ED_KEY, when set, wins. Otherwise the key is derived from
# SPARKLE_PRIVATE_KEY (a 32-byte seed from `generate_keys -x`, or a legacy 96-byte key).
# If both are set they must match. If neither is set, the public key is left empty and
# scripts/build-app.sh omits SUPublicEDKey.
#
# Writes public_key to $GITHUB_OUTPUT when that variable is set. The public key is not a secret.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -f "$ROOT/.env.local" ]]; then
    ENV_SNAPSHOT="$(export -p | grep -E '^declare -x SPARKLE_(PUBLIC_ED_KEY|PRIVATE_KEY)=' || true)"
    set -a
    # shellcheck disable=SC1091
    source "$ROOT/.env.local"
    set +a
    eval "$ENV_SNAPSHOT"
fi

trim() {
    local value="$1"
    printf '%s' "$value" | tr -d '[:space:]'
}

PUBLIC="$(trim "${SPARKLE_PUBLIC_ED_KEY:-}")"
PRIVATE="$(trim "${SPARKLE_PRIVATE_KEY:-}")"

DERIVED=""
if [[ -n "$PRIVATE" ]]; then
    DERIVED="$(SPARKLE_PRIVATE_KEY="$PRIVATE" swift "$ROOT/scripts/sparkle-public-key.swift")"
    DERIVED="$(trim "$DERIVED")"
fi

if [[ -n "$PUBLIC" && -n "$DERIVED" && "$PUBLIC" != "$DERIVED" ]]; then
    echo "::error::SPARKLE_PUBLIC_ED_KEY does not match the public key derived from SPARKLE_PRIVATE_KEY." >&2
    echo "Unset SPARKLE_PUBLIC_ED_KEY to use the derived key, or set it to the string generate_keys printed." >&2
    exit 1
fi

RESOLVED="${PUBLIC:-$DERIVED}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
        echo "public_key<<EOF"
        printf '%s\n' "$RESOLVED"
        echo "EOF"
    } >> "$GITHUB_OUTPUT"
fi

if [[ -z "$RESOLVED" ]]; then
    echo "Sparkle public key is unset. This build cannot verify updates until SPARKLE_PRIVATE_KEY or SPARKLE_PUBLIC_ED_KEY is set (see RELEASING.md)."
elif [[ -n "$PUBLIC" ]]; then
    echo "Using SPARKLE_PUBLIC_ED_KEY from the environment."
    echo "SUPublicEDKey=$RESOLVED"
else
    echo "Derived SUPublicEDKey from SPARKLE_PRIVATE_KEY."
    echo "SUPublicEDKey=$RESOLVED"
fi
