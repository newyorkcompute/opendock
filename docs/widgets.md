# Widget settings

Each widget in the dock is stored in `dock.json` as a `WidgetInstance`: a `typeID` that
says which widget it is, and a `settings` dictionary of strings that the widget owns. This
page lists every built-in widget, its type ID, and the keys it reads. It's for people
editing `dock.json` by hand, writing a layout to import, or building a widget of their own;
the Settings window covers the same options with checkboxes and menus.

Your layout lives at `~/Library/Application Support/OpenDock/dock.json`. Quit OpenDock
before editing it, or it will write its own copy over yours. A widget looks like this in
the file:

```json
{
  "id" : "0B0B6C2E-8F6E-4B8A-A3B1-7E6F0C1D2A02",
  "kind" : {
    "widget" : {
      "_0" : {
        "settings" : {
          "label" : "Oslo",
          "showSeconds" : "true",
          "timeZone" : "Europe/Oslo"
        },
        "typeID" : "com.newyorkcompute.opendock.widget.clock"
      }
    }
  }
}
```

How settings are read:

- Every value is a string, even booleans (`"true"` / `"false"`) and numbers (`"3"`).
- A missing key means the default.
- A value that isn't allowed for its key is replaced with the default when the file is
  loaded, so a typo can't break a widget.
- Keys a widget doesn't declare are kept as they are, so a file written by a newer OpenDock
  still round-trips through an older one.
- Type IDs and key names never change between versions.

In code, each widget declares these keys as its `settingsSchema` (a `WidgetSettingsSchema`
from `DockCore`). The tables below are generated from those schemas by `make widget-docs`,
and `WidgetDocsTests` fails if they're out of date. Edit the schema, not the tables.

<!-- BEGIN GENERATED (make widget-docs) -->

## Clock

Type ID: `com.newyorkcompute.opendock.widget.clock`

The current time and date.

| Key | Value | Default | What it does |
| --- | --- | --- | --- |
| `showSeconds` | `"true"` or `"false"` | `"false"` | Show seconds in the time. |
| `showDate` | `"true"` or `"false"` | `"true"` | Show the weekday and day of the month under the time. |
| `timeZone` | An IANA time zone name such as `"Europe/Oslo"`, or `""` for the Mac's time zone | `""` | Show the time in this zone instead of the Mac's, for a world clock. |
| `label` | Any text | `""` | A short caption, such as a city name, shown under the time instead of the date. |

## Battery

Type ID: `com.newyorkcompute.opendock.widget.battery`

Charge level and power source.

| Key | Value | Default | What it does |
| --- | --- | --- | --- |
| `showPercentage` | `"true"` or `"false"` | `"true"` | Show the charge percentage next to the ring. |
| `showAccessories` | `"true"` or `"false"` | `"true"` | Show small rings for Bluetooth accessories that report a battery, such as AirPods. |

## Calendar

Type ID: `com.newyorkcompute.opendock.widget.calendar`

Today's date and your next event.

| Key | Value | Default | What it does |
| --- | --- | --- | --- |
| `showNextEvent` | `"true"` or `"false"` | `"true"` | Show the next event beside the date. When off, the tile is just the date icon. |

## System Activity

Type ID: `com.newyorkcompute.opendock.widget.systemactivity`

CPU, memory and disk use at a glance.

| Key | Value | Default | What it does |
| --- | --- | --- | --- |
| `showCPU` | `"true"` or `"false"` | `"true"` | Show the CPU gauge. |
| `showMemory` | `"true"` or `"false"` | `"true"` | Show the memory ring. |
| `showDisk` | `"true"` or `"false"` | `"true"` | Show the startup disk ring. |
| `showCPUHistory` | `"true"` or `"false"` | `"true"` | Draw CPU as a sparkline of the last minute instead of a ring. |

## Weather

Type ID: `com.newyorkcompute.opendock.widget.weather`

Current conditions and a short forecast.

