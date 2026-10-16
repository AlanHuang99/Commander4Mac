# Releases

The [Release workflow](../.github/workflows/release.yml) builds and publishes on version tags such as `v1.0`. It can also be dispatched against an existing tag. CI runs natively on Apple Silicon and Intel before the release job gets signing credentials. Toolchains use Xcode 26.3 on `macos-26` and `macos-15-intel`.

## Normal release

1. Update the single `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` entries in `project.yml`, and update `CHANGELOG.md` and README download examples. Use a new version and increasing build number.
2. Resolve pinned dependencies, regenerate license resources and run CI checks. Review any dependency/license changes. Commit the generated project and source-kit changes with the release.
3. Push `main` and wait for both hosted CI jobs to pass.
4. Tag that reviewed commit with `v` plus its exact marketing version, then push the tag:

   ```sh
   git tag -a v1.0 -m 'Commander4Mac 1.0'
   git push origin v1.0
   ```

   This example names the first release. Use the new version for subsequent releases; never move an existing release tag.

The release job checks the tag/version match and ancestry from `main`. It imports the Developer ID identity into a temporary keychain, archives the universal production app, verifies every signed slice and bundled source/licenses, submits and staples the app, builds the DMG, submits and staples the image, then validates the actual mounted app before publication. Existing releases are not overwritten.

Assets: `Commander4Mac-VERSION.dmg`, its portable `.sha256`, `LGPL-Sources.tar.gz` and `ThirdPartyNotices.txt`. Full Commander4Mac source is available at the release tag and GitHub's source archive links.

## Signing setup

Repository Actions secrets use the same names as Sonance:

| Secret | Value |
| --- | --- |
| `MACOS_CERT_P12_BASE64` | Base64 of the Developer ID Application certificate and private key exported as PKCS#12. |
| `MACOS_CERT_P12_PASSWORD` | Export password for that PKCS#12 archive. |
| `MACOS_KEYCHAIN_PASSWORD` | A random password for the disposable runner keychain. |
| `MACOS_NOTARY_API_KEY_P8_BASE64` | Base64 of the existing App Store Connect notarization API private key. |
| `MACOS_NOTARY_API_KEY_ID` | That key's ID. |
| `MACOS_NOTARY_ISSUER_ID` | Its issuer UUID. |
| `MACOS_TEAM_ID` | The production team `66LBY954DT`. |

Upload these through GitHub encrypted secrets or `gh secret set` using stdin. Never put secret values in commands, Git, issue reports or logs. Pull-request CI does not use them. The `release` environment permits version tags only; do not grant release credentials to an untrusted branch or PR workflow. Rotate/revoke leaked credentials in Apple's portal and GitHub, rather than removing a file and assuming the leak is repaired.

`script/ci_signing.sh cleanup` runs even on failure and removes the temporary keychain and key files. Diagnostic uploads are restricted to build logs, notary JSON and checksums; credential directories are never uploaded. The local installed development identity is unaffected.

## Failed notarization

Wait operations have a 25-minute deadline. A timeout is a failed job, not a rejection or acceptance. The workflow saves submission IDs, status and full notary logs in a diagnostics artifact. Inspect Apple's status before resubmitting. Do not rebuild or change an artifact while its submission is pending.

The local commands support resuming the same saved submission:

```sh
./script/notarize.sh app-wait
./script/notarize.sh app-finish
./script/notarize.sh dmg-wait
./script/notarize.sh dmg-finish
```

See [manual production packaging](../Packaging/DISTRIBUTION.md) for the complete local flow. `COMMANDER_DISTRIBUTION_DIR` can isolate a local release directory from an earlier archive; use the same directory for build, submit, wait and finish.

## After publication

Download the public DMG and checksum into the same folder. Run `shasum -a 256 -c Commander4Mac-VERSION.dmg.sha256`, `xcrun stapler validate` and Gatekeeper checks, then verify a normal Applications install. Preserve the Niels Provos acknowledgement in release notes and advertising mentioning the included software's features or use.
