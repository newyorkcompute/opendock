#!/usr/bin/env bash
# Generates App/OpenDock.xcodeproj from App/project.yml with XcodeGen (brew install xcodegen).
#
#   scripts/xcodeproj.sh          # generate
#   scripts/xcodeproj.sh --open   # generate, then open the project in Xcode
#
# Environment:
#   OPENDOCK_SIGN_IDENTITY  codesign identity for builds from Xcode, e.g. "OpenDock Dev"
#                           (default "-", ad hoc), the same variable scripts/build-app.sh
#                           uses. Set it to keep Calendar and Accessibility permissions
#                           across Xcode builds (see CONTRIBUTING.md).
#   SPARKLE_PUBLIC_ED_KEY   EdDSA public key baked into SUPublicEDKey. Empty until a key
#                           exists (see RELEASING.md). Rerun this after changing it.
#
# Like build-app.sh, this also reads a git-ignored .env.local at the repo root. The identity
# and the public key are baked into the generated project, so rerun this after changing them.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OPEN=0
for arg in "$@"; do
    case "$arg" in
        --open) OPEN=1 ;;
        -h|--help) sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $arg (see --help)" >&2; exit 2 ;;
    esac
done

command -v xcodegen > /dev/null \
    || { echo "xcodegen not found. Install it with: brew install xcodegen" >&2; exit 1; }

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

# project.yml reads these with ${OPENDOCK_SIGN_IDENTITY} and ${SPARKLE_PUBLIC_ED_KEY}.
export OPENDOCK_SIGN_IDENTITY="${OPENDOCK_SIGN_IDENTITY:--}"
export SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"

xcodegen generate --spec "$ROOT/App/project.yml"
if [[ "$OPENDOCK_SIGN_IDENTITY" != "-" ]]; then
    echo "▸ Xcode builds will be signed with '$OPENDOCK_SIGN_IDENTITY'"
fi

if [[ "$OPEN" == 1 ]]; then
    open "$ROOT/App/OpenDock.xcodeproj"
fi
