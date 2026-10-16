# Commander4Mac

A native macOS file manager with two independent panes. The local development build is installed at `/Applications/Commander4Mac Dev.app`.

## Local development build

Implemented: independent tabs and histories, locked and navigable pins, bookmarks and favorite routing, a shared staging shelf, list and icon views, System/Light/Dark appearance, independent text/icon sizing, and workspace restoration. Local operations include queued copy/move, explicit conflicts, cancellation, metadata preservation, rename, new folder, macOS Trash, safe rename/new-folder undo, file URL clipboard actions, Quick Look, and Open With.

The app is a signed development build. Native drag source/destination handlers are implemented, but end-to-end drag completion remains unverified. The XCTest UI runner stalls on this Mac. See [local acceptance](verification/local-release.md) for exact coverage and limitations. SFTP, SMB, and WebDAV connections are implemented, including staged folder copies between local and remote panes. Existing mounted volumes can be browsed through the local provider.

## Server connections

Use Connect or Command-K, choose a protocol, and open the saved connection in either pane. Saved secrets use Keychain. Restored remote tabs remain disconnected until explicitly opened from Connections.

- SFTP supports passwords or OpenSSH Ed25519 keys, with explicit host fingerprint verification.
- SMB connects directly to a share, with an optional domain, password or Guest access. It does not mount or unmount system shares.
- WebDAV uses HTTPS with system certificate validation. Enter the server, port, and base collection such as `/dav/team`. Authentication supports HTTP Basic/Digest or Anonymous. Redirects are refused; save the final endpoint. Plain HTTP is restricted to numeric loopback test servers.

Browse, filter, sort, rename, create folders, and copy regular files or directory trees between one local and one remote pane. Copies retain the source and support root-level Skip, Keep Both, and Cancel. A temporary tree is verified before one non-replacing root rename. Existing destination trees are never merged or replaced. Local-only operations keep their existing metadata-preserving engine.

Remote copies preserve contents and structure, without preserving permissions, timestamps, ACLs, extended attributes, or resource forks. Packages, symlinks, special files, and undownloaded placeholders are rejected before mutation. Transfers are bounded to 100,000 entries and 128 levels. Remote Move, Trash, replacement, and server-to-server copies remain unavailable. Interrupted remote artifacts are retained for explicit review; recovery records include a non-secret endpoint identity. Activity copies readable remote paths and reveals only local files in Finder.

The installed app and owned loopback fixtures have been exercised with OpenSSH SFTP, Impacket SMB2, and WsgiDAV. Real LAN/NAS/public-server interoperability still needs acceptance on those environments. SFTP password authentication and encrypted keys also remain unverified here. See [network and folder acceptance](verification/network-folders-release.md), [SFTP acceptance](verification/sftp-release.md), and [SFTP review](verification/sftp-final-review.md).

## Build and run

Requirements: macOS 15 or later, Xcode with Swift 6, XcodeGen, and an available signing identity. Tested here with Xcode 27.0 on macOS 27.0.1, Apple M4. The checked-in signing team is this development Mac's team; change `project.yml` when building on another machine.

```sh
./script/build_and_run.sh
./script/build_and_run.sh --verify
```

The script generates the Xcode project, builds and signs Debug, installs only the development identity at its stable path, and launches that installed app. It refuses relaunch when a matching live process reports active operations. Codex's Run action uses the same script. Release and UI-test hosts have separate bundle identifiers.

Enable that exact installed development app in **System Settings → Privacy & Security → Full Disk Access**, then restart if macOS requests it. Acknowledging the setup screen is separate from granting permission. Actual protected-location browsing has been verified in the installed app. Individual file permissions still apply.

## Verify

```sh
./script/test.sh
./script/test.sh LocalOperationExecutorTests
./script/test_sftp.sh
./script/test_smb.sh
./script/test_webdav.sh
COMMANDER_TEST_KEYCHAIN=1 ./script/test.sh KeychainIntegrationTests
./script/test_cross_volume.sh
COMMANDER_PERFORMANCE=1 ./script/test.sh LocalPerformanceTests
./script/test.sh --ui
```

SMB/WebDAV fixture scripts use an isolated `.build/network-fixture-venv` with Impacket 0.13.1, WsgiDAV 4.3.4, and Cheroot 11.1.2 from PyPI. Fixtures bind only to loopback and use disposable credentials/data.

