# Appearance, saved connections and automatic updates

As of October 17, 2026. Release target: Commander4Mac 1.1/build 2, production identity `com.alanhuang.Commander4Mac`, team `66LBY954DT`. This record distinguishes executed checks from remaining manual acceptance.

## Implemented behavior

- File font families and 10–28 pt text, 12–40 pt list icons and 32–160 pt grid icons. Navigation has an independent font, 10–24 pt text, 12–28 pt icons and 180–320 pt sidebar width.
- Appearance sharing defaults on for existing/future tabs, panes and windows. Opt-out keeps pane edits with that tab through folder changes and restoration. Sort/filter/view-mode/pin/navigation state remain independent. App defaults style the sidebar.
- System, Ocean, Forest, Sand and Plum themes, with light/dark/system appearance. Theme palettes have executable selected/secondary/primary text contrast checks.
- Cmd-K saved-profile chooser, Save Connection without network activity, Save and Connect, and sidebar endpoint details. Profile selection preserves custom endpoints and clears transient credentials. Transactional profile/Keychain stores remain authoritative.
- Sparkle 2.10.0, exact commit `eef1a539a373c1f1a320624b1130fc5de7b2e100`, a separate Commander4Mac Ed25519 key and GitHub Releases appcast. Automatic checks default on; background downloads are opt-in. Dev/UI-test identities cannot start the production updater.
- Update relaunch waits for active and pending file operations, pauses new mutation admission during the final save, and proceeds only after successful workspace persistence. A save failure keeps the app open with retry UI.

## Executed checks

- Full local `script/ci.sh`: 181 core tests, 20 opt-in skips, zero failures; each owned SMB/WebDAV/SFTP/cross-volume fixture passes; 23 Python publication/signature tests pass normally and with optimized Python; unsigned universal app build passes. Hosted architecture checks are recorded separately after publication.
- Five real coordinator tests cover waiting/drain/save ordering, duplicate install callbacks, cancellation during a save, late activity, and failed-save retry.
- Real official `sign_update` signatures cross-verify with CryptoKit. Tests reject altered archives and feeds, unsigned trailing XML, wrong/missing keys, bad version/build/minimum OS/length/URL, and verify restricted temporary-key creation/removal.
- A separately identified disposable app was actually upgraded by pinned upstream `sparkle-cli`: invalid signed XML rejected with Sparkle error 1000; valid probe exit 0; install exit 0; version 1 became 2 and the installed executable printed the build 2 marker. Deep signature verification passed. User Applications were never a target. This fixture was not notarized; it exercises the actual updater path while production notarization is a separate gate.
- Developer ID archive/export passed production verification for 9 universal Mach-O files, secure timestamps, unchanged signing team, hardened runtime, complete licenses and dynamic LGPL linkage. Xcode export re-signs Sparkle helpers. A local DMG preview passed the mounted-app/layout/Applications-link checks; its generated signed appcast cross-verified against exact 15,737,036-byte preview bytes. This preview is not a published/notarized release.
- `actionlint`, shell syntax checks and source-history Gitleaks pass. The sole public verification key has an exact-value allowlist; all default secret rules remain enabled. Private keys never enter Git or release assets.

## Native UI evidence and limits

The isolated UITest host used only owned demonstration files and state. Native interaction confirmed shared 19 pt file text, Rounded font, 18 pt navigation text and 24 pt navigation icons in both panes and the sidebar. The saved preferences document retained these values. The options popover keeps a stable control font as navigation grows.

UI regressions for sharing/new tabs, opt-out/relaunch and saved-profile save/relaunch/load/remove compile. The XCTest service timed out enabling automation before executing tests. Later the Computer Use native bridge repeatedly closed its pipe, including after a REPL reset; the host stayed running with no crash report. Extreme-size, theme-selection, multiple-window and full saved-connection UI acceptance remain unexercised. No permission database was reset, and no UI-suite pass is claimed. Core regressions cover persisted appearance routing and saved-profile transitions, but do not prove every visual layout.

## Independent review and correction

One fresh whole-change review of `2ed315e..138ffb0` found no Critical issues, two Important defects and one Minor. Both Important findings were reproduced before correction and fixed in one pass:

- An exact native table probe reproduced the missing spacing: a 380 pt viewport with 28 pt text/40 pt icons had a 585.538 pt document while its last column extended to 609.5 pt. The layout now reserves gaps and uses AppKit's actual visible column extents. The production scroll class passes 48 size/hidden-column configurations, including maximum horizontal reachability.
- The actual AppDelegate silently canceled Quit after a failed save. With injected native presentation boundaries, its old body reproduced the missing error. It now presents the storage error immediately, keeps the app/connections open, and explains how to retry. Offscreen tests execute ordinary Quit, pending updater termination using the real coordinator, quitting after canceled operations, and a successful retry after storage recovers.

Deferred Minor: sidebar hover help omits share/start-folder details when endpoint labels truncate. Full endpoint information remains in accessible labels and the Cmd-K chooser; profile identities remain distinct. This hover refinement was not changed in the review correction pass.

The reviewer declined to certify complete installed-app visual acceptance, an actual installed-production update with retained permissions, and every clean-machine/OS/architecture combination. Those remain qualified below rather than being represented as tested.

## Publication and installed-app verification

The first hosted run for `7979389` passed tests and protocol fixtures, then failed the final app build under Xcode 26.3. The compiler could not type-check the large `PaneView` and `SavedConnectionRow` expressions in time. Splitting their existing content into smaller typed view properties preserves the controls, bindings and actions. The resulting unsigned universal build passes locally with Xcode 27. Hosted Xcode 26.3 checks remain required before a release tag.

The development app built from `7979389` is installed and running at `/Applications/Commander4Mac Dev.app`, with version 1.1/build 2 and a valid deep signature. Its existing connection catalog and nonvisual session preferences were preserved, with an owner-only local backup. Onscreen acceptance remains qualified above.

Pending hosted CI/release and public artifact verification. Version 1.0 needs one manual 1.1 DMG installation to gain the updater. Clean-machine permissions/onboarding remain a separate manual acceptance check.
