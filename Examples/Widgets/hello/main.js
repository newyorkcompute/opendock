// Hello: the sample scripted widget. Copy this folder into
// ~/Library/Application Support/OpenDock/Widgets to try it, then add a Scripted Widget to the
// dock and pick "Hello" in its settings. docs/scripted-widgets.md explains the API.

// Module state lives as long as the tile does. It's lost when the script reloads.
let renders = 0;

// Called by OpenDock whenever the tile needs drawing: at first, after `refresh` seconds, when a
// setting changes, and when the dock comes back on screen. `settings` holds every key from
// manifest.json, already validated and typed (bool, number, or string).
function render({ settings, now, size }) {
  renders += 1;
  const seconds = new Date(now).getSeconds();
  const elements = [];

  if (settings.showRing) {
    elements.push({
      type: "progress",
      style: "ring",
      fraction: seconds / 60,
      color: settings.color,
      label: String(seconds),
    });
  }

  elements.push({
    type: "column",
    alignment: size === "compact" ? "center" : "leading",
    children: [
      { type: "text", style: "primary", text: `Hello, ${settings.name}` },
      { type: "text", style: "secondary", text: renders === 1 ? "Rendered once" : `Rendered ${renders}×` },
    ],
  });

  if (renders % 10 === 0) {
    opendock.log("rendered", renders, "times");
  }

  return {
    elements,
    refresh: settings.refreshSeconds,
    minWidth: 3,
    accessibilityLabel: `Hello, ${settings.name}. Rendered ${renders} times.`,
  };
}
