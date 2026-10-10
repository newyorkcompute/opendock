# Scripted widgets

A scripted widget is a folder with a `manifest.json` and a `main.js`, in
`~/Library/Application Support/OpenDock/Widgets`. OpenDock runs the script in JavaScriptCore
(which comes with macOS; nothing to install), asks it for a description of its tile, and
draws that description with the same views the built-in widgets use. You write JavaScript;
the dock takes care of drawing, icon sizes, magnification, side edges, timers, settings, and
keeping a broken script from taking anything else down.

This is the format and the API for `apiVersion` 1. Scripts can fetch from hosts they declare
and save state across launches. They still can't react to clicks; see [Status](#status).

## Try it

`Examples/Widgets/hello` is a complete widget that only draws. `open-meteo` fetches a public
forecast, and `tally` keeps a counter in storage. To run one of them:

```sh
mkdir -p ~/Library/Application\ Support/OpenDock/Widgets
cp -R Examples/Widgets/hello ~/Library/Application\ Support/OpenDock/Widgets/
```

Use `open-meteo` or `tally` in place of `hello` for the other two. In OpenDock, open
Settings > Widgets, add a **Scripted Widget** to the dock, select the new tile under Dock
Items, and pick the widget under Widget. Edit `main.js` and save: the tile reloads on its
own. "Show Widgets Folder" in the same settings opens the folder in Finder.

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
| `network` | a list of hosts, such as `["api.github.com", "*.open-meteo.com"]` | `opendock.fetch()` to those hosts only. A pattern is an exact host, or one leading `*.` label (`*.open-meteo.com` matches `api.open-meteo.com` and `a.b.open-meteo.com`, not `open-meteo.com`). `*.com` is rejected. Matching is case-insensitive. |
| `openURL` | `true` | `opendock.openURL()` (not yet available). |
| `shortcuts` | `true`, or a list of shortcut names | `opendock.runShortcut()` (not yet available). |

An unknown permission name fails the load, so a manifest can't ask for something the installed
OpenDock doesn't know and silently get nothing. There are no permissions for the file system,
clipboard, keychain, processes, or AppleScript, and there won't be; a widget that needs those is
a Swift widget.

## The script

`main.js` is a classic script (no modules, no `require`), evaluated once when the widget
loads. It has to define a global function `render`. It may also define `update`. OpenDock
calls `update` (when it exists) and then `render` whenever the tile needs new data, and draws
what `render` returns. The sample:

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
dock and the script hasn't been reloaded. To keep state across launches, use
`opendock.storage` or `opendock.settings.set` (below). Two tiles of the same package do not
share top-level variables; they do share storage.

### `render(context)`

`context` has:

| Field | Type | Meaning |
| --- | --- | --- |
| `settings` | object | Every key from the manifest's `settings`, already validated (an invalid stored value reads as the default) and typed: `bool` keys are booleans, `integer` and `number` keys are numbers, the rest are strings. This is the snapshot at the start of the call. |
| `now` | number | Milliseconds since the epoch, so `new Date(now)` works. |
| `size` | `"regular"` or `"compact"` | `compact` when the dock is on the left or right edge, where a tile is one icon wide and content stacks. Most scripts can ignore it. |
| `locale` | string | The user's locale identifier, for `Intl.NumberFormat` and friends. |
| `data` | any | The value the last `update()` returned, or `null` when the script has no `update` or hasn't completed one. |

`render` must be synchronous and return a plain object (OpenDock runs it through
`JSON.stringify`, so no functions or cycles). It may throw: the error, with its line number,
shows in the tile and in Settings. Returning something that isn't a tile is an error too, with
the field that's wrong ("elements[2].fraction has the wrong type").

### `update(context)`

Optional. When the script defines it, OpenDock calls it before each scheduled `render`,
including the first time the tile is shown and whenever a setting changes. It may be `async`
and `await opendock.fetch`. Whatever it returns (or resolves to) is cached and passed to
`render` as `context.data`. On the way into `update`, `context.data` is the previous result,
or `null` the first time.

Moving the dock to a side edge, which only changes `context.size`, renders again from that
cache and does not call `update`. Nothing runs while the dock is hidden. The interval still
comes from `render`'s `refresh`, not from `update`.

`update` has 10 seconds of wall-clock time, fetches included, and 2 seconds of JavaScript
between awaits. Past either, the tile shows "Timed out" and the loop stops until something
changes (a setting, a reload, or the dock coming back). A thrown error does the same, and
settings the call tried to write are discarded.

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

There is no `setTimeout` or `setInterval`. To be drawn again, return `refresh` seconds from
`render`. OpenDock clamps it to between 1 and 3600 seconds, and treats a missing value, zero,
a negative number, or a non-number as "no refresh". A script with `update` is updated, then
rendered, on that same schedule. Beyond the schedule, both run immediately when a setting
changes, when the package reloads, and when the dock comes back on screen; nothing runs while
the dock is hidden. After an error, the loop stops until one of those happens, so a bug can't
spin at 1 Hz.

### The `opendock` object

Everything the host offers is on one frozen global, `opendock`:

