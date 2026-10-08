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

`scripts/build-app.sh` reads these environment variables:

| Variable | Default | Sets |
| --- | --- | --- |
| `OPENDOCK_VERSION` | `0.1.0` | `CFBundleShortVersionString` |
| `OPENDOCK_BUILD` | commit count | `CFBundleVersion` |
| `OPENDOCK_SIGN_IDENTITY` | `-` (ad hoc) | `codesign` identity, e.g. `Developer ID Application: Name (TEAMID)` |

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
