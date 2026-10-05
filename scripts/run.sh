#!/usr/bin/env bash
# Build (debug) and launch OpenDock, replacing any running instance.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT/scripts/build-app.sh" --debug
pkill -x OpenDock 2>/dev/null || true
# OpenDock quits gracefully on SIGTERM (restoring Apple's Dock if it hid it).
for _ in {1..50}; do pgrep -x OpenDock >/dev/null || break; sleep 0.1; done
open "$ROOT/build/OpenDock.app"
echo "▸ launched. Logs: log stream --predicate 'subsystem == \"com.newyorkcompute.opendock\"' --level debug"