| Key | Value | Default | What it does |
| --- | --- | --- | --- |
| `unit` | One of `"celsius"` or `"fahrenheit"` | `""` | Temperature scale. Empty means the Mac's region setting: Fahrenheit in the US, Celsius elsewhere. |
| `caption` | One of `"location"` or `"condition"` | `"location"` | What the small line under the temperature says: the place's name, or the conditions. |
| `locationMode` | One of `"current"` or `"place"` | `"current"` | Where the weather is for: the Mac's location, or the place in the keys below. |
| `placeName` | Any text | `""` | Name of the chosen place, such as a city. Only used when `locationMode` is `"place"`. |
| `placeRegion` | Any text | `""` | Region or country of the chosen place, shown in the popover. |
| `latitude` | A number from -90 to 90 | `""` | Latitude of the chosen place, in degrees. Without both coordinates the tile uses the Mac's location. |
| `longitude` | A number from -180 to 180 | `""` | Longitude of the chosen place, in degrees. |

## Now Playing

Type ID: `com.newyorkcompute.opendock.widget.nowplaying`

What's playing, with play/pause and skip.

| Key | Value | Default | What it does |
| --- | --- | --- | --- |
| `showControls` | `"true"` or `"false"` | `"true"` | Show previous, play/pause and next buttons on the tile. |
| `showWhenIdle` | `"true"` or `"false"` | `"false"` | Keep the tile in the dock while nothing is playing. When off, it takes no space at all. |

## Time Progress

Type ID: `com.newyorkcompute.opendock.widget.timeprogress`

How much of the year, month, week, or day has passed.

| Key | Value | Default | What it does |
| --- | --- | --- | --- |
| `showYear` | `"true"` or `"false"` | `"true"` | Show how much of the year has passed. |
| `showMonth` | `"true"` or `"false"` | `"true"` | Show how much of the month has passed. |
| `showWeek` | `"true"` or `"false"` | `"false"` | Show how much of the week has passed. The week starts on the day your region's calendar says it does. |
| `showDay` | `"true"` or `"false"` | `"true"` | Show how much of the day has passed. |
| `style` | One of `"bars"` or `"rings"` | `"bars"` | Draw each period as a horizontal bar with its percentage beside it, or as a ring with the percentage under it. |

## Network

Type ID: `com.newyorkcompute.opendock.widget.network`

Download and upload speeds.

| Key | Value | Default | What it does |
| --- | --- | --- | --- |
| `showDownload` | `"true"` or `"false"` | `"true"` | Show the download speed. |
| `showUpload` | `"true"` or `"false"` | `"true"` | Show the upload speed. |
| `showHistory` | `"true"` or `"false"` | `"true"` | Draw a sparkline of the last minute beside the speeds. |
| `unit` | One of `"bytes"` or `"bits"` | `"bytes"` | Measure in bytes per second (KB/s, MB/s), as Finder counts, or in bits per second (Kb/s, Mb/s), as internet plans are sold. |
| `interface` | Any text | `""` | The one interface to measure, by its BSD name such as "en0". Empty means every connected Wi-Fi, Ethernet and cellular link, leaving out loopback, VPN tunnels and the system's own interfaces. |

## Reminders

Type ID: `com.newyorkcompute.opendock.widget.reminders`

How many reminders are waiting, and the list to tick them off.

| Key | Value | Default | What it does |
| --- | --- | --- | --- |
| `listID` | Any text | `""` | The identifier of the list to show, as chosen in Settings. Empty, or a list that doesn't exist on this Mac, means every list. |
| `scope` | One of `"all"` or `"today"` | `"all"` | Which reminders the tile counts and the popover lists: every incomplete reminder, or only those due today or overdue. |
| `showListName` | `"true"` or `"false"` | `"true"` | Show the list's name under the count. When off, the tile is just the icon and the count. |

## Focus Timer

Type ID: `com.newyorkcompute.opendock.widget.focustimer`

Pomodoro-style focus sessions and breaks.

