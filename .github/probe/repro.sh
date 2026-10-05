#!/usr/bin/env bash
# TEMPORARY: minimal reproducer for the Swift 6.3.3 -O crash.
set -uo pipefail
cd "$(mktemp -d)"
SDK="$(xcrun --show-sdk-path)"
SWIFTC=(xcrun swiftc -sdk "$SDK" -target arm64-apple-macos15.0 -swift-version 6 -parse-as-library -module-name R)

variant() {
    local name="$1" body="$2"; shift 2
    cat > "$name.swift" <<EOF
import AppKit
import SwiftUI
$body
func make() -> NSView { H(rootView: Text("x")) }
EOF
    for flags in "-Onone" "-O" "-O -default-isolation MainActor"; do
        if "${SWIFTC[@]}" $flags -c "$name.swift" -o "$name.o" > "$name.log" 2>&1; then r=ok; else r="FAIL($(grep -oE 'signal [0-9]+|error: .*' "$name.log" | head -1))"; fi
        echo "$name [$flags]: $r"
    done
}

variant generic-implicit   'final class H<C: View>: NSHostingView<C> {}'
variant generic-weak       'final class H<C: View>: NSHostingView<C> { weak var x: AnyObject? }'
variant generic-explicit   'final class H<C: View>: NSHostingView<C> { deinit {} }'
variant generic-isolated   'final class H<C: View>: NSHostingView<C> { isolated deinit {} }'
variant concrete-implicit  'final class H: NSHostingView<Text> {}'
variant generic-nsview     'final class H<C: View>: NSView { init(rootView: C) { super.init(frame: .zero) }; required init?(coder: NSCoder) { nil } }'

echo "--- SILGen of implicit deinit (generic, default isolation MainActor)"
echo 'import AppKit
import SwiftUI
final class H<C: View>: NSHostingView<C> {}' > g.swift
"${SWIFTC[@]}" -default-isolation MainActor -emit-silgen g.swift 2>&1 | grep -nE 'deinit|Executor|isolat' | head -40
echo "--- SILGen of explicit deinit"
echo 'import AppKit
import SwiftUI
final class H<C: View>: NSHostingView<C> { deinit {} }' > e.swift
"${SWIFTC[@]}" -default-isolation MainActor -emit-silgen e.swift 2>&1 | grep -nE 'deinit|Executor|isolat' | head -40
