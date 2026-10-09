# Scripted widgets

A scripted widget is a folder with a `manifest.json` and a `main.js`, in
`~/Library/Application Support/OpenDock/Widgets`. OpenDock runs the script in JavaScriptCore
(which comes with macOS; nothing to install), asks it for a description of its tile, and
draws that description with the same views the built-in widgets use. You write JavaScript;
the dock takes care of drawing, icon sizes, magnification, side edges, timers, settings, and
keeping a broken script from taking anything else down.

This is the format and the API for `apiVersion` 1. It's an early preview: scripts can't
fetch from the network, react to clicks, or save state yet; see [Status](#status).

## Try it

`Examples/Widgets/hello` in this repository is a complete widget. To run it:

```sh
mkdir -p ~/Library/Application\ Support/OpenDock/Widgets
cp -R Examples/Widgets/hello ~/Library/Application\ Support/OpenDock/Widgets/
```

In OpenDock, open Settings > Widgets, add a **Scripted Widget** to the dock, select the new
tile under Dock Items, and pick **Hello** under Widget. Edit `main.js` and save: the tile
reloads on its own. "Show Widgets Folder" in the same settings opens the folder in Finder.

## The package

```
~/Library/Application Support/OpenDock/Widgets/
└── hello/                ← the folder name doesn't matter; the id comes from the manifest
    ├── manifest.json     ← required
    ├── main.js           ← required (another name is fine; set "main")
    └── README.md         ← optional
```

The folder is the unit of install and removal: copy it in, delete it to remove it. If two
folders declare the same `id`, the first one in name order wins and the other is listed under
Problems in the widget's settings. `main.js` may be up to 1 MB. Paths in the manifest are
relative to the folder and may not contain `..` or start with `/`.

## The manifest

```json
{
  "apiVersion": 1,
  "id": "com.example.hello",
  "name": "Hello",
  "version": "1.0.0",
  "summary": "Greets you and counts how often it has redrawn.",
  "symbol": "hand.wave",
  "main": "main.js",
  "author": "Alice",
  "homepage": "https://github.com/alice/opendock-hello",
  "settings": [
    { "key": "name", "title": "Name", "type": "text", "default": "World", "summary": "Who to greet." },
    { "key": "showRing", "title": "Show seconds ring", "type": "bool", "default": true,
      "summary": "Show the seconds of the minute as a ring." },
    { "key": "refreshSeconds", "title": "Redraw every", "type": "integer", "min": 1, "max": 3600,
      "default": 1, "summary": "How often the tile redraws, in seconds." }
  ],
  "permissions": {}
}
```

| Field | Required | Meaning |
| --- | --- | --- |
| `apiVersion` | yes | The API version the script was written for. Only `1` exists. A version OpenDock doesn't know fails to load with a message saying so, rather than running and failing in some obscure way. |
| `id` | yes | Reverse-DNS: letters, digits, `.`, `-`, `_`; 3 to 100 characters; at least one dot; no leading, trailing, or double dots. It's stored in users' `dock.json`, so never change it once people use the widget. Ids starting with `com.newyorkcompute.opendock.` are reserved. |
| `name` | yes | Shown in Settings. |
| `version` | yes | Free-form; semver is a good idea. Shown in Settings. |
| `summary` | yes | One sentence on what the widget shows. |
| `symbol` | no | An SF Symbol name for the widget in Settings. Default `curlybraces`. |
| `main` | no | The script's path inside the folder. Default `main.js`. |
| `author`, `homepage` | no | Shown in Settings. |
| `settings` | no | The widget's settings; see below. Default none. |
| `permissions` | no | What the script may do beyond drawing; see below. Default nothing. |

Unknown top-level fields are ignored, so a manifest written for a newer OpenDock still loads on
an older one as long as its `apiVersion` is understood. What is read is checked strictly: a bad
`id`, a settings key that isn't lowerCamelCase, a default that isn't valid for its type, or a
permission OpenDock doesn't know, and the package doesn't load. The reason appears under
Problems in the Scripted Widget's settings, naming the field.

### Settings

Each entry declares one key, in the same terms as a built-in widget's settings schema (see
[docs/widgets.md](widgets.md)). OpenDock builds the controls in Settings from this list,
validates stored values against it, and hands the script typed values.

