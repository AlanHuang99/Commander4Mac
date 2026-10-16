# Production distribution

As of October 16, 2026. The release identity is `com.alanhuang.Commander4Mac`, version 1.0 build 1, signed by team `66LBY954DT`. The development app remains separate. Both arm64 and x86_64 slices are built; Intel hardware execution is not implied by archive validation.

## Build and validate

```sh
./script/build_release.sh
```

This prepares licenses and exact LGPL sources, generates the project, archives Release into `.build/distribution/Commander4Mac.xcarchive`, and validates the actual app. Verification requires production identity/version, secure timestamps, every required architecture and UUID, Developer ID nested signatures, hardened runtime, no debug or library-validation exceptions, complete license/source resources and dynamic SMB linkage. Do not replace the development installation to produce a release.

## Apple credentials

Create a profile interactively in your own Terminal, never by pasting passwords into chat, source, arguments or logs:

```sh
xcrun notarytool store-credentials Commander4Mac-notary --team-id 66LBY954DT
```

The tool prompts for your developer Apple ID and app-specific password. An existing App Store Connect API-key profile can also be passed as the second script argument. This workflow reads an existing profile; it does not export credentials or write them to the repository.

## Notarize the app and DMG

```sh
./script/notarize.sh app-submit
./script/notarize.sh app-finish
./script/notarize.sh dmg-submit
./script/notarize.sh dmg-finish
```

Run each finish action after Apple's processing completes; it safely refuses unfinished or rejected submissions. Accepted submissions still require a clean notary log. Rejected terminal submissions retain their downloaded log for diagnosis. Submission IDs, logs and upload hashes are saved under `.build/distribution/notarization`. A pending upload file represents an uncertain outcome and prevents blind resubmission. Inspect its ID/status before retrying.

The app ZIP is submitted first. Its signing hash is checked before stapling. After the app has a valid ticket, the final DMG is built from that exact app, signed and submitted. The last step staples the image, checks the container signature and checksum, mounts read-only, verifies the inner app's ticket and signatures, and runs Gatekeeper and `syspolicy_check distribution` on the actual mounted app. The final output is `.build/distribution/Commander4Mac-1.0.dmg` with its `.sha256` file. Only the fully validated final image is a distribution candidate.

Do not rebuild the archive while a submission is in progress. Do not change the app or DMG after validation. Use new version/build metadata and a separate saved submission record for future releases; never reuse an old submission ID for changed bytes.

## Source and attribution

The signed app carries `Contents/Resources/OpenSource` with corresponding LGPL source, exact revisions and per-file hashes, licenses and tested rebuild/replacement scripts. It is accessible from Open Source Components in the app menu. Its About panel, installation artwork and this repository retain the acknowledgement: This product includes software developed by Niels Provos. Retain it in advertising mentioning features or use of the included software. Do not add terms restricting personal modification or reverse engineering for LGPL debugging.

The production app keeps hardened runtime and library validation. Replacing a library in a personal copy requires re-signing that copy; the supplied scripts never change the distributed original or system policy. Third-party licenses remain authoritative. See the [engineering license review](../docs/verification/dependency-licensing.md).

## References

Apple: [notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [custom workflows](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow), [packaging](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution). GNU: [LGPL 2.1](https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html).
