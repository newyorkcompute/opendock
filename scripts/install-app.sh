#!/usr/bin/env bash
# Builds OpenDock and installs it over /Applications/OpenDock.app.
#
#   scripts/install-app.sh            # universal release build (what `make install` runs)
#   scripts/install-app.sh --native   # release build for this Mac's architecture only
#
# Options are passed through to scripts/build-app.sh, which also reads
# OPENDOCK_SIGN_IDENTITY (environment or .env.local). OPENDOCK_INSTALL_DIR
# overrides /Applications. Steps:
#
#   1. build the app bundle
#   2. back up the installed app and ~/Library/Application Support/OpenDock/dock.json
#      to ~/Library/Application Support/OpenDock/Backups/<timestamp>/
#   3. quit the running OpenDock, replace the installed bundle, relaunch it
#
# The app backup is a zip so Launch Services never sees a second OpenDock.app with
# the same bundle identifier. To restore one: ditto -x -k <backup>.app.zip /Applications

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="OpenDock"
BUILT_APP="$ROOT/build/$APP_NAME.app"
INSTALLED_APP="${OPENDOCK_INSTALL_DIR:-/Applications}/$APP_NAME.app"
SUPPORT_DIR="$HOME/Library/Application Support/$APP_NAME"
DOCK_JSON="$SUPPORT_DIR/dock.json"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$SUPPORT_DIR/Backups/$STAMP"

"$ROOT/scripts/build-app.sh" "$@"

if [[ -d "$INSTALLED_APP" || -f "$DOCK_JSON" ]]; then
    echo "▸ backing up to $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    if [[ -d "$INSTALLED_APP" ]]; then
        ditto -c -k --sequesterRsrc --keepParent "$INSTALLED_APP" "$BACKUP_DIR/$APP_NAME.app.zip"
    fi
    if [[ -f "$DOCK_JSON" ]]; then
        cp -p "$DOCK_JSON" "$BACKUP_DIR/dock.json"
    fi
fi

if pgrep -xq "$APP_NAME"; then
    echo "▸ quitting $APP_NAME"
    # OpenDock quits gracefully on SIGTERM (restoring Apple's Dock if it hid it),
    # and flushes its debounced dock.json save on the way out.
    pkill -x "$APP_NAME" || true
    for _ in {1..50}; do pgrep -xq "$APP_NAME" || break; sleep 0.1; done
    if pgrep -xq "$APP_NAME"; then
        echo "$APP_NAME did not quit within 5 s; not replacing the running app" >&2
        exit 1
    fi
fi

echo "▸ installing $INSTALLED_APP"
# Replace the bundle atomically from the installed app's point of view: stage a
# copy next to it, then swap. ditto keeps the signature and metadata intact.
STAGING="$(dirname "$INSTALLED_APP")/.$APP_NAME.app.installing-$$"
trap 'rm -rf "$STAGING"' EXIT
rm -rf "$STAGING"
ditto "$BUILT_APP" "$STAGING"
rm -rf "$INSTALLED_APP"
mv "$STAGING" "$INSTALLED_APP"
codesign --verify --deep --strict "$INSTALLED_APP"

echo "▸ launching $INSTALLED_APP"
open "$INSTALLED_APP"

SIGNATURE="$(codesign -dvv "$INSTALLED_APP" 2>&1 | grep -E '^(Authority|Signature)=' | head -n 1)"
echo "✓ installed ($SIGNATURE). Logs: log stream --predicate 'subsystem == \"com.newyorkcompute.opendock\"' --level debug"