| Key | Value | Default | What it does |
| --- | --- | --- | --- |
| `focusMinutes` | A whole number from 1 to 180 | `"25"` | Length of a focus session, in minutes. |
| `shortBreakMinutes` | A whole number from 1 to 60 | `"5"` | Length of the break after a focus session, in minutes. |
| `longBreakMinutes` | A whole number from 1 to 120 | `"15"` | Length of the long break that ends a cycle, in minutes. |
| `sessionsBeforeLongBreak` | A whole number from 1 to 12 | `"4"` | Focus sessions in a cycle; the break after the last one is the long one. |
| `autoStart` | `"true"` or `"false"` | `"false"` | Start the next focus session or break as soon as one ends. |
| `notify` | `"true"` or `"false"` | `"true"` | Show a notification and play a sound when a session or break ends. |

## Countdown

Type ID: `com.newyorkcompute.opendock.widget.countdown`

Time left until a date.

| Key | Value | Default | What it does |
| --- | --- | --- | --- |
| `date` | Any text | `""` | The moment to count down to: ISO 8601 such as `"2026-12-25T18:00:00Z"`, or a date alone such as `"2026-12-25"` for midnight. Empty means no date is set. |
| `label` | Any text | `""` | What the countdown is for, shown under the time left. |
| `notify` | `"true"` or `"false"` | `"true"` | Show a notification and play a sound when the countdown reaches zero. |

## Stopwatch

Type ID: `com.newyorkcompute.opendock.widget.stopwatch`

Elapsed time, with laps.

| Key | Value | Default | What it does |
| --- | --- | --- | --- |
| `showLaps` | `"true"` or `"false"` | `"true"` | Show the latest lap under the elapsed time. |

## Alarm

Type ID: `com.newyorkcompute.opendock.widget.alarm`

An alarm that rings at a time of day.

| Key | Value | Default | What it does |
| --- | --- | --- | --- |
| `enabled` | `"true"` or `"false"` | `"false"` | Whether the alarm is set. A one-off alarm turns itself off once it has been stopped. |
| `time` | Any text | `"07:00"` | When the alarm rings, as 24-hour `"HH:mm"`. |
| `repeats` | One of `"once"`, `"daily"`, `"weekdays"`, or `"weekends"` | `"once"` | Which days the alarm rings. |
| `label` | Any text | `""` | A name for the alarm, shown in the tile and in the notification. |
| `snoozeMinutes` | A whole number from 1 to 60 | `"9"` | How long Snooze waits before the alarm rings again. |
| `sound` | `"true"` or `"false"` | `"true"` | Play a sound while the alarm rings, as well as showing a notification. |

## Sticky Note

Type ID: `com.newyorkcompute.opendock.widget.stickynote`

A note to yourself, on colored paper.

| Key | Value | Default | What it does |
| --- | --- | --- | --- |
| `text` | Any text | `""` | The note itself, line breaks included. The tile shows its first few lines; the popover shows and edits all of it. |
| `color` | One of `"yellow"`, `"orange"`, `"pink"`, `"green"`, `"blue"`, `"purple"`, `"white"`, `"black"`, or `"translucent"` | `"yellow"` | The paper the note is written on. The colors and white take dark text, black takes white text, and translucent is the same surface as the other widgets. |

<!-- END GENERATED -->

## Declaring settings in your own widget

Give your `DockWidget` a `settingsSchema` with one `WidgetSettingKey` per key: its name,
value type (`.bool`, `.text`, `.choice([...])`, `.integer(range)`, `.number(range)`, or
`.timeZone`), default, and a one-sentence description. A key's default always counts as
valid, so an optional number or choice can default to `""` for "not set", as the Weather
widget's coordinates do. `defaultSettings` comes from the schema, settings views can bind
to a key with `updater.boolBinding(key, in: $instance)` or `stringBinding`, and reading
through the key (`key.value(in: instance.settings)`, `key.boolValue(in:)`,
`key.intValue(in:)`, `key.doubleValue(in:)`) gives you the default whenever the stored
value is missing or invalid. See [Writing a widget](../README.md#writing-a-widget) for the
rest.
