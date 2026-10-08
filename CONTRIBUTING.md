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

OpenDock is a pure Swift Package. `Package.swift` is the source of truth for targets, their
dependencies, and compiler settings, and `scripts/build-app.sh` wraps the SwiftPM binary into
`build/OpenDock.app` (Info.plist, icon, ad-hoc signature). No Xcode project is checked in;
[`make xcodeproj`](#working-in-xcode) generates one when you want Xcode's debugger, Instruments,
or SwiftUI previews.

| Command | What it does |
| --- | --- |
| `make build` | Debug build and `.app` bundle |
| `make run` | Debug build, then (re)launch the app |
| `make test` | Run the unit tests (`swift test`) |
| `make format` | Format the Swift sources in place with swift-format |
| `make lint` | Check formatting and lint rules, as CI does |
| `make release` | Optimized universal (Apple silicon + Intel) build and `.app` bundle |
| `make release-native` | Optimized build for your Mac's architecture only (faster) |
| `make install` | `make release`, then replace `/Applications/OpenDock.app` with it (see below) |
| `make xcodeproj` | Generate `App/OpenDock.xcodeproj` with XcodeGen (`make xcode` also opens it) |
| `make clean` | Delete `.build`, `build`, and the generated Xcode project |

Releases are cut by pushing a `v*` tag; see [RELEASING.md](RELEASING.md).

### Installing your build, and keeping its permissions

`make install` is for dogfooding: it builds the universal app, backs up the installed
`/Applications/OpenDock.app` (as a zip) and your `dock.json` to
`~/Library/Application Support/OpenDock/Backups/<timestamp>/`, quits the running OpenDock,
copies the new bundle in, and relaunches it. `scripts/install-app.sh --native` does the same
with a single-architecture build.

By default the bundle is ad-hoc signed, and macOS ties permissions such as Calendar and
Accessibility to the app's signature. An ad-hoc signature changes with every build, so each
reinstall counts as a new app and asks for them again. To keep them across builds, sign with
a certificate of your own:

1. Create a self-signed code-signing certificate named `OpenDock Dev` in your login
   keychain. Either open **Keychain Access**, choose **Keychain Access > Certificate
   Assistant > Create a Certificate…**, set the name to `OpenDock Dev`, **Identity Type** to
   *Self Signed Root*, **Certificate Type** to *Code Signing*, and click **Create**; or do it
   from Terminal:

   ```sh
   cd "$(mktemp -d)"
   openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes -subj '/CN=OpenDock Dev' \
       -addext 'keyUsage=critical,digitalSignature' -addext 'extendedKeyUsage=critical,codeSigning' \
       -keyout key.pem -out cert.pem
   openssl pkcs12 -export -inkey key.pem -in cert.pem -name 'OpenDock Dev' -passout pass:x -out dev.p12
   security import dev.p12 -k ~/Library/Keychains/login.keychain-db -P x -T /usr/bin/codesign
   # Marks the certificate as trusted for code signing (macOS asks for your login password).
   security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db cert.pem
   # Lets codesign use the key without a dialog on every build (asks for the password again).
   security set-key-partition-list -S apple-tool:,apple:,codesign: -s ~/Library/Keychains/login.keychain-db
   ```

   Either way, `security find-identity -v -p codesigning` should now list `OpenDock Dev`.
   If it shows `CSSMERR_TP_NOT_TRUSTED` instead, the certificate isn't trusted yet: run the
   `add-trusted-cert` line above, or double-click the certificate in Keychain Access, expand
   **Trust**, and set **Code Signing** to *Always Trust*.
2. Tell the build about it, either in the environment or in a git-ignored `.env.local` at
   the repo root:

   ```sh
   echo 'OPENDOCK_SIGN_IDENTITY="OpenDock Dev"' >> .env.local
   make install
   ```

`scripts/build-app.sh` then signs every build with that certificate (with the hardened
runtime, as releases are), and `codesign -dv /Applications/OpenDock.app` shows
`Authority=OpenDock Dev`. Permissions you grant are kept from one `make install` to the next.
If macOS asks whether `codesign` may use the key, click **Always Allow** (or run the
`set-key-partition-list` line above once). A self-signed certificate is only for your own
Mac: Gatekeeper still treats
the app as unsigned anywhere else, so releases use a Developer ID (see
[RELEASING.md](RELEASING.md#signing-and-notarization)).

To watch the app's logs while it runs:

```sh
log stream --predicate 'subsystem == "com.newyorkcompute.opendock"' --level debug
```

### Working in Xcode

Opening `Package.swift` in Xcode is enough for editing, but Xcode then runs the `OpenDock`
executable as a bare binary: no `Info.plist`, so no bundle identifier for permission prompts
and no `LSUIElement`, and no Now Playing helper next to it. For the debugger, Instruments, and
SwiftUI previews on the real app, generate a project instead:

```sh
brew install xcodegen   # once
make xcode              # = make xcodeproj + open App/OpenDock.xcodeproj
```

`make xcodeproj` runs [XcodeGen](https://github.com/yonaskolb/XcodeGen) on `App/project.yml`
and writes `App/OpenDock.xcodeproj`, which is git-ignored. Never commit it or edit it by hand;
change `App/project.yml` and regenerate. The project has:

- An `OpenDock` app target that compiles `App/OpenDock` with the package's `Info.plist`,
  entitlements, and icon, and links every other module from `Package.swift` through its
  `OpenDockModules` product. Module settings, dependencies, and tests come from the package,
  so `Package.swift` stays the single source of truth. Select the **OpenDock App** scheme
  (the plain **OpenDock** scheme Xcode also lists is the package's bare executable), then
  press ⌘R to run the app and ⌘U to run the package's tests.
- An `OpenDockNowPlayingHelper` target for `Sources/NowPlayingHelper`, copied into
  `Contents/Frameworks/libOpenDockNowPlayingHelper.dylib` the same way `build-app.sh` does it.

Sources are Xcode 16 synchronized folders, so adding or removing a Swift file doesn't need a
regeneration. Regenerate when you change `App/project.yml`. Adding a module to the app is done
in `Package.swift` alone: put it in `appModules`, which feeds both the executable and
`OpenDockModules` (widgets don't go there; they reach the app through `BuiltInWidgets`). A new
test target needs one line under the `OpenDock App` scheme's `test.targets` in
`App/project.yml` so ⌘U runs it.
`App/project.yml` also mirrors two package settings (`ExistentialAny` and main-actor default
isolation); if those change in `Package.swift`, change them there too.

Builds from Xcode are ad-hoc signed unless `OPENDOCK_SIGN_IDENTITY` is set when you run
`make xcodeproj`, in the environment or in `.env.local`, exactly as for `build-app.sh`. With
the `OpenDock Dev` certificate from
[Installing your build](#installing-your-build-and-keeping-its-permissions), permissions
survive rebuilds from Xcode too. The identity is baked into the generated project, so
regenerate after changing it.

CI, releases, and `make build` all still use SwiftPM and `scripts/build-app.sh`, so run
`make test` and `make lint` before you push even if you did everything in Xcode. Why XcodeGen:
it's a single Homebrew install and a small YAML file, Xcode reads the local package directly so
there is nothing else to keep in sync, and unlike Tuist it adds no project DSL, build cache, or
generated manifests of its own.

### Formatting

Swift code is formatted with [swift-format](https://github.com/swiftlang/swift-format),
which ships with Xcode 16 and later as `swift format`, so there's nothing to install. The
settings live in `.swift-format` at the repo root: 4-space indentation and 120-column lines.
Run `make format` before you commit, and `make lint` to check what CI will check. CI fails
the `Build & test` job on any formatting difference or lint warning.

In Xcode, Editor > Structure > Format File with 'swift-format' (⌃⇧I) formats the current
file with the same settings.

The config works with, and gives identical output on, swift-format 6.3 (Xcode 26) and 6.4
(Xcode 27). When you edit it, change only top-level options and entries in `rules`. Don't
regenerate it with `swift format dump-configuration`, and don't add nested option objects
such as `orderedImports`: every key inside one is required, so an object written by one
version fails to load in a version that added a key to it. Keep the full `rules` list,
because a rule missing from it is turned off.

Whole-repo formatting commits are listed in `.git-blame-ignore-revs`. GitHub's blame view
skips them already; to make `git blame` skip them too, run this once in your checkout:

```sh
git config blame.ignoreRevsFile .git-blame-ignore-revs
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

### Working with Cursor agents

This repository enables the [pstack](https://github.com/cursor/plugins/tree/main/pstack)
plugin at project scope in `.cursor/settings.json`, so Cursor loads it when you open the repo.
pstack is a set of skills that make agents work more carefully: reproduce a bug before fixing
it, keep changes small, and verify against the real app before calling the work done.

- Start a non-trivial task with `/poteto-mode`. It picks a playbook (bug fix, feature,
  refactoring, and so on) and runs the other skills as it needs them.
- Run `/setup-pstack` once to choose which models pstack uses. It writes a rule to your home
  directory (`~/.cursor/rules/pstack-models.mdc`), not to this repo.
- Not sure which skill fits? Ask `/poteto-help`.

pstack doesn't change how OpenDock is built or tested. Verification still means `make test`
plus the manual testing described under [Tests](#tests), and agents running in parallel should
each use their own `--scratch-path`, as described above.

Agents other than Cursor's (Codex, Claude Code, Copilot, and so on) pick up the essentials
from [AGENTS.md](AGENTS.md).

## Code conventions

These keep the codebase consistent and avoid known pitfalls. If you think one of them should
change, open an issue to discuss it.

**Platform**

- The deployment target is macOS 15. Liquid Glass APIs must sit behind
  `if #available(macOS 26, *)`, with a frosted-material fallback.
- OpenDock is a menu bar app (`LSUIElement`). It only changes Apple's Dock when the
  user turns on "Hide Apple's Dock", and then always restores the user's Dock settings
  (`AppleDockHider`).
- The app can't be sandboxed, so it won't ship on the Mac App Store.

**Concurrency and state**

- Everything compiles under Swift 6 strict concurrency, and should build without warnings.
- UI targets (`DockWidgetKit`, `DockShell`, `Widgets/*`, and the `OpenDock` app) use
  main-actor default isolation. `DockCore` and `SystemServices` don't, so mark UI-facing types
  there `@MainActor` explicitly.
- Use `@Observable` for observable state. Don't use `ObservableObject` or Combine.
- Use `isolated deinit` when a `@MainActor` class owns non-Sendable state that its deinit
  has to clean up.
- Generic classes in UI targets are the exception: give them an explicit, empty `deinit {}`
  (see `DockHostingView`). Swift 6.3.3 crashes in `-O` builds on their implicit deinit, and on
  `isolated deinit` too.

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
- Unit tests live in `Tests/DockCoreTests`, `Tests/SystemServicesTests`, and `Tests/WidgetTests`. Logic that can run
  without a screen (models, persistence, geometry) belongs in `DockCore`, where it can be tested.
- `Tests/WidgetTests` checks that `docs/widgets.md` matches the widgets' settings schemas. After changing a
  widget's `settingsSchema`, run `make widget-docs` and commit the regenerated tables.
- Much of the dock panel's behavior (hover, drag and drop, auto-hide, multiple displays)
  can't be covered by unit tests yet. For changes there, describe in your pull request how you
  tested by hand, including your macOS version and display setup.

## Pull requests

- Keep each pull request focused on one change. Separate refactors from behavior changes.
- Link the issue it addresses (`Fixes #123`).
- Run `make test` and `make lint`, and make sure the build has no new warnings.
- For visible changes, include a screenshot or a short screen recording.
- CI (`Build & test` and `Universal release build`) must pass before merging.
- We squash-merge every pull request, so the PR title becomes the commit message on `main`.
  Write it as a short summary in the imperative mood, for example "Add a Weather widget".
  You don't need to tidy up your branch's individual commits.
- Expect review comments. Pushing follow-up commits to the same branch is fine.

## AI-assisted contributions

AI-assisted contributions are welcome. Much of OpenDock is written with coding agents. Whatever
tools you use, you're the author of your pull request:

- You're responsible for every line in it, whoever or whatever wrote it.
- You understand the change and can explain it, including how it fits the existing code.
  Answer review comments yourself.
- You built it and tested it: `make test` passes, and you ran the app and tried what you
  changed. Passing CI isn't testing, because CI can't use the dock.
- If AI did a notable part of the work, say so in the PR: which tool, and what it did.
  Autocomplete and quick questions don't need a mention.

The same goes for issues: read and trim what you post, and check that it's true.

We may close low-effort pull requests and issues made of unreviewed generated output without
a review. That includes code that doesn't build, testing claims that aren't true, and PRs an
agent opened with no human behind it.

## License

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE), the same license as the project.
