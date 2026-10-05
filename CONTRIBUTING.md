# Contributing to OpenDock

Thanks for your interest in OpenDock! Bug reports, widget ideas, and pull requests are all
welcome. This guide covers how to build the project, the conventions the code follows, and
what we look for in a pull request.

By participating, you agree to follow our [Code of Conduct](CODE_OF_CONDUCT.md). To report a
security problem, please follow [SECURITY.md](SECURITY.md) instead of opening a public issue.

## Finding something to work on

- The [issue tracker](https://github.com/newyorkcompute/opendock/issues) doubles as the
  roadmap. Issues labeled `good first issue` are self-contained and a good place to start.
  Labels also say which part of the app an issue touches: `widget`, `shell` (the dock panel
  itself), or `infra` (build, CI, release).
- New widgets are a great first contribution. See
  [Writing a widget](README.md#writing-a-widget) in the README.
- For anything larger than a small fix, please open or comment on an issue first so we can
  agree on the approach before you invest time in it.

## Building and testing

See the README for [toolchain requirements](README.md#build-and-run).

OpenDock is a pure Swift Package. There is no Xcode project, and we don't want one in the
repo. `scripts/build-app.sh` wraps the SwiftPM binary into `build/OpenDock.app` (Info.plist,
icon, ad-hoc signature). You can still edit in Xcode by opening `Package.swift`.

| Command | What it does |
| --- | --- |
| `make build` | Debug build and `.app` bundle |
| `make run` | Debug build, then (re)launch the app |
| `make test` | Run the unit tests (`swift test`) |
| `make release` | Optimized build and `.app` bundle |
| `make clean` | Delete `.build` and `build` |

To watch the app's logs while it runs:

```sh
log stream --predicate 'subsystem == "com.newyorkcompute.opendock"' --level debug
```

### Running several builds at once

If you build from more than one worktree or terminal at the same time (or run coding agents
in parallel), give each one its own SwiftPM scratch directory so they don't fight over
`.build`:

```sh
swift build --scratch-path .build-mytopic
swift test --scratch-path .build-mytopic
```

`.build-*` directories are already ignored by git. When several people or agents share one
checkout, have each of them edit a separate set of files.

## Code conventions

These keep the codebase consistent and avoid known pitfalls. If you think one of them should
change, open an issue to discuss it.

**Platform**

- The deployment target is macOS 15. Liquid Glass APIs must sit behind
  `if #available(macOS 26, *)`, with a frosted-material fallback.
- OpenDock is a menu bar app (`LSUIElement`). It never modifies Apple's Dock.
- The app can't be sandboxed, so it won't ship on the Mac App Store.

**Concurrency and state**

- Everything compiles under Swift 6 strict concurrency, and should build without warnings.
- UI targets (`DockWidgetKit`, `DockShell`, `Widgets/*`, and the `OpenDock` app) use
  main-actor default isolation. `DockCore` and `SystemServices` don't, so mark UI-facing types
  there `@MainActor` explicitly.
- Use `@Observable` for observable state. Don't use `ObservableObject` or Combine.
- Use `isolated deinit` when a `@MainActor` class owns non-Sendable state that its deinit
  has to clean up.

**Persistence**

- Change the dock layout and settings only through `DockStore` methods.
  `store.document` is read-only from outside the store on purpose.
- The layout file (`~/Library/Application Support/OpenDock/dock.json`) is a versioned
  `DockDocument` with tolerant decoding. Keep changes backward compatible: add fields with
  defaults rather than renaming or removing them.
- Widget type IDs (`BuiltInWidgetID.*`, `com.newyorkcompute.opendock.widget.*`) are stored
  in users' layout files. Never rename one.

**Smaller gotchas**

- Compare file URLs with `URL.normalizedPath`, not `==`.
- Settings live in an AppKit-hosted `SettingsWindowController`. The SwiftUI `Settings` scene
  is deliberately not used, because a menu bar app can't open it programmatically.

**Originality**

OpenDock is inspired by [Dockset](https://dockset.app), but it isn't a clone. Don't copy
Dockset's (or any other app's) icons, artwork, or marketing copy.

## Tests

- Write tests with [Swift Testing](https://developer.apple.com/documentation/testing)
  (`import Testing`, `@Suite`, `@Test`, `#expect`). Don't use XCTest.
- Unit tests live in `Tests/DockCoreTests`. Logic that can run without a screen (models,
  persistence, geometry) belongs in `DockCore`, where it can be tested.
- Much of the dock panel's behavior (hover, drag and drop, auto-hide, multiple displays)
  can't be covered by unit tests yet. For changes there, describe in your pull request how you
  tested by hand, including your macOS version and display setup.

## Pull requests

- Keep each pull request focused on one change. Separate refactors from behavior changes.
- Link the issue it addresses (`Fixes #123`).
- Run `make test` and make sure the build has no new warnings.
- For visible changes, include a screenshot or a short screen recording.
- CI (`Build & test` and `Universal release build`) must pass before merging.
- We squash-merge every pull request, so the PR title becomes the commit message on `main`.
  Write it as a short summary in the imperative mood, for example "Add a Weather widget".
  You don't need to tidy up your branch's individual commits.
- Expect review comments. Pushing follow-up commits to the same branch is fine.

## License

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE), the same license as the project.
