#!/usr/bin/env bash
# Build (debug) and launch OpenDock, replacing any running instance.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT/scripts/build-app.sh" --debug
pkill -x OpenDock 2>/dev/null || true
sleep 0.3
open "$ROOT/build/OpenDock.app"
echo "▸ launched. Logs: log stream --predicate 'subsystem == \"org.opendock\"' --level debug"
