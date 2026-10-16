# Commander4Mac

A native macOS file manager with two independent panes. The local development build is installed at `/Applications/Commander4Mac Dev.app`.

## Local development build

Implemented: independent tabs and histories, locked and navigable pins, bookmarks and favorite routing, a shared staging shelf, list and icon views, System/Light/Dark appearance, independent text/icon sizing, and workspace restoration. Local operations include queued copy/move, explicit conflicts, cancellation, metadata preservation, rename, new folder, macOS Trash, safe rename/new-folder undo, file URL clipboard actions, Quick Look, and Open With.

The app is a signed development build. Native drag source/destination handlers are implemented, but end-to-end drag completion remains unverified. The XCTest UI runner stalls on this Mac. See [local acceptance](docs/verification/local-release.md) for exact coverage and limitations. SFTP connection management is now implemented. SMB connection management and WebDAV remain later milestones. Existing mounted volumes can be browsed through the local provider.

## SFTP

Use the Connect toolbar button or Command-K. Save a server with password authentication or an OpenSSH Ed25519 key, verify its SHA256 host fingerprint through a trusted channel, and open it in either pane. Saved secrets use Keychain. Restored remote tabs remain disconnected until explicitly opened from Connections.

Browse, filter, sort, rename, create folders, and copy individual regular files between local and remote panes. Copies retain the source and support Skip, Keep Both, and Cancel. They copy file contents without preserving permissions, timestamps, extended attributes, or resource forks. Remote folder transfers, Move, Trash, replacement, and server-to-server copies are not available yet.

The installed app has been exercised against an owned loopback OpenSSH server. Password authentication, encrypted keys, and real LAN/public-server interoperability still need acceptance on those environments. See [SFTP acceptance](docs/verification/sftp-release.md).

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
COMMANDER_TEST_KEYCHAIN=1 ./script/test.sh KeychainIntegrationTests
./script/test_cross_volume.sh
COMMANDER_PERFORMANCE=1 ./script/test.sh LocalPerformanceTests
./script/test.sh --ui
```

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
| Connect to SFTP | Command-K |
| Stage selected items | Shift-Command-S |

Text fields keep standard editing behavior. Hardware function-key settings can affect F5 through F7; all operations also have menu or button actions. Dropping on the shelf is intended to collect references only. File-list drops advertise copy by default and move with Command when the source permits it.

## Architecture and evidence

`CommanderCore` owns provider listings, pane/tab state, bookmarks, persistence, transfer planning, a serial mutation gate, execution, and journals. The app supplies SwiftUI scenes, reusable AppKit table/collection views, menus, previews, and system integration. SFTP sessions are actor-owned, with strict host-key validation and bounded streaming. Credentials are kept in Keychain or memory. No privileged helper, recursive folder-size scanning, or eager thumbnails are used.

- [Approved design](docs/superpowers/specs/2026-10-16-commander4mac-design.md)
- [Implementation plan](docs/superpowers/plans/2026-10-16-local-file-manager.md)
- [Acceptance record](docs/verification/local-release.md)
- [SFTP plan](docs/superpowers/plans/2026-10-16-sftp-connections.md)
- [SFTP acceptance](docs/verification/sftp-release.md)
- [Performance measurements](docs/verification/local-performance.md)
