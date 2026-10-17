# Releases

The [Release workflow](../.github/workflows/release.yml) builds and publishes on version tags such as `v1.0`. It can also be dispatched against an existing tag. CI runs natively on Apple Silicon and Intel before the release job gets signing credentials. Toolchains use Xcode 26.3 on `macos-26` and `macos-15-intel`.

## Normal release

1. Update the single `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` entries in `project.yml`, and update `CHANGELOG.md` and README download examples. Use a new version and increasing build number.
2. Resolve pinned dependencies, regenerate license resources and run CI checks. Review any dependency/license changes. Commit the generated project and source-kit changes with the release.
3. Open a pull request and wait for both required hosted CI jobs to pass, then merge using the repository's allowed merge method. Do not use an administrator bypass. If the merge creates a new commit, verify its complete tree equals the tested PR head; otherwise wait for hosted CI on the changed tree.
4. Tag that reviewed commit on `main` with `v` plus its exact marketing version, then push the tag. Release CI repeats all native checks on that exact tag before signing:

   ```sh
   git tag -a v1.0 -m 'Commander4Mac 1.0'
   git push origin v1.0
   ```

   This example names the first release. Use the new version for subsequent releases; never move an existing release tag.

The release job checks the tag/version match and ancestry from `main`. It imports the Developer ID identity into a temporary keychain, verifies the update key matches the app, archives and exports the universal production app with Xcode's Developer ID export, verifies every signed slice and bundled source/licenses, submits and staples the app, builds the DMG, submits and staples the image, then validates the actual mounted app. Pinned Sparkle tools generate a signed appcast from the final DMG. Public-key verification checks both XML and archive signatures plus exact release metadata before publication. Existing releases are not overwritten.

Assets: `Commander4Mac-VERSION.dmg`, its portable `.sha256`, `appcast.xml`, `LGPL-Sources.tar.gz` and `ThirdPartyNotices.txt`. Full Commander4Mac source is available at the release tag and GitHub's source archive links.

## Signing setup

Encrypted secrets in the repository's `release` environment:

| Secret | Value |
| --- | --- |
| `MACOS_CERT_P12_BASE64` | Base64 of the Developer ID Application certificate and private key exported as PKCS#12. |
| `MACOS_CERT_P12_PASSWORD` | Export password for that PKCS#12 archive. |
| `MACOS_KEYCHAIN_PASSWORD` | A random password for the disposable runner keychain. |
| `MACOS_NOTARY_API_KEY_P8_BASE64` | Base64 of the existing App Store Connect notarization API private key. |
| `MACOS_NOTARY_API_KEY_ID` | That key's ID. |
| `MACOS_NOTARY_ISSUER_ID` | Its issuer UUID. |
| `MACOS_TEAM_ID` | The production team `66LBY954DT`. |
| `SPARKLE_ED_PRIVATE_KEY` | Commander4Mac's separate Ed25519 signing key export, exactly as produced by Sparkle `generate_keys -x`. This is not Sonance's key. |

Upload these through the environment's GitHub encrypted secrets settings or `gh secret set --env release` using stdin. Never put secret values in commands, Git, issue reports or logs. Pull-request CI does not use them. The `release` environment permits version tags only; do not grant release credentials to an untrusted branch or PR workflow. Rotate/revoke leaked credentials in Apple's portal and GitHub, rather than removing a file and assuming the leak is repaired.

`script/ci_signing.sh cleanup` runs even on failure and removes the temporary keychain and key files. Diagnostic uploads are restricted to build logs, notary JSON and checksums; credential directories are never uploaded. The local installed development identity is unaffected.

## Automatic update feed

The production app reads `https://github.com/AlanHuang99/Commander4Mac/releases/latest/download/appcast.xml`. Enclosures point to immutable version-tagged DMGs. Do not edit a published feed or DMG; both signatures cover their exact bytes. `SUPublicEDKey` is checked in, while the private key stays in Keychain, protected recovery storage and GitHub's encrypted release environment. Routine releases reuse that key. Follow [Sparkle's key rotation guidance](https://sparkle-project.org/documentation/#rotating-signing-keys) if it is ever lost or compromised.

Automatic checks default to on; background downloads are opt-in. Sparkle owns persistence of those preferences. Only the production identity installed in Applications starts the updater. Version 1.0 lacks Sparkle and requires one manual 1.1 installation. Subsequent update restarts wait for operations, block new mutations during the final save, and require a successful workspace write.

For a local release, set `COMMANDER_UPDATE_KEY_FILE` to an owner-only private key export and pass it to `script/update_feed.py check-key`. After the final DMG is stapled:

```sh
python3 script/update_feed.py generate --app .build/distribution/export/Commander4Mac.app \
  --archive .build/distribution/Commander4Mac-VERSION.dmg --feed .build/distribution/appcast.xml \
  --key-file "$COMMANDER_UPDATE_KEY_FILE" --notes .build/distribution/release-notes.md
python3 script/update_feed.py verify --archive .build/distribution/Commander4Mac-VERSION.dmg \
  --feed .build/distribution/appcast.xml
```

The verify command uses only the checked-in public key and CryptoKit. Signing keys never enter command arguments as values. Real-tool regression tests cover altered archives/feeds, wrong or absent keys, metadata and URL mismatches, and temporary credential cleanup.

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
