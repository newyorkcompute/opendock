# Releasing OpenDock

Releases are built by the [Release workflow](.github/workflows/release.yml) on GitHub's
macOS runner. Pushing a `v*` tag builds a universal (Apple silicon + Intel) `OpenDock.app`,
zips it, attests the zip's [build provenance](#verifying-a-download), and publishes a GitHub
Release with the zip, its SHA-256 checksum, and auto-generated notes.

## Cutting a release

1. Make sure `main` is green in CI.
2. Tag the commit and push the tag:

   ```sh
   git tag v0.1.0
   git push origin v0.1.0
   ```

   A tag with a suffix, like `v0.2.0-beta.1`, publishes a pre-release.
3. Watch the run under **Actions > Release**. When it finishes, the release appears under
   **Releases** with `OpenDock-<version>.zip` and `OpenDock-<version>.zip.sha256`.

The tag sets `CFBundleShortVersionString` (`v0.2.0-beta.1` becomes `0.2.0`; the suffix only
appears in the zip name and the release title). `CFBundleVersion` is the commit count, so it
only ever goes up.

### Dry runs

To check the pipeline without publishing anything, run **Actions > Release > Run workflow**
on any branch, optionally with a version. Pull requests that touch `scripts/`, the
`Makefile`, `App/Resources/`, or the workflow also run it. A dry run does the same build
and uploads the zip and checksum as a workflow artifact instead of creating a release. It
doesn't attest the zip, so only released zips have attestations.

## Verifying a download

