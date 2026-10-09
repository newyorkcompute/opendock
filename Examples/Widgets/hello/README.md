# Hello

The smallest useful scripted widget: a greeting, a count of how often the tile has redrawn, and
a ring that follows the seconds. It shows settings of every kind, the `refresh` interval,
`opendock.log`, and the compact layout on a side edge.

To try it:

```sh
mkdir -p ~/Library/Application\ Support/OpenDock/Widgets
cp -R Examples/Widgets/hello ~/Library/Application\ Support/OpenDock/Widgets/
```

Then, in OpenDock, Settings > Widgets > Scripted Widget > Add to Dock, select the new tile in
Dock Items, and pick **Hello** under Widget. Edit `main.js` and the tile picks up the change.

See [docs/scripted-widgets.md](../../../docs/scripted-widgets.md) for the manifest, the
`render()` contract, and the limits.
