// Tally: a counter stored beside the package, so it survives relaunch. The count is shared by
// every tile of this widget. docs/scripted-widgets.md explains opendock.storage and settings.set.

async function update({ settings }) {
  if (settings.reset) {
    opendock.storage.set("count", 0);
    opendock.settings.set("reset", false);
    return { count: 0 };
  }
  const stored = opendock.storage.get("count");
  const count = (typeof stored === "number" ? stored : 0) + 1;
  opendock.storage.set("count", count);
  return { count: count };
}

function render({ settings, data }) {
  const count = data && typeof data.count === "number" ? data.count : 0;
  return {
    elements: [
      { type: "number", value: count, label: settings.label },
    ],
    refresh: settings.refreshSeconds,
    accessibilityLabel: settings.label + ", " + count,
  };
}
