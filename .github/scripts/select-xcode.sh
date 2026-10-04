#!/usr/bin/env bash
# Selects an Xcode on a GitHub-hosted macOS runner.
#
# Uses $XCODE_VERSION (e.g. "26.6") when set, otherwise the newest stable
# /Applications/Xcode_<version>.app (betas and release candidates are skipped).
# Writes `version` to $GITHUB_OUTPUT for cache keys.

set -euo pipefail

if [[ -n "${XCODE_VERSION:-}" ]]; then
    XCODE="/Applications/Xcode_${XCODE_VERSION}.app"
    [[ -d "$XCODE" ]] || { echo "::error::$XCODE is not installed"; ls -d /Applications/Xcode*.app; exit 1; }
else
    XCODE="$(ls -d /Applications/Xcode_*.app \
        | grep -Ei '/Xcode_[0-9]+(\.[0-9]+)*\.app$' \
        | sort -V | tail -n 1)"
    [[ -n "$XCODE" ]] || { echo "::error::no Xcode found"; exit 1; }
fi

sudo xcode-select --switch "$XCODE/Contents/Developer"

VERSION="$(xcodebuild -version | awk '/^Xcode/ { print $2 }')"
echo "Selected $XCODE (Xcode $VERSION)"
xcodebuild -version
swift --version

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "version=$VERSION" >> "$GITHUB_OUTPUT"
fi
