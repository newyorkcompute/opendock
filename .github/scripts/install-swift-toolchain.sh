#!/usr/bin/env bash
# Installs the swift.org release toolchain $SWIFT_VERSION (e.g. "6.4.0") into
# ~/Library/Developer/Toolchains and activates it for later steps via
# TOOLCHAINS, layered on top of the SDK from the selected Xcode.
# Skips the download when the toolchain is already present (restored from cache).

set -euo pipefail

: "${SWIFT_VERSION:?set SWIFT_VERSION, e.g. 6.4.0}"

NAME="swift-${SWIFT_VERSION}-RELEASE"
TOOLCHAIN="$HOME/Library/Developer/Toolchains/$NAME.xctoolchain"

if [[ ! -d "$TOOLCHAIN" ]]; then
    PKG="$RUNNER_TEMP/$NAME-osx.pkg"
    URL="https://download.swift.org/swift-${SWIFT_VERSION}-release/xcode/$NAME/$NAME-osx.pkg"
    echo "Downloading $URL"
    curl -fsSL --retry 3 -o "$PKG" "$URL"
    installer -pkg "$PKG" -target CurrentUserHomeDirectory
    rm -f "$PKG"
fi

[[ -d "$TOOLCHAIN" ]] || { echo "::error::$TOOLCHAIN missing after install"; exit 1; }

TOOLCHAIN_ID="$(plutil -extract CFBundleIdentifier raw "$TOOLCHAIN/Info.plist")"
echo "TOOLCHAINS=$TOOLCHAIN_ID" >> "$GITHUB_ENV"
TOOLCHAINS="$TOOLCHAIN_ID" swift --version
