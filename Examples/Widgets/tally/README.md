# Tally

A counter that goes up by one on each refresh and remembers the number after OpenDock quits.
The value lives in `Widgets/com.example.tally.storage.json`, beside this folder, so replacing
the folder keeps it. Turn on **Reset** and the next update stores zero and turns Reset back off
with `opendock.settings.set`.

To try it:

```sh
mkdir -p ~/Library/Application\ Support/OpenDock/Widgets
cp -R Examples/Widgets/tally ~/Library/Application\ Support/OpenDock/Widgets/
```

Then, in OpenDock, Settings > Widgets > Scripted Widget > Add to Dock, select the new tile in
Dock Items, and pick **Tally** under Widget.

See [docs/scripted-widgets.md](../../../docs/scripted-widgets.md).
