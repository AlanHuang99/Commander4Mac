# Reliability, icon and installer acceptance

As of October 16, 2026. Branch `codex/local-file-manager`, phase base `2d09bf2`. This phase resolves the three deferred minors in [the network review](network-folders-final-review.md), repairs native command routing, and implements the user-selected icon and a signed local DMG preview.

## Reliability changes

- SMB synchronous transport failures are classified from the pinned libsmb2 diagnostics instead of interpreting a bare `-1` as permission denied. Genuine server EPERM remains an access error and preserves a usable session. Dropped transports retire immediately. Failed opens and channel operations also reconcile the unified sidebar without requiring another listing. Owned server tests reproduced the incorrect classification and stale sidebar before the corrections. Temporarily removing the channel wrapper reproduced the stale connected state on a failed read; the wrapper was restored before the final suite.
- Apply to all decisions span every regular-file and folder root in one remote batch. Mixed file/folder/file regressions exercised both Skip and Keep Both, verified preserved originals and copied children, and reduced three prompts to one.
- Router outcomes belong to a generation, so an old attempt cannot overwrite a newer successful connection or an explicit disconnect. A fresh read-only review found one additional P2: a peer could close during setup while connect still returned success. The new regression first reproduced that outcome, then passed after completion reconciled transport liveness. SFTP disconnect observations arriving during a pending attempt are retained and reconciled before success. Generation guards remain across every actor hop. The existing old-failure regressions also pass.

Relevant ignored logs: `smb-classification-red.log`, `smb-classification-green.log`, `smb-sidebar-red.log`, `smb-sidebar-green.log`, `channel-status-red.log`, `mixed-batch-red-final.log`, `mixed-batch-green.log`, `review-connect-red.log`, and `review-connect-green.log`, all under `.build/logs`.

## Cmd-K and menus

Native testing reproduced a sheet-dismissal failure: controller-dependent File menu items remained disabled in an active key workspace. Cmd-K now routes using the actual event window, and an observable command target follows native key-window, modal, and application update state. Target updates publish only when controller identity changes. Settings and modal windows do not route commands into another file window.

Native acceptance covered repeated connect-sheet open/dismiss cycles, a focused path field, Settings and return, native Open panel cancellation, and another file window followed by return to the original. Cmd-Shift-G and menu enablement recovered after sheet dismissal. A corresponding XCTest UI regression is included; automated UI execution remains unverified on this Mac.

## Icon and installation

The user chose B: a midnight tile with folded cobalt and teal panes. [The icon guide](../../Design/AppIcon/README.md) records the visual concept, Apple references, source PNG, complete ten-file iconset size table, `.icns` generation, and appearance limitations. All ten PNG dimensions and an `iconutil` round-trip were checked. The icon is integrated through `CFBundleIconFile` in the signed bundle.

[The packaging guide](../../Packaging/README.md) records the 720 × 480 layout, 112-point native app and Applications icons, shortcut positions, Retina artwork, instructions, and reproducible build. All essential artwork avoids the bottom area where this Mac’s Finder retains its path bar. The package contains a real `/Applications` symlink and Finder layout data.

Opening the mounted copy shows install guidance before file services initialize. The screen explains moving the app into Applications before Full Disk Access setup and provides reveal, Applications, and quit actions. An actual mounted launch and quit left all 47 existing files under the development app’s Application Support directory byte-identical. The installed copy is the permission target; setup acknowledgement alone never claims access.

Packaging initially caught an invalid inner app signature: hiding the app extension added FinderInfo to the signed bundle. That option was removed. The build now checks the actual mounted app with deep strict verification and compares its CDHash with the source before publishing the image. It separately signs and checks the DMG and verifies image checksums. Logs: `dmg-inner-red.log` and `dmg-build-green.log`.

## Automated verification

All results use the final source after the review fix. Core and protocol tests run in Debug with dependency assertions enabled; the UI bundle uses its separate UITest identity. Protocol runs use owned loopback servers and disposable content.

| Run | Result | Log under `.build/logs` |
| --- | --- | --- |
| Full core suite | 160 tests, 20 environment-gated skips, zero failures | `reliability-final-core.log` |
| Real OpenSSH/SFTP fixture | 6/6, zero failures | `reliability-final-sftp.log` |
| Real SMB2 fixture | 8/8, zero failures | `reliability-final-smb.log` |
| WebDAV fixture | 6/6, zero failures | `reliability-final-webdav.log` |
| UI bundle compilation | TEST BUILD SUCCEEDED, execution unverified | `reliability-final-ui-build.log` |
| Router review regression | 3/3, zero failures after runtime RED | `review-connect-green.log` |

## Final installed and mounted acceptance

The final build again opened and reopened the connection editor using native Cmd-K. A disposable workspace window listed `~/Library/Mail`, including V10 and PersistenceInfo.plist, without opening message contents. That window was closed and the prior Home/Downloads workspace returned. The final mounted DMG displayed the intended icon spacing, readable instructions, and visible minimum-system label. Its launch screen exposed distinct identifiers for all three controls; Quit This Copy terminated the exact volume copy. The final launch/quit comparison again preserved all 47 app-state files byte-for-byte. The owned Finder window was closed, the exact test volume ejected, and the canonical installed app reopened.

Installed identity: `com.alanhuang.Commander4Mac.dev`, team `66LBY954DT`, Developer ID signed with hardened runtime. Deep strict verification passed. Main arm64 UUID `1BFAF630-68F1-3236-8C91-C0764A396F08`; CommanderCore arm64 UUID `4397695F-4282-3B01-B8F1-6511B62C2255`. App debug-library arm64 UUID `0682D2CB-1BFC-3F42-A597-7614F618EF24`. The main launcher UUID is unchanged; changed runtime code has the framework/debug-library identities. Final observed PID: 2579, executable `/Applications/Commander4Mac Dev.app/Contents/MacOS/Commander4MacDev`. This local package is arm64; no universal-build acceptance is claimed.

Final DMG: `.build/distribution/Commander4Mac-Dev.dmg`, SHA-256 `94b63c7e007cab20a94e0404b5e15a8a0b2b4fa898f265dbbec3dc7bb9da467b`. The inner source CDHash matched, the outer signature verified, and `hdiutil verify` reported a valid checksum. Log: `dmg-build-green.log`. Owned protocol servers and command-routing log capture were stopped; no test volume remains mounted.

## Limits

This is a signed local development preview. External distribution still requires notarization/stapling and dependency licensing/relinking review. No Icon Composer agreement was accepted; delivery uses a classic flattened `.icns`, without claiming adaptive layered appearances. UI automation execution, broad NAS/Windows Server interoperability, LAN permission grants, and native drag-copy completion are not inferred from fixture tests or UI compilation. No privacy database, unrelated grant, user credential, or user document contents were changed for diagnostics.