| Member | Does |
| --- | --- |
| `opendock.apiVersion` | `1`. |
| `opendock.log(...args)` | Writes a line to the system log (subsystem `com.newyorkcompute.opendock`, category `Scripted`), prefixed with the widget's id. `log stream --predicate 'subsystem == "com.newyorkcompute.opendock"' --level debug` shows it. |
| `opendock.fetch(url, options)` | Installed only when `permissions.network` lists at least one host. See below. |
| `opendock.storage.get(key)` / `set(key, value)` | A JSON object stored beside the package. See below. |
| `opendock.settings.get(key)` / `set(key, value)` | The manifest's settings, readable and writable. See below. |

There is no `XMLHttpRequest`, `require`, `import`, `localStorage`, or `console` (use
`opendock.log`). `fetch` on `opendock` is the only network call, and only when the manifest
asks for it. What JavaScriptCore itself provides (ES2023, `Intl`, `JSON`, `Math`, `Date`) all
works.

### `opendock.fetch(url, options)`

```js
const response = await opendock.fetch(url, { method, headers, body });
const payload = await response.json();
```

Call it from `update` and `await` it. `render` stays synchronous, so it reads `context.data`
instead of fetching.

`options` is optional. `method` is `"GET"` (the default) or `"POST"`. A string `body` is sent
as text (`text/plain;charset=UTF-8` unless you set `Content-Type`); any other `body` is
`JSON.stringify`'d and sent as `application/json`. GET with a body is an error.

The promise resolves to `{ status, ok, headers, text(), json() }`. `ok` is true for status
200–299. `text()` and `json()` return promises. The body has to be UTF-8 text.

Rules, all applied before a request leaves the machine, and again for every redirect:

- HTTPS only. A username or password in the URL is refused.
- The host has to match `permissions.network`. Anything else throws, the tile shows
  "Can't contact \<host\>", and nothing is connected.
- Redirects are not followed by the transport. OpenDock follows 301, 302, and 303 as GET
  without the body, and 307 and 308 with the same method and body, and only when the next URL
  is still on the list. An off-list or non-HTTPS redirect is the same error and is not
  requested. More than 5 redirects fails.
- One request or response may be 1 MB. Four fetches may be in flight. Each fetch has 10
  seconds, which fits inside `update`'s 10 second budget.
- `Host`, `Content-Length`, `Transfer-Encoding`, and `Connection` are dropped. A missing
  `User-Agent` is sent as `OpenDock`.
- No cookies and no cache.

### `opendock.storage`

```js
const count = opendock.storage.get("count"); // null when missing
opendock.storage.set("count", count + 1);
opendock.storage.set("count");               // deletes the key
```

Values are JSON: objects, arrays, strings, numbers, booleans, and `null`. `undefined`, or a
call with no value, deletes the key. A missing key and a stored `null` both read back as
`null`.

The file is `Widgets/<id>.storage.json`, next to the package folder rather than inside it, so
replacing the folder keeps the state. Every tile of that package id shares the file. The whole
file may be 256 KB; a `set` that would pass that throws and does not write. Keys are 1 to 128
characters. A file that isn't a JSON object, or that's already over the cap, fails the load
and the tile shows "Can't load".

### `opendock.settings`

```js
opendock.settings.get("name");
opendock.settings.set("reset", false);
```

`get` returns the same typed value as `context.settings`, including writes made earlier in
this call. `set` checks the value against the manifest and does not coerce: a bool setting
wants a boolean, an integer or number wants a number, and the rest want a string. An unknown
key, a wrong type, or a value outside `min`/`max` or `choices` throws, and the tile shows
"Script error". A value that's already what's stored is ignored, so setting it again doesn't
restart the tile. A real change is written to `dock.json` and the tile updates. Writes from a
call that then throws are thrown away.

## Limits and isolation

Each tile has its own JavaScript context on a background actor, so two tiles of the same widget
keep separate module state and a slow script never blocks the dock. The script can't reach the
file system, other processes, or any host it didn't declare. Every call into the script has a
time limit; a script that runs past it is stopped and the tile shows "Timed out". Over any
other limit is an error, not a truncation, so the author notices.

| Limit | Value |
| --- | --- |
| Loading `main.js` | 2 seconds of CPU |
| One `render` call | 250 milliseconds of CPU |
| One `update` call | 10 seconds of wall-clock time, and 2 seconds of CPU between awaits |
| One `fetch` | 10 seconds, 1 MB request or response, 4 in flight, 5 redirects |
| Storage file | 256 KB |
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
- `update`, with its result passed to `render` as `context.data`.
- `opendock.fetch` to the hosts in `permissions.network`.
- `opendock.storage` and `opendock.settings.get` / `set`.
- `opendock.apiVersion` and `opendock.log`.
- Reload on save, Reload and Show Widgets Folder in Settings, errors in the tile and Settings.

Planned, as additions within version 1 (a script can feature-test with
`typeof opendock.fetch === "function"`, which is `"undefined"` until the manifest lists a
host):

- `onClick`, with `opendock.openURL()` and `opendock.runShortcut()` allowed from it.
- `image` elements from files in the package.
- Installing from a folder or a `.zip` in Settings, a per-widget on/off switch, and a gallery.

A change that would break existing scripts will come as `apiVersion` 2, with version 1 still
supported.

## Changelog

- **1** (this version): `render`, then `update`, `opendock.fetch`, `opendock.storage`, and
  `opendock.settings`. Fetch, storage, and settings writes are additions: a script that only
  defines `render` still runs.
