#!/usr/bin/env python3
"""TEMPORARY: applies one candidate workaround for the Swift 6.3.3 -O crash."""
import sys
from pathlib import Path

variant = sys.argv[1]
panel = Path("Sources/DockShell/DockPanel.swift")
ctrl = Path("Sources/DockShell/DockController.swift")
p = panel.read_text()
c = ctrl.read_text()

DECL = "final class DockHostingView<Content: View>: NSHostingView<Content> {"
PROP = "    weak var dropHandler: DockController?\n"
assert DECL in p and PROP in p

def sub(text, old, new):
    assert old in text, old
    return text.replace(old, new)

if variant == "baseline":
    pass
elif variant == "explicit-deinit":
    p = sub(p, PROP, PROP + "\n    deinit {}\n")
elif variant == "isolated-deinit":
    p = sub(p, PROP, PROP + "\n    isolated deinit {}\n")
elif variant == "nonfinal":
    p = sub(p, DECL, DECL.replace("final class", "class"))
elif variant == "no-stored-prop":
    p = sub(p, PROP, "    var dropHandler: DockController? { get { nil } set {} }\n")
elif variant == "strong-box":
    p = sub(p, PROP,
            "    private let dropTarget = DropTarget()\n"
            "    var dropHandler: DockController? {\n"
            "        get { dropTarget.handler }\n"
            "        set { dropTarget.handler = newValue }\n"
            "    }\n")
    p += "\nfinal class DropTarget {\n    weak var handler: DockController?\n}\n"
elif variant == "anyview":
    p = sub(p, DECL, "final class DockHostingView: NSHostingView<AnyView> {")
    c = sub(c, "DockHostingView(rootView: root)", "DockHostingView(rootView: AnyView(root))")
elif variant == "concrete-root":
    p = sub(p, DECL, "final class DockHostingView: NSHostingView<DockHostedRoot> {")
    p += """
struct DockHostedRoot: View {
    let controller: DockController
    var body: some View {
        DockRootView(controller: controller)
            .environment(controller.store)
            .environment(controller.registry)
            .environment(controller.running)
            .environment(controller.shellState)
    }
}
"""
    c = sub(c, """        let root = DockRootView(controller: self)
            .environment(store)
            .environment(registry)
            .environment(running)
            .environment(shellState)
        let hosting = DockHostingView(rootView: root)""",
            "        let hosting = DockHostingView(rootView: DockHostedRoot(controller: self))")
else:
    sys.exit(f"unknown variant {variant}")

panel.write_text(p)
ctrl.write_text(c)
