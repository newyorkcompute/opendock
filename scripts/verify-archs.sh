#!/usr/bin/env bash
# Fails unless a Mach-O binary contains every listed architecture.
#
#   scripts/verify-archs.sh build/OpenDock.app/Contents/MacOS/OpenDock arm64 x86_64
#
# `lipo -verify_arch` with several architectures isn't portable: Xcode 27's lipo
# rejects it ("-verify_arch requires exactly one input file"), so compare against
# the list lipo reports instead.

set -euo pipefail

[[ $# -ge 2 ]] || { echo "usage: $0 <binary> <arch>..." >&2; exit 2; }
BINARY="$1"; shift
[[ -f "$BINARY" ]] || { echo "$BINARY: no such file" >&2; exit 1; }

if ! ACTUAL="$(lipo -archs "$BINARY" 2>/dev/null)"; then
    # Older lipo without -archs: "Architectures in the fat file: … are: x86_64 arm64"
    # or "Non-fat file: … is architecture: arm64".
    ACTUAL="$(lipo -info "$BINARY" | sed -E 's/.*(are|architecture): //')"
fi

MISSING=()
for arch in "$@"; do
    [[ " $ACTUAL " == *" $arch "* ]] || MISSING+=("$arch")
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "$BINARY is missing ${MISSING[*]} (has: $ACTUAL)" >&2
    exit 1
fi
echo "$BINARY: $ACTUAL"