Every release zip has a [build provenance attestation](https://docs.github.com/en/actions/security-guides/using-artifact-attestations-to-establish-provenance-for-builds):
a Sigstore-signed record that the zip was built by this repository's Release workflow, from
a given tag and commit. While releases aren't notarized, it's the way to check that a zip
really came from this repo's CI before clearing its quarantine flag. With the
[GitHub CLI](https://cli.github.com):

```sh
gh attestation verify OpenDock-*.zip --repo newyorkcompute/opendock
```

It shows the workflow and tag that built the zip (add `--format json` for the full record,
including the commit), and fails if the zip was modified or built anywhere else. The attestations are also listed under the repository's
**Actions > Attestations**.

## Building locally

```sh
make release                 # universal app in build/OpenDock.app (make release-native: this Mac only)
make dist                    # build/dist/OpenDock-<version>.zip + .sha256
```

`scripts/build-app.sh` reads these environment variables (also from a git-ignored
`.env.local` at the repo root; the environment takes precedence):

| Variable | Default | Sets |
| --- | --- | --- |
| `OPENDOCK_VERSION` | `0.1.0` | `CFBundleShortVersionString` |
| `OPENDOCK_BUILD` | commit count | `CFBundleVersion` |
| `OPENDOCK_SIGN_IDENTITY` | `-` (ad hoc) | `codesign` identity (name or SHA-1), e.g. `Developer ID Application: Name (TEAMID)`. Only Developer ID signatures get a secure timestamp; for local self-signed certificates see [CONTRIBUTING.md](CONTRIBUTING.md#installing-your-build-and-keeping-its-permissions) |

To sign and notarize locally, store notary credentials once with
`xcrun notarytool store-credentials opendock`, then:

```sh
export OPENDOCK_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
make release
NOTARY_KEYCHAIN_PROFILE=opendock make notarize
make dist
```

## Signing and notarization

Until the project has an Apple Developer ID, releases are **ad-hoc signed and not
notarized**, so Gatekeeper blocks them on first launch. Users have to either:

- right-click `OpenDock.app`, choose **Open**, and confirm (on macOS 15 and later, if there
  is no Open button, click **Open Anyway** in **System Settings > Privacy & Security**), or
- remove the quarantine flag: `xattr -dr com.apple.quarantine /Applications/OpenDock.app`.

The release notes of unnotarized builds say this automatically. Users can
[verify the zip](#verifying-a-download) first.

The workflow signs and notarizes as soon as these repository secrets exist
(**Settings > Secrets and variables > Actions**); no workflow changes are needed. Without
them, those steps are skipped.

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_CERT_P12` | Base64 of a `.p12` export of the **Developer ID Application** certificate and its private key: `base64 -i cert.p12 \| pbcopy` |
| `DEVELOPER_ID_CERT_PASSWORD` | The password chosen when exporting the `.p12` |

Plus one set of notarization credentials:

| Secret | Value |
| --- | --- |
| `APPLE_ID` | Apple ID email of a member of the developer team |
| `APPLE_TEAM_ID` | 10-character team ID ([Membership details](https://developer.apple.com/account)) |
| `APPLE_APP_PASSWORD` | An [app-specific password](https://account.apple.com) for that Apple ID |

or an App Store Connect API key (preferred for CI, since it doesn't depend on a person's
account):

| Secret | Value |
| --- | --- |
| `NOTARY_API_KEY` | Contents of the `AuthKey_<KEYID>.p8` file (team key with Developer access) |
| `NOTARY_API_KEY_ID` | The key ID |
| `NOTARY_API_ISSUER_ID` | The issuer ID shown above the keys list |

With a certificate the app is signed with the hardened runtime and a secure timestamp.
With notary credentials too, tag builds and manual runs submit it with `xcrun notarytool`,
staple the ticket with `xcrun stapler`, and check it with `spctl` before zipping. PR dry
runs sign but skip notarization.

## Automatic updates (Sparkle)

The app embeds [Sparkle](https://sparkle-project.org) 2.10.0. **Check for Updates…** is in
the menu bar menu, and Settings > General has the current version and an automatic-check
toggle (about once a day). The app is menu-bar-only: while Sparkle's update window is on
screen it briefly uses a normal activation policy so that window can appear, then goes back
to having no Dock icon.

`SUFeedURL` is `https://github.com/newyorkcompute/opendock/releases/latest/download/appcast.xml`,
which is the `appcast.xml` asset on the latest non-prerelease. Pre-release tags still upload
an appcast, but GitHub's `latest` URL skips pre-releases, so stable installs are not offered
a beta. The private EdDSA key is never committed. `SUPublicEDKey` is stamped at build time.

The app is not sandboxed, so Sparkle's Installer and Downloader XPC services stay off
(`SUEnableInstallerLauncherService` and `SUEnableDownloaderService` are not set). The
framework still ships with `Autoupdate`, `Updater.app`, and those XPC services inside it;
`scripts/build-app.sh` copies and signs them.

### Generate the key pair once

On a Mac, from Sparkle 2.10.0's tools (the same zip Swift Package Manager downloads):

```sh
curl -fsSL -o Sparkle.zip \
    https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-for-Swift-Package-Manager.zip
unzip Sparkle.zip
bin/generate_keys
```

That stores the private key in your login keychain and prints `SUPublicEDKey`. Export the
private key to a file (one base64 line), then delete the file after copying it:

```sh
bin/generate_keys -x sparkle-private-key.txt
```

Add the file's contents as the Actions secret `SPARKLE_PRIVATE_KEY`
(**Settings > Secrets and variables > Actions > Secrets**). Do not commit the file.
`bin/generate_keys -p` prints the public key again later.

Release builds derive `SUPublicEDKey` from that secret and stamp it into Info.plist, so the
secret alone is enough. To pin the public key instead, set the Actions **variable** (not a
secret) `SPARKLE_PUBLIC_ED_KEY` to the exact string `generate_keys` printed. If both are set
they must match. For a local build, put the same public key in `.env.local`:

```sh
echo 'SPARKLE_PUBLIC_ED_KEY="the string generate_keys printed"' >> .env.local
```

`make xcodeproj` bakes that value into the generated project; rerun it after changing the
key. Until either value exists, builds omit `SUPublicEDKey` and log a warning. Update checks
then cannot verify a feed. That is expected for local development.

### What the release workflow does

After the zip is built, `scripts/generate-appcast.sh` runs Sparkle's `generate_appcast` with
`--ed-key-file` (the key is not passed on the command line). The enclosure URL is the zip on
that git tag, and `appcast.xml` is uploaded as a release asset. Each appcast contains just
that version, which is enough for Sparkle to offer the update. Delta updates are not
produced, because the workflow does not have the previous zip in the same directory.

If `SPARKLE_PRIVATE_KEY` is missing, the step logs a warning and exits successfully. The zip
and checksum still publish; there is no `appcast.xml`, so Sparkle will not offer that build
as an update.

### What notarization adds

Sparkle does not notarize. Notarization is the Developer ID certificate and the notary
credentials in the tables above. When those secrets exist, the same workflow signs with the
hardened runtime, notarizes, and staples **before** the zip that `generate_appcast` records.
That is what makes Gatekeeper accept the app on first launch without a right-click Open.

Until then, releases stay ad-hoc signed. Sparkle can still install a newer zip and clears
the quarantine flag as it does, but an ad-hoc signature is not a Developer ID signature, so
the first launch of a downloaded copy is still blocked the way
[Signing and notarization](#signing-and-notarization) describes. Ship the key pair whenever
you want update checks to verify the appcast; ship the Developer ID and notary secrets
whenever you want Gatekeeper to accept the app those updates install.