| Field | Meaning |
| --- | --- |
| `key` | The name in `dock.json` and in `settings` inside the script. lowerCamelCase ASCII, unique within the manifest, and not `package` (that key is OpenDock's: it says which widget the tile runs). Don't rename a key once published. |
| `type` | `bool`, `text`, `choice`, `integer`, `number`, or `timeZone`. |
| `default` | A JSON string, number, or boolean. It's stored as a string (`true` becomes `"true"`). Must be valid for the type; a `number` or `choice` may also default to `""`, meaning "not set". |
| `summary` | One sentence on what the key does, shown under its control. |
| `title` | The control's label. Optional; defaults to the key split into words (`refreshSeconds` → "Refresh seconds"). |
| `choices` | For `choice`: the allowed strings, at least one. |
| `min`, `max` | For `integer` and `number`: the allowed range, `min` ≤ `max`. |

The controls: a switch for `bool`, a menu for `choice`, a stepper for `integer`, and a text
field for `text`, `number`, and `timeZone`. Scripted widgets don't get custom settings views;
that is what keeps settings validated, documented, and consistent across widgets.

### Permissions

Permissions are declared in the manifest, not requested while the script runs, so a user can see
what a widget does before it runs. The names OpenDock understands:

| Permission | Form | Grants |
| --- | --- | --- |
| `network` | a list of hosts, such as `["api.github.com", "*.open-meteo.com"]` | `opendock.fetch()` to those hosts only (not yet available; see [Status](#status)). |
| `openURL` | `true` | `opendock.openURL()` (not yet available). |
| `shortcuts` | `true`, or a list of shortcut names | `opendock.runShortcut()` (not yet available). |

An unknown permission name fails the load, so a manifest can't ask for something the installed
OpenDock doesn't know and silently get nothing. There are no permissions for the file system,
clipboard, keychain, processes, or AppleScript, and there won't be; a widget that needs those is
a Swift widget.

## The script

`main.js` is a classic script (no modules, no `require`), evaluated once when the widget
loads. It has to define a global function `render`. OpenDock calls `render` whenever the tile
needs drawing and draws what it returns. The sample:

```js
let renders = 0;

function render({ settings, now, size }) {
  renders += 1;
  const seconds = new Date(now).getSeconds();
  return {
    elements: [
      { type: "progress", style: "ring", fraction: seconds / 60, color: settings.color, label: String(seconds) },
      { type: "column", children: [
        { type: "text", style: "primary", text: `Hello, ${settings.name}` },
        { type: "text", style: "secondary", text: `Rendered ${renders}×` },
      ]},
    ],
    refresh: settings.refreshSeconds,
    minWidth: 3,
  };
}
```

Variables at the top level keep their values between calls, for as long as the tile is in the
dock and the script hasn't been reloaded. There is no way to save state across launches yet.

### `render(context)`

`context` has:

| Field | Type | Meaning |
| --- | --- | --- |
| `settings` | object | Every key from the manifest's `settings`, already validated (an invalid stored value reads as the default) and typed: `bool` keys are booleans, `integer` and `number` keys are numbers, the rest are strings. |
| `now` | number | Milliseconds since the epoch, so `new Date(now)` works. |
| `size` | `"regular"` or `"compact"` | `compact` when the dock is on the left or right edge, where a tile is one icon wide and content stacks. Most scripts can ignore it. |
| `locale` | string | The user's locale identifier, for `Intl.NumberFormat` and friends. |

`render` must be synchronous and return a plain object (OpenDock runs it through
`JSON.stringify`, so no functions or cycles). It may throw: the error, with its line number,
shows in the tile and in Settings. Returning something that isn't a tile is an error too, with
the field that's wrong ("elements[2].fraction has the wrong type").

### The tile

```ts
type Tile = {
  elements: Element[];          // laid out along the dock: side by side on the bottom edge, stacked on a side edge
  refresh?: number;             // seconds until the next render; leave it out to render only when something changes
  minWidth?: number;            // least width along the dock, in icon widths (0 to 8), so the tile doesn't jitter as text changes
  accessibilityLabel?: string;  // what VoiceOver reads; built from the texts when left out
};

type Element =
  | { type: "text";      text: string; style?: "primary" | "secondary" | "caption"; color?: Color }
  | { type: "number";    value: number; fractionDigits?: number; unit?: string; label?: string; color?: Color }
  | { type: "progress";  fraction: number; style?: "ring" | "bar"; color?: Color; label?: string }
  | { type: "icon";      symbol: string; color?: Color; size?: "small" | "regular" | "large" }
  | { type: "sparkline"; samples: number[]; capacity?: number; color?: Color }
  | { type: "row";       children: Element[]; spacing?: number; alignment?: Alignment }
  | { type: "column";    children: Element[]; spacing?: number; alignment?: Alignment }
  | { type: "spacer" };

type Alignment = "leading" | "center" | "trailing";
type Color = "red" | "orange" | "yellow" | "green" | "mint" | "teal" | "cyan" | "blue" | "indigo"
           | "purple" | "pink" | "brown" | "gray" | "primary" | "secondary" | "#RRGGBB";
```

- `text`: `primary` is the tile's main line, `secondary` the smaller line under it, `caption`
  smaller still. These are the same styles the built-in tiles use, so they scale with the
  icon size.
- `number`: formatted for the user's locale, with `fractionDigits` decimals, the `unit` after
  it (`"%"`, `"°"`), and the `label` under it in the secondary style.
- `progress`: a ring (the default) or a bar filled to `fraction`, 0 to 1. The label goes inside
  the ring or above the bar.
- `icon`: an SF Symbol by name. `size` is relative to the icon size.
- `sparkline`: a line through samples from 0 to 1, oldest first, like the Network tile's
  chart. `capacity` is how many samples make a full-width chart (the sample count when
  left out), so a chart that's still filling up grows from the left.
- `row` and `column`: nest other elements. `spacing` is in icon widths.
- `spacer`: takes up the free space in a row or column.

Decoding is forgiving where that helps and strict where it matters. An unknown element `type`
draws nothing, so a script written for a newer OpenDock degrades instead of breaking; unknown
fields are ignored; a missing `style`, `color`, `size`, or `alignment`, or one that isn't in
the list, means the default. A required field that's missing or of the wrong type
(`fraction: "half"`) is an error, because quietly drawing an empty ring would hide the bug.

### Refreshing

There is no `setTimeout` or `setInterval`. To be drawn again, return `refresh` seconds.
OpenDock clamps it to between 1 and 3600 seconds, and treats a missing value, zero, a
negative number, or a non-number as "no refresh". Beyond the schedule, `render` runs
immediately when a setting changes, when the package reloads, and when the dock comes back on
screen; nothing runs while the dock is hidden. After an error, the loop stops until one of
those happens, so a bug can't spin at 1 Hz.

### The `opendock` object

Everything the host offers is on one frozen global, `opendock`:

| Member | Does |
| --- | --- |
| `opendock.apiVersion` | `1`. |
| `opendock.log(...args)` | Writes a line to the system log (subsystem `com.newyorkcompute.opendock`, category `Scripted`), prefixed with the widget's id. `log stream --predicate 'subsystem == "com.newyorkcompute.opendock"' --level debug` shows it. |

Nothing else exists: no `fetch`, `XMLHttpRequest`, `require`, `import`, `localStorage`, or
`console` (use `opendock.log`). What JavaScriptCore itself provides (ES2023, `Intl`, `JSON`,
`Math`, `Date`) all works.

## Limits and isolation

Each tile has its own JavaScript context on a background actor, so two tiles of the same widget
keep separate state and a slow script never blocks the dock. The script can't reach the file
system, the network, or any other process. Every call into the script has a time limit; a
script that runs past it is stopped and the tile shows "Timed out". Over any other limit is an
error, not a truncation, so the author notices.

| Limit | Value |
| --- | --- |
| Loading `main.js` | 2 seconds |
| One `render` call | 250 milliseconds |
| `refresh` | 1 to 3600 seconds |
| `main.js` | 1 MB |
| The tile | 64 elements, nesting 4 deep, 64 KB as JSON, 200 characters per text, 256 samples per sparkline, `minWidth` 0 to 8 |

## Errors

A script that throws, times out, returns something that isn't a tile, or fails to load shows a
warning in its tile ("Script error", "Timed out", "Can't load") and the full message, with
the line number when there is one, under the widget's picker in Settings. A package whose
manifest doesn't load is listed under Problems there. A missing package ("Not installed")
keeps the tile's settings, so putting the folder back restores it. Nothing a script does can
take the dock down.

## Status

Shipped in this version (`apiVersion` 1):

- The package and manifest formats, settings, and permission names.
- `render` with the elements above, `refresh`, `minWidth`, and `accessibilityLabel`.
- `opendock.apiVersion` and `opendock.log`.
- Reload on save, Reload and Show Widgets Folder in Settings, errors in the tile and Settings.

Planned, as additions within version 1 (a script can feature-test with
`typeof opendock.fetch === "function"`):

- `opendock.fetch()` to the hosts in `permissions.network`.
- `onClick`, with `opendock.openURL()` and `opendock.runShortcut()` allowed from it.
- Saving state across launches (`opendock.settings.set()` or a per-widget store).
- `image` elements from files in the package.
- Installing from a `.zip`, a per-widget on/off switch, and a gallery.

A change that would break existing scripts will come as `apiVersion` 2, with version 1 still
supported.

## Changelog

- **1** (this version): first release.