Core tests default to Debug with dependency assertions enabled and run real XCTest assertions directly after `build-for-testing`, avoiding this Mac's stalled UI automation service. Cross-volume integration creates and detaches its own disposable APFS image. Performance tests create their own 10,000-entry fixture. UI execution has a 180-second deadline and never treats a timeout as a pass. Logs are under `.build/logs`.

## Keyboard

| Action | Shortcut |
|---|---|
| Open selected / rename / Quick Look | Command-O / Return / Space |
| Switch pane | Tab |
| Copy / move to other pane / new folder | F5 / F6 / F7 |
| New folder | Shift-Command-N |
| Copy file URLs / paste copy / paste move | Command-C / Command-V / Option-Command-V |
| Trash | Command-Delete |
| Path / filter | Command-L / Command-F |
| New tab / close tab / new window | Command-T / Command-W / Command-N |
| Parent / back / forward | Command-Up / Command-[ / Command-] |
| Connect to server | Command-K |
| Stage selected items | Shift-Command-S |

Text fields keep standard editing behavior. Hardware function-key settings can affect F5 through F7; all operations also have menu or button actions. Dropping on the shelf is intended to collect references only. File-list drops advertise copy by default and move with Command when the source permits it.

## Architecture and evidence

`CommanderCore` owns provider listings, pane/tab state, bookmarks, persistence, transfer planning, a serial mutation gate, execution, and journals. The app supplies SwiftUI scenes, reusable AppKit table/collection views, menus, previews, and system integration. SFTP sessions are actor-owned with strict host-key validation. The [Citadel 0.12.1 snapshot](../Vendor/Citadel/COMMANDER_PATCHES.md) supplies bounded READDIR, no-follow LSTAT, and packet limits. SMB serializes libsmb2 on bounded workers; WebDAV uses ephemeral URLSession authentication and bounded private disk spools. Network file channels use 64 KiB blocks. AMSMB2/libsmb2 revisions are pinned; see ThirdPartyNotices.txt. The production workflow bundles LGPL corresponding source, license notices and tested rebuild/replacement instructions; see the dependency licensing review. Credentials are kept in Keychain or memory. No privileged helper, recursive folder-size scanning, or eager thumbnails are used.

- [Approved design](superpowers/specs/2026-10-16-commander4mac-design.md)
- [Implementation plan](superpowers/plans/2026-10-16-local-file-manager.md)
- [Acceptance record](verification/local-release.md)
- [SFTP plan](superpowers/plans/2026-10-16-sftp-connections.md)
- [Network and folder acceptance](verification/network-folders-release.md)
- [Network final review and decisions](verification/network-folders-final-review.md)
- [SFTP acceptance](verification/sftp-release.md)
- [Performance measurements](verification/local-performance.md)

## Icon and installer

The selected blue/teal folded-pane icon is included in the app, with its PNG source, ten-size iconset, and `.icns` export. See [icon design and format guide](../Design/AppIcon/README.md).

A signed local drag-to-Applications DMG can be built with `./script/build_dmg.sh`. It includes Retina background artwork, the Applications shortcut, and first-launch installation guidance before Full Disk Access setup. See [installer design and build instructions](../Packaging/README.md). Production distribution uses the separate release and notarization workflow documented there.

See [reliability, icon and installer acceptance](verification/reliability-icon-installer.md) for the latest test and installed-app evidence.

This product includes software developed by Niels Provos.

See [release and notarization instructions](../Packaging/DISTRIBUTION.md) and the [dependency license review](verification/dependency-licensing.md).

- [Commander4Mac 1.0 notarized distribution acceptance](verification/distribution-release.md)

## Unsigned CI builds

`COMMANDER_CI=1 ./script/test.sh` runs core tests with signing disabled, so contributors do not need the distribution certificate. `./script/ci.sh` runs the complete hosted-check sequence. The installed development app is never replaced by these checks.

## Local Network troubleshooting

Inspect the running executable path and installed app's logs when a connection reports `Local network prohibited`; a generic URLSession `-1009` can have that cause. A successful curl request does not prove the app has permission. Check for development copies and use the entry matching the exact installed app. Toggle its existing Local Network permission off/on, restart and verify an authenticated connection with real content. Do not reset the network privacy database or unrelated permissions.

See [Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy). Manual clean-machine installation and UI test execution remain distinct from hosted core/integration checks.
