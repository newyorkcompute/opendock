# Open-Meteo

The temperature at a latitude and longitude, from the [Open-Meteo](https://open-meteo.com/)
forecast API. No API key. It shows `update()` and `opendock.fetch`: the host calls `update`
on the refresh schedule, the script asks `api.open-meteo.com` (the only host in
`permissions.network`), and `render` draws the cached result from `context.data`.

To try it:

```sh
mkdir -p ~/Library/Application\ Support/OpenDock/Widgets
cp -R Examples/Widgets/open-meteo ~/Library/Application\ Support/OpenDock/Widgets/
```

Then, in OpenDock, Settings > Widgets > Scripted Widget > Add to Dock, select the new tile in
Dock Items, and pick **Open-Meteo** under Widget. A fetch to any other host fails in the tile
before a connection is made.

See [docs/scripted-widgets.md](../../../docs/scripted-widgets.md).
