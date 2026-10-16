# Local File Manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a signed, directly installed local file manager with Full Disk Access setup, two independent tabbed panes, favorites, a staging shelf, and dependable local file operations before adding remote connections.

**Architecture:** SwiftUI owns scenes, settings, and composition; bounded AppKit components own file tables, selection, dragging, and Quick Look. A UI-independent core owns locations, browsing sessions, persistence, planning, and queued operations. Blocking filesystem work uses dedicated workers rather than the main actor.

**Tech Stack:** Swift, SwiftUI, AppKit, Foundation, Darwin filesystem APIs, XCTest, XcodeGen, and the Build macOS Apps plugin workflow. No third-party runtime dependencies for this release.

**Spec:** [Approved design](../specs/2026-10-16-commander4mac-design.md), updated with the user's October 16 requirement for Full Disk Access and local-first delivery.

## Global Constraints

- Use direct installation and a non-App-Sandbox build for the initial release, with macOS 15 or later as the deployment target.
- Full Disk Access is required for the intended complete local browsing workflow. Address it early in setup rather than adding repeated folder-selection workarounds.
- Implement the local workspace and file operations before adding remote connections.
- Appearance: System, Light, Dark. Apply the chosen mode to all app-controlled browsing surfaces.
- Text size: independent list text control, proposed default 13 points and range 11 through 20.
- List icon size: independent control, proposed default 20 points and range 16 through 32. Row height accommodates both text and icons.
- Default to one active transfer job initially, with subsequent jobs queued. Browsing remains available.
- Conflicts offer Skip, Keep Both, Replace, and Cancel. Apply-to-all is scoped to the current job. No silent overwrite.
- Trash failures stay failures. Never fall back to permanent deletion without an explicit, separate user action.
- Do not modify TCC databases or disable platform protections.
- Use the Build macOS Apps plugin. Follow the user's shared Local Network and signing lessons.
- Every implemented core action has a menu or context-menu entry and a pointer-accessible control where appropriate. No fake remote connection controls or placeholder file listings.

## Review Focus

1. Destination appears or changes after conflict checking: keep the existing item unless replacement was explicitly chosen; never silently overwrite. Task 8 owns the race tests.
2. Two names refer to the same inode, or names differ by case/Unicode normalization: preserve distinct directory entries and obey the filesystem's actual naming rules. Tasks 2, 7, and 10 own the tests.
3. Source changes, destination disappears, or cancellation arrives during a move: retain the source unless the copy has been finalized and completion checks succeed. Task 8 owns the failure-injection tests.
4. A path is denied, a volume is missing, or a cloud file is only a placeholder: show the actual state; never report an empty successful folder or download content merely to list it. Tasks 1, 2, and 5 own the tests.
5. Focus moves to a text field, sidebar, another tab, or another window: keyboard commands operate on the intended session and captured destination. Tasks 3, 4, and 11 own the tests.

## Scope and development decisions

This plan implements design milestones A and B together as the first usable release. SFTP, integrated SMB connection management, and WebDAV get separate plans after local release acceptance. Existing mounted volumes remain ordinary browseable filesystem locations.

Use XcodeGen's installed version to generate `Commander4Mac.xcodeproj` from `project.yml`. Commit the spec and generated project. Use one app scheme, `Commander4Mac`, with Debug, Release, and UITest configurations; a `CommanderCore` framework; unhosted `CommanderCoreTests`; and `Commander4MacUITests`. The UITest configuration has a separate app identity so XCTest does not launch another copy of the development identity. All declarations consumed across the app/core boundary are public. Use strict concurrency checks and make values crossing workers Sendable.

| Configuration | Bundle identifier | Product/executable | Canonical test installation |
| --- | --- | --- | --- |
| Debug | `com.alanhuang.Commander4Mac.dev` | `Commander4MacDev` | `/Applications/Commander4Mac Dev.app` |
| Release | `com.alanhuang.Commander4Mac` | `Commander4Mac` | `/Applications/Commander4Mac.app` |
| UITest | `com.alanhuang.Commander4Mac.uitest` | `Commander4MacUITestHost` | Isolated build product launched by XCTest |

Keep one selected Developer ID Application identity stable for signing. Select it from local Keychain discovery without copying certificates or storing private key data. Do not publish, notarize, or replace a production installation as part of this development plan. Confirm an existing development bundle's identifier before updating it. Build into `.build/xcode`, install the development app at its canonical path, and launch that exact bundle for permission verification.

As of October 16, 2026, XcodeGen 2.45.4 and a valid Developer ID Application identity are available. `xcrun --find swift` still reports unaccepted Xcode license agreements. The user must review and accept those agreements before compilation. Complete available source work if that prerequisite remains pending, but never mark build or app verification passed.

Full Disk Access setup is explicit, short, and early: show the app's installed name/path, explain where to enable it, and provide Retry and Restart actions. Acknowledgement is user-reported setup state, not a global OS authorization result. Read the folder the user actually requests and handle its real errors. Do not probe private databases, use private TCC APIs, or claim one readable path proves universal access. Apple documents user-controlled granting and recommends checking real operations. [Apple file-access guidance](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox?language=objc), [Apple DTS](https://developer.apple.com/forums/thread/114452).

## File map

Paths are relative to the checkout selected for implementation. Create only the files needed by each task.

| Area | Files and responsibility |
| --- | --- |
| Build/configuration | `project.yml`, `Commander4Mac.xcodeproj/`, `Configuration/Info.plist`, `Configuration/Commander4Mac.entitlements`, `.gitignore`, `script/build_and_run.sh`, `script/test.sh`, `.codex/environments/environment.toml` |
| App entry and commands | `Sources/Commander4Mac/App/Commander4MacApp.swift`, `AppServices.swift`, `AppCommands.swift`, `AppDelegate.swift` |
| Main UI | `Sources/Commander4Mac/Views/WorkspaceView.swift`, `PaneView.swift`, `TabStripView.swift`, `LocationBarView.swift`, `SidebarView.swift`, `ShelfView.swift`, `ActivityView.swift`, `ConflictSheet.swift`, `SettingsView.swift`, `AccessSetupView.swift` |
| Native bridges | `Sources/Commander4Mac/Views/FileTable/` with `FileTableView.swift`, `FileTableCoordinator.swift`, `FileTableCommandHandler.swift`; `Views/FileGridView.swift`; `Support/QuickLookController.swift`, `SystemFileActions.swift`, `FilePasteboard.swift` |
| Core models | `Sources/CommanderCore/Models/` with `FileLocation.swift`, `FileEntry.swift`, `FileFailure.swift`, `ViewOptions.swift`, `LocationReference.swift`, `TransferModels.swift`, `OperationModels.swift` |
| Core state | `Sources/CommanderCore/Stores/` with `TabSession.swift`, `PaneSession.swift`, `WorkspaceSession.swift`, `ApplicationStateStore.swift`, `FavoriteStore.swift`, `ShelfStore.swift`, `PreferencesStore.swift` |
| Core services | `Sources/CommanderCore/Services/` with `LocalFileSystem.swift`, `DirectoryLoader.swift`, `DirectoryWatcher.swift`, `LocationResolver.swift`, `LocalTransferPlanner.swift`, `LocalCopyEngine.swift`, `LocalOperationExecutor.swift`, `TransferQueue.swift`, `OperationJournal.swift`, `LocalFileActions.swift` |
| Shared support | `Sources/CommanderCore/Support/BlockingFileWorker.swift`, `OperationCancellation.swift`, `AtomicFileWriter.swift`, `FileNameRules.swift`; app `Support/RuntimeIdentity.swift`, `PermissionGuidance.swift`, `ActiveOperationMarker.swift` |
| Tests | `Tests/CommanderCoreTests/`, `Tests/Commander4MacUITests/`, `Tests/Support/FixtureDirectory.swift`, `ControlledDirectoryProvider.swift`, `FaultInjectingFileOperations.swift` |
| Acceptance evidence | `docs/verification/local-release.md`, `docs/verification/local-performance.md` |

## Verification commands

Task 1 creates `script/test.sh`. With no arguments it runs the core tests; with a final class name it limits the run to `CommanderCoreTests/<ClassName>`. `--ui` selects the UI test bundle and an optional class name limits that bundle. It uses the same scheme, build directory, and macOS destination as the Run script, selects the UITest configuration for the test host, and returns xcodebuild's exit status. UI tests use only disposable fixture locations and never serve as Full Disk Access acceptance for the installed development app. Do not suppress failures or infer success from truncated logs.

Define shared value types in the owning task before consumers use them: Task 2 defines `ListingOptions(includeHidden: Bool)`, `FileKind` (directory/file/package/symbolicLink), and `PlaceholderState` (local/notDownloaded/unknown). Task 3 defines `PaneID` (left/right), `NavigationTicket` (tabID/generation/location), `NavigationTarget` (paneID/tabID/ticket with a computed location), and `ScrollAnchor` (entryID/offset). Task 7 defines `ItemVersion` (identity/size/modificationTime), `CopyProgress` (bytesCopied/completedItems), `JournalRecord` (jobID/itemID/source/staging/destination/expectedIdentities/phase), `OperationEvent`, and `JobSnapshot` (request/state/progress/outcomes/pendingConflict). Task 10 defines `LocalMutation` (kind/before/after/expectedIdentity). Values used in persistence are Codable; worker-bound values are Sendable. Do not persist callback closures or framework error objects.

All functional tasks follow the red/green cycle below. Build configuration and visual styling use build and native inspection instead of artificial tests that duplicate configuration constants. Commit after each independently verified task.

---

### Task 1: Signed app, repeatable Run, and Full Disk Access setup

**Files:** Create the build/configuration area, app entry/delegate/services, `Views/AccessSetupView.swift`, `Support/RuntimeIdentity.swift`, `Support/PermissionGuidance.swift`, and the test-target directories.

**Interfaces:** Produces `RuntimeIdentity.current() -> RuntimeIdentity` with bundle identifier, executable URL, installed bundle URL, and executable UUID; `PermissionGuidance.message(for error: NSError, path: URL) -> String?`; and a scene-local setup acknowledgement. No global `isFullDiskAccessGranted` flag.

- [ ] **Step 1: Verify prerequisites and initial failure.** Read `build-run-debug/references/run-button-bootstrap.md`. Recheck Git/worktree state using the using-git-worktrees skill at execution time. Confirm the missing Xcode project prevents a build; stop short of accepting Apple's license on the user's behalf.
- [ ] **Step 2: Create the app and test targets.** Generate the project with XcodeGen. Set deployment target 15.0, `ENABLE_APP_SANDBOX=NO`, hardened runtime enabled, and the identities above. Set the Debug display name to Commander4Mac Dev and the scheme's test configuration to UITest. Add explanatory Files & Folders usage descriptions for Desktop, Documents, Downloads, removable volumes, and network volumes. Do not add imaginary Full Disk Access entitlements.
- [ ] **Step 3: Implement the Run contract.** `./script/build_and_run.sh` stops the idle development instance, builds, verifies its signature, installs to the canonical development path, and launches with `/usr/bin/open`. Keep the plugin's `--debug`, `--logs`, `--telemetry`, and `--verify` modes. Refuse relaunch while the live development process reports an active operation. Add the Run action only after the script exists. Give `script/test.sh` the contract above.
- [ ] **Step 4: Implement concise access setup.** Show the installed identity, Full Disk Access instructions, and Retry/Restart. Open System Settings using a supported application-open action; give a visible navigation path if opening the exact panel is unavailable. Never change permissions programmatically. Keep denied path errors contextual: distinguish filesystem access denial from possible privacy/system protection and do not present all EACCES/EPERM errors as proven missing Full Disk Access.
- [ ] **Step 5: Verify and commit.** Run `xcodegen generate`, `./script/build_and_run.sh --verify`, inspect the installed app's native window, and inspect `codesign -dvvv --entitlements :- '/Applications/Commander4Mac Dev.app'`. Confirm the selected identity and absence of App Sandbox. Record the manual Full Disk Access grant as pending until the user completes it. Commit `build: bootstrap signed native app and access setup`.

### Task 2: Real directory listings and filesystem identity

**Files:** Create core `FileLocation`, `FileEntry`, `FileFailure`, `LocalFileSystem`, `BlockingFileWorker`; test `LocalFileSystemTests.swift` and `Tests/Support/FixtureDirectory.swift`.

**Interfaces:** `FileLocation: Hashable, Codable, Sendable` starts with `.local(URL)` and exposes a computed local provider identifier; expand it only when remote providers are implemented. `EntryID` identifies the parent/name directory entry. `FileIdentity` contains device/inode from `lstat`. `FileEntry` contains id, location, name, kind, optional identity, byte size, modification date, and placeholder state. `DirectorySnapshot` contains location and entries. `DirectoryProviding: Sendable` defines `list(_ location: FileLocation, options: ListingOptions) async throws -> DirectorySnapshot`. `LocalFileSystem` implements it. `FileFailure` preserves category, domain/code, and attempted location without contents.

- [ ] **Step 1: Add failing fixture tests.** Create disposable roots with an owner marker; cleanup only those roots. Specify tests for directories, packages, broken symlinks, hidden items, two hard links, Unicode names, missing folders, injected EACCES/EPERM, and placeholder metadata. Core assertions include:

```swift
XCTAssertNotEqual(hardLinkA.id, hardLinkB.id)
XCTAssertEqual(hardLinkA.fileIdentity, hardLinkB.fileIdentity)
XCTAssertEqual(brokenLink.kind, .symbolicLink)
XCTAssertEqual(deniedFailure.category, .accessDenied)
```

- [ ] **Step 2: Run `./script/test.sh LocalFileSystemTests`.** Expect failure because listing and identity support do not exist yet.
- [ ] **Step 3: Implement shallow listing and error classification.** Fetch required URL metadata together, distinguish packages and links, and use dedicated bounded workers for blocking calls. Do not follow links during classification, compute recursive directory sizes, generate thumbnails, or open file content to render a row. A failed enumeration throws rather than returning `[]`.
- [ ] **Step 4: Rerun the focused tests.** Expect all cases to pass; use fault injection for permission failures when CI permissions differ. Verify actual denied-path behavior in the app later.
- [ ] **Step 5: Commit `feat: load real local directories and preserve item identity`.**

### Task 3: Independent panes, navigation, tabs, pins, and routing

**Files:** Create core `ViewOptions.swift`, `TabSession.swift`, `PaneSession.swift`, `WorkspaceSession.swift`; test `WorkspaceSessionTests.swift` and `ControlledDirectoryProvider.swift`.

**Interfaces:** Main-actor observable `WorkspaceSession` owns `left`, `right`, and `activePane: PaneID`. `open(_ location: FileLocation, destination: OpenDestination, inNewTab: Bool) -> NavigationTarget` returns pane/tab/location. `OpenDestination` has current/left/right. `TabPin` has none/locked(home:)/navigable(home:). `TabSession.requestNavigation(to:) -> NavigationTicket` advances its generation; `apply(_ snapshot: DirectorySnapshot, for: NavigationTicket) -> Bool` rejects stale responses. `goBack()` and `goForward()` return optional tickets. `returnToPinnedFolder(in: PaneID, tabID: UUID) -> NavigationTarget?` restores home. `ViewOptions` defines sort column/direction, folders-first, hidden files, visible columns, text/icon sizes, and list/icon mode.

- [ ] **Step 1: Write failing behavior tests.** Assert that navigating a locked pin creates an ordinary tab in the same pane while its home stays fixed; navigating a navigable pin preserves its home; returning home is explicit; switching away/back preserves the browsed location. Verify left routing while right is active, independent histories, last-tab closing, and stale-response rejection:

```swift
XCTAssertEqual(workspace.activePane, .left)
XCTAssertEqual(lockedTab.location, lockedHome)
XCTAssertFalse(tab.apply(oldSnapshot, for: oldTicket))
```

- [ ] **Step 2: Run `./script/test.sh WorkspaceSessionTests`; expect failures for the missing state transitions.**
- [ ] **Step 3: Implement the state transitions.** Preserve selection and scroll anchors per tab. Resolve destinations once, protect pinned tabs from ordinary close, support updating a pin's saved home explicitly, and seed first launch with Home/Downloads. Do not load files in the state constructors.
- [ ] **Step 4: Rerun tests and verify independence across two workspace instances.** Expect no shared focus, histories, or tab objects between windows.
- [ ] **Step 5: Commit `feat: add independent pane sessions tabs and both pin modes`.**

### Task 4: Native two-pane browsing, filtering, and directory updates

**Files:** Create `WorkspaceView`, `PaneView`, `TabStripView`, `LocationBarView`, the file-table bridge, `DirectoryLoader`, `DirectoryWatcher`; test `DirectoryLoaderTests.swift` and UI `BrowserInteractionTests.swift`.

**Interfaces:** `DirectoryLoader.load(target: NavigationTarget, options: ListingOptions) async` consumes Tasks 2/3 and applies only current tickets. `DirectoryWatcher.events(for: FileLocation) -> AsyncStream<Void>` coalesces invalidations and ends when no tab observes it. `FileTableView` receives snapshot, selected `Set<EntryID>`, scroll anchor, `ViewOptions`, and intent callbacks. `BrowserIntent` covers selection, activate, rename, navigate-parent, focus-other-pane, and context action.

- [ ] **Step 1: Add failing tests.** A controlled slow directory A finishing after directory B must not replace B. Refresh must keep each hard-link row distinct, preserve surviving selections, and use unique identity matches for external rename reconciliation. UI cases: clicking a pane sets focus; Tab from a file table switches panes; Tab while editing a path stays in field traversal; a denied listing shows its error.
- [ ] **Step 2: Run `./script/test.sh DirectoryLoaderTests` and `./script/test.sh --ui BrowserInteractionTests`; expect the absent loader/UI behaviors to fail.**
- [ ] **Step 3: Implement the composed window and table bridge.** Use reusable NSTableView rows and normal AppKit selection. Add column resize/sort, folders-first, type selection, editable breadcrumbs/path, name filter, and explicit loading/error/empty states. Refresh after coalesced filesystem invalidations and app focus. Defer icons with bounded caching. A canceled system call may finish on its worker, but its old result cannot update the tab.
- [ ] **Step 4: Rerun the focused checks and inspect the running app.** Browse real fixture folders in both panes, including long filenames and symlinks, and resize the window. Confirm filtering is current-directory only and keyboard focus is visible.
- [ ] **Step 5: Commit `feat: build native dual pane browser with live directory updates`.**

### Task 5: Persistent workspaces, favorites, and durable location references

**Files:** Create `LocationReference`, `LocationResolver`, `AtomicFileWriter`, `ApplicationStateStore`, `FavoriteStore`, `SidebarView`; tests `ApplicationStateStoreTests.swift` and `FavoriteStoreTests.swift`.

**Interfaces:** `LocationResolver.reference(for: FileLocation) throws -> LocationReference`; `resolve(_ reference: LocationReference) -> ResolvedLocation` returns available/unavailable/needsRelink. `LocationReference` stores bookmark data, display URL, and expected volume/item identity; display URL is not an automatic fallback for a missing item. Use ordinary non-security-scoped bookmarks for this non-sandboxed app. `SavedApplicationState` version 1 contains window snapshots, favorites, and `[StagedItem]`; define `StagedItem` here as id/reference/displayName without executing it yet. `ApplicationStateStore.loadRecovering() -> StateLoadResult`; `save(_ state: SavedApplicationState) throws`. `FavoriteStore.add(name: String, location: FileLocation, destination: OpenDestination?) throws`, `rename(id: UUID, to name: String)`, `move(id: UUID, to index: Int)`, and `remove(id: UUID)` operate on favorite UUIDs.

- [ ] **Step 1: Add failing round-trip and recovery tests.** Assert both panes, tab order, pin homes/current locations, options, selection anchors, and split ratio survive save/load. A corrupt file is preserved and returns a fresh workspace plus a diagnostic; failed writes keep the previous valid file. A missing volume remains unavailable. A stale bookmark is refreshed or surfaced for relinking, never silently replaced with another volume's same path.
- [ ] **Step 2: Run `./script/test.sh ApplicationStateStoreTests` and `./script/test.sh FavoriteStoreTests`; expect missing persistence behaviors to fail.**
- [ ] **Step 3: Implement atomic, versioned persistence and sidebar favorites.** Save under Application Support for the active bundle identity. Keep window ownership explicit. Debounce session saves and flush on normal quit. Expose add/reorder/rename/remove and per-favorite destination override; use Task 3 routing. List mounted volumes without mounting or disconnecting them.
- [ ] **Step 4: Rerun tests, then relaunch the installed app and inspect restored windows.** Verify missing favorites produce a useful action, and reopening a favorite into a locked pane creates an ordinary tab.
- [ ] **Step 5: Commit `feat: persist workspaces and add destination aware favorites`.**

### Task 6: Appearance, density, view defaults, and settings

**Files:** Create core `PreferencesStore.swift`, app `SettingsView.swift`; modify `ViewOptions`, app entry, pane views, and table bridge. Test `PreferencesStoreTests.swift`.

**Interfaces:** `AppearanceMode` is system/light/dark. `Preferences` contains appearance, default view options, restore-session flag, and default opening destination. `PreferencesStore.load() -> Preferences`; `save(_ preferences: Preferences) throws`. `ViewOptions.validated() -> ViewOptions` clamps persisted/imported values to approved ranges; global defaults seed only new tabs.

- [ ] **Step 1: Write failing tests for preference behavior.** Test corrupt/out-of-range data, the default current-pane destination, and independent text/icon values:

```swift
XCTAssertEqual(defaults.view.textSize, 13)
XCTAssertEqual(defaults.view.listIconSize, 20)
XCTAssertEqual(invalid.validated().textSize, 20)
XCTAssertEqual(invalid.validated().listIconSize, 16)
```

- [ ] **Step 2: Run `./script/test.sh PreferencesStoreTests`; expect missing validation and persistence to fail.**
- [ ] **Step 3: Implement General, Appearance, and Shortcuts settings.** Apply semantic themes consistently across AppKit and SwiftUI. Offer per-tab view options, preserving explicit overrides when global defaults change. Compute row height from text and icon requirements. Keep Shortcuts concise with the approved command map; arbitrary shortcut remapping is outside this release.
- [ ] **Step 4: Rerun the tests and inspect System/Light/Dark, minimum/maximum sizes, and relaunch persistence.** Verify no clipped row text at the largest sizes and no fixed light table backgrounds in Dark mode.
- [ ] **Step 5: Commit `feat: add adaptive appearance and independent view sizing`.**

### Task 7: Transfer requests, preflight, conflicts, and naming

**Files:** Create `TransferModels`, `OperationModels`, `LocalTransferPlanner`, `FileNameRules`; tests `LocalTransferPlannerTests.swift` and `FileNameRulesTests.swift`.

**Interfaces:** Immutable `TransferRequest` contains UUID, kind copy/move, ordered source `[FileLocation]`, and destination directory. `LocalTransferPlanner.plan(_ request: TransferRequest) throws -> TransferPlan` produces ordered `PlannedTransfer` roots and captured identities. `TransferConflict` identifies job/item and source/destination metadata. `ConflictResolution` contains decision skip/keepBoth/replace/cancel and applyToAll. `OperationResult` contains per-item completed/skipped/failed/partial outcomes. Define job states queued/planning/running/awaitingConflict/cancelRequested/completed/failed/canceled. `FileNameRules.keepBothCandidate(originalName: String, ordinal: Int) -> String` preserves the extension, starting with `name copy.ext`, then `name copy 2.ext`.

- [ ] **Step 1: Add failing tests.** Reject self-copy including aliased paths, a directory into its descendant, same-item hard-link destinations, and overlapping parent/child source roots. An ordinary symbolic link is copied as a link, not traversed. Test extension-preserving Keep Both, dotfiles, names containing shell characters, and collision checks on actual case-sensitive/case-insensitive fixtures where available.
- [ ] **Step 2: Run `./script/test.sh LocalTransferPlannerTests` and `./script/test.sh FileNameRulesTests`; expect unsupported preflight/naming to fail.**
- [ ] **Step 3: Implement local plans without mutation.** Resolve actual parent directories to detect aliases; do not use string-prefix tests for containment. Reject overlapping roots with a clear message before touching files. A folder replacement replaces that folder as a whole; merging is outside this release and must not be implied. Treat preflight as advisory and retain information needed for execution-time revalidation.
- [ ] **Step 4: Rerun tests and confirm planning leaves both trees byte-for-byte unchanged.** The operating system decides whether names collide; never approximate its rules by lowercasing filenames.
- [ ] **Step 5: Commit `feat: plan local transfers and explicit conflict policies`.**

### Task 8: Safe transfer execution, cancellation, metadata, and journal

**Files:** Create `LocalCopyEngine`, `LocalOperationExecutor`, `OperationCancellation`, `OperationJournal`, and `Services/FileOperationBackend.swift`; test `LocalOperationExecutorTests.swift`, `MetadataPreservationTests.swift`, and `FaultInjectingFileOperations.swift`.

**Interfaces:** `OperationCancellation` is a thread-safe cancellation token. `LocalCopyEngine.copy(source: URL, stagingDestination: URL, cancellation: OperationCancellation, progress: @Sendable (CopyProgress) -> Void) throws` copies without following symbolic links. `LocalOperationExecutor.execute(_ plan: TransferPlan, cancellation: OperationCancellation, resolveConflict: @escaping @Sendable (TransferConflict) async -> ConflictResolution, emit: @escaping @Sendable (OperationEvent) -> Void) async -> OperationResult`. `OperationJournal.record(_ record: JournalRecord) throws` persists intent/staging/finalization/completion; `recoverableJobs() throws -> [JournalRecord]` never executes them automatically. `OperationEvent` carries state, actual copied counts, conflicts, and item outcomes.

Internal `FileOperationBackend: Sendable` defines `version(at: URL) throws -> ItemVersion`, `renameExclusive(from: URL, to: URL) throws`, `swap(_ first: URL, _ second: URL) throws`, `removeSource(at: URL, expecting: ItemVersion) throws`, and `writeJournal(_ record: JournalRecord) throws`. Its production adapter delegates journal writes to `OperationJournal`; injected test implementations fail at named boundaries. The copy engine is separately injectable with its declared copy signature.

- [ ] **Step 1: Write failing failure-injection tests.** Cancel during a file copy, fail staging, fill the destination, remove the destination volume, race a new final filename into place, change a source, and fail source deletion after destination completion. Assert source retention before completion, an unchanged old destination on failed replacement, accurate partial results, and no automatic recovery replay. Test timestamps, POSIX permissions, ACLs, xattrs/resource forks, symlinks, and packages using disposable fixtures. Use `FileOperationBackend` and the injected copy engine to place failures at exact execution boundaries; production uses Darwin/Foundation and tests use `FaultInjectingFileOperations`.
- [ ] **Step 2: Run `./script/test.sh LocalOperationExecutorTests` and `./script/test.sh MetadataPreservationTests`; expect absent execution protections to fail.**
- [ ] **Step 3: Implement the copy/finalize boundary.** Use Darwin `copyfile` with `COPYFILE_ALL`, `COPYFILE_RECURSIVE`, `COPYFILE_NOFOLLOW`, and `COPYFILE_EXCL` plus its status callback for cancellation and measured progress. Keep C callback context alive through the entire worker call. Copy into a unique staging item beside the final destination. Finalize with `renameatx_np` and `RENAME_EXCL` so a racing destination becomes a conflict. Use supported `RENAME_SWAP` or a journaled backup strategy for explicit replacement, revalidating identities and preserving recovery artifacts until the journal establishes completion; if the filesystem cannot safely support the chosen replacement strategy, fail without removing the old destination. Never use `COPYFILE_MOVE` to combine an unverified copy with source removal.
- [ ] **Step 4: Implement moves and durable outcomes.** Prefer an exclusive native same-volume move; cross-volume moves copy, finalize, compare captured source identity/content metadata, then remove the source. For recursive moves, record each copied entry's version and directory membership, then revalidate that manifest before source removal; a nested file change must retain the source tree even when the root directory's timestamps are unchanged. A changed source or failed deletion is a partial result with both locations shown. Do not claim a transactional snapshot of a directory another process is modifying. Cancellation remains cancelRequested until all filesystem mutations have stopped. Journal before and after irreversible boundaries; preserve incomplete recovery artifacts and never delete unrelated temporary files.
- [ ] **Step 5: Rerun focused tests and a real cross-volume fixture check where a disposable volume is available.** Missing optional filesystem fixtures are reported as unverified coverage, not passing tests. Confirm all source/destination assertions and metadata checks before committing `feat: execute recoverable local transfers with cancellation`.

### Task 9: Queue, shelf transfers, conflicts, and activity UI

**Files:** Create `TransferQueue`, `ShelfStore`, `ShelfView`, `ActivityView`, `ConflictSheet`; modify app services, pane actions, persistence, and `FileTableCoordinator`. Test `TransferQueueTests.swift`, `ShelfStoreTests.swift`, UI `ShelfTransferTests.swift`.

**Interfaces:** `TransferQueue.enqueue(_ request: TransferRequest) async -> UUID`, `cancel(jobID: UUID) async`, `resolveConflict(jobID: UUID, resolution: ConflictResolution) async`, and `snapshots() async -> AsyncStream<[JobSnapshot]>`. Actor ownership serializes jobs, not the main thread; executor work uses its dedicated worker. `ShelfStore.stage(_ locations: [FileLocation]) throws`, `remove(ids: Set<UUID>)`, `clear()`, and `apply(_ result: OperationResult)` consume Tasks 5/8 and persist references.

- [ ] **Step 1: Add failing queue and shelf tests.** Assert maximum running-job count is one; canceling a queued job touches no files; conflict decisions resume only the matching job; apply-to-all resets between jobs. Stage from multiple sources, deduplicate references, remove shelf entries without deleting originals, and keep failed/canceled entries while removing successful ones. Changing panes after enqueue must not change the destination:

```swift
XCTAssertEqual(recordedRequest.destinationDirectory, capturedDestination)
XCTAssertEqual(executor.maximumSimultaneousJobs, 1)
XCTAssertTrue(failedShelfItemStillExists)
```

- [ ] **Step 2: Run `./script/test.sh TransferQueueTests`, `./script/test.sh ShelfStoreTests`, and `./script/test.sh --ui ShelfTransferTests`; expect missing orchestration/UI to fail.**
- [ ] **Step 3: Implement shelf and activity surfaces.** Dropping on the shelf stages only. Copy/Move to Left/Right name the target directory before execution. Connect per-item outcomes to shelf removal, show stale items, and present all four conflict decisions plus job-scoped apply-to-all. Default progress to indeterminate when totals are unknown. Expose real cancellation state, partial completion, and recovery choices. `ActiveOperationMarker` atomically publishes the development process PID, executable UUID, and active-job count under its Application Support directory; clear it at idle/normal termination. The Run script verifies that a marker belongs to a live matching process before refusing relaunch, and ignores stale markers.
- [ ] **Step 4: Rerun focused tests and perform a multi-source shelf copy/move in fixture folders.** Browse and switch tabs while a transfer runs; verify contents at the captured destination and responsive input.
- [ ] **Step 5: Commit `feat: connect staging shelf to queued local transfers`.**

### Task 10: Rename, folders, Trash, clipboard, drag-and-drop, and limited undo

**Files:** Create `LocalFileActions`, app `FilePasteboard`; modify `AppCommands`, table coordinator, and pane contexts. Test `LocalFileActionsTests.swift`, `ClipboardRequestTests.swift`, UI `FileActionTests.swift`.

**Interfaces:** `LocalFileActions.rename(_ source: FileLocation, to name: String) async throws -> LocalMutation`; `createDirectory(named: String, in parent: FileLocation) async throws -> LocalMutation`; `trash(_ locations: [FileLocation]) async -> [ItemOperationOutcome]`; `undo(_ mutation: LocalMutation) async throws`. `LocalMutation` records exact before/after identities and expected preconditions. `FilePasteboard.readLocations() -> [FileLocation]` parses file URLs and never evaluates shell text. Clipboard and drag operations build Task 7 requests rather than copying directly.

- [ ] **Step 1: Add failing tests.** Rename rejects separators, NUL, `.`/`..`, and collisions; case-only rename works where the filesystem permits it without replacing another item. Undo refuses a renamed file that changed identity and a new folder that gained contents. Trash failure preserves the original without a delete fallback. Clipboard tests preserve spaces, Unicode, apostrophes, dollar signs, and backticks literally; folder/file drop requests capture the intended destination.
- [ ] **Step 2: Run `./script/test.sh LocalFileActionsTests`, `./script/test.sh ClipboardRequestTests`, and `./script/test.sh --ui FileActionTests`; expect missing operations and routing to fail.**
- [ ] **Step 3: Implement the actions.** Serialize filesystem mutations with the operation coordinator, use per-item outcomes, and register only successful rename/new-folder mutations with the owning window's UndoManager. Command-C/Command-V copy file URLs; Option-Command-V requests a move. File-table drag-and-drop follows the displayed copy/move operation and modifier intent; defer unsupported drops. Show incoming external file drags and export standard file URL pasteboard items. Never treat dropping on the shelf as a transfer.
- [ ] **Step 4: Rerun tests and verify native inline rename, new-folder selection, Trash, clipboard transfers, both drag directions, and undo in the installed app with fixtures.** Confirm each action refreshes affected panes and preserves useful selection.
- [ ] **Step 5: Commit `feat: complete local file actions clipboard and safe undo`.**

### Task 11: Keyboard commands, file opening, Quick Look, and accessibility

**Files:** Complete `AppCommands`, `FileTableCommandHandler`, `SystemFileActions`, `QuickLookController`, `AppDelegate`; add `CommandRoutingTests.swift` and UI `KeyboardAndAccessibilityTests.swift`.

**Interfaces:** `SystemFileActions.open(_ locations: [FileLocation])` uses NSWorkspace for regular files/packages; folders route through `WorkspaceSession.open`. `showPackageContents(_ location: FileLocation) -> FileLocation` enables explicit package navigation. `QuickLookController.present(_ items: [FileLocation], selectedIndex: Int)` owns the native panel/data source. Incoming folder URLs use the configured destination in the most recently active window, or create a new window when none exists.

- [ ] **Step 1: Add failing routing tests.** F5/F6 use the active source and opposite pane, F7 creates in the active pane, and Command-Delete requests Trash. Command-L, Command-F, Command-T, Command-W, Command-O, Command-Up, history shortcuts, Return, and Space honor the approved focus rules. Text editing consumes normal editing commands. Two windows never share an active selection. Assert Quick Look receives selected items in visible order and ordinary package opening does not browse its contents.
- [ ] **Step 2: Run `./script/test.sh CommandRoutingTests` and `./script/test.sh --ui KeyboardAndAccessibilityTests`; expect unconnected commands to fail.**
- [ ] **Step 3: Implement standard menu routing and system integration.** Use the responder chain and focused scene values rather than a global key monitor. Expose full filenames, selection, active pane, pin type, errors, progress, and command names to accessibility. Do not change default folder associations. Offer Copy Path and Open With through contextual actions using actual selected URLs.
- [ ] **Step 4: Rerun tests and inspect keyboard-only/VoiceOver navigation.** Verify that a toolbar/sidebar click keeps the intended command pane and that dialogs retain standard focus traversal. Check Quick Look open/close and normal default-application opening using harmless fixture files.
- [ ] **Step 5: Commit `feat: finish native commands previews and accessible navigation`.**

### Task 12: Icon view, installed-app acceptance, and performance evidence

**Files:** Create `Views/FileGridView.swift`; modify view mode composition/preferences; add `ViewModeStateTests.swift`; create `docs/verification/local-release.md` and `local-performance.md`; update README with real Run/test instructions and supported scope.

**Interfaces:** `FileGridView` consumes the same snapshot, selection, scroll intent, and BrowserIntent callbacks as the list. Add `gridIconSize` to preferences with default 64 and range 32 through 128, independent of `listIconSize`; migration supplies 64 for previously saved preferences. No new filesystem access path or command implementation.

- [ ] **Step 1: Add failing state tests.** Switching list/icon modes preserves location and surviving selection; icon size changes do not alter list size; older preferences acquire the grid default. Run `./script/test.sh ViewModeStateTests`; expect missing grid state/migration to fail.
- [ ] **Step 2: Implement the icon view.** Reuse selection, action routing, drop behavior, and cached icons. Do not add eager thumbnails. Rerun the state tests and inspect both modes, three appearances, long names, scaling, resizing, and multiple windows.
- [ ] **Step 3: Run the completed core and UI suites.** Execute `./script/test.sh`, `./script/test.sh --ui`, and `./script/build_and_run.sh --verify`. Inspect the installed bundle's signature and executable UUID. Record actual output and limitations. Never describe a process-only check as complete UI verification.
- [ ] **Step 4: Complete manual Full Disk Access acceptance.** Once the signed development app exists, have the user enable that exact installed app in Full Disk Access. Restart it, then browse a user-approved protected location in that app without reading document contents for diagnostics. Also verify fixture copy/move/rename/Trash, a permission-denied path, a missing volume, conflicts, cancellation, crash/relaunch recovery, and workspace restoration. Record acknowledgement separately from real location-access results. Confirm identity continuity across a subsequent signed development rebuild.
- [ ] **Step 5: Measure performance and document the local release.** Use 10,000 simple fixture entries with thumbnails disabled, at least 20 samples per reported timing. Record the machine, OS, filesystem/storage, build configuration, warm/cold definition, and sample count. Targets: cached tab switch p95 at most 100 ms; first useful local rows at most 500 ms warm and 1.5 seconds cold; input response during transfer p95 at most 100 ms. If controlled cold runs are unavailable, mark cold timing unverified. Profile table scrolling and investigate any blocking UI work. Commit `feat: finish local views and record release acceptance` only after the evidence accurately describes the implemented state.

## Exit criteria and remote handoff

The local release is complete when all twelve tasks and the acceptance records pass, with Full Disk Access enabled by the user and actual protected-location access verified in the exact installed app. Known failures or unmet budgets stay documented as unresolved work. Never label skipped integration checks as passing.

Next work is an SFTP provider plan, then SMB management, then WebDAV, using the approved design's connection requirements. Do not add remote libraries, credentials, cloud integrations, archive browsing, recursive search, synchronization, or privileged helpers to this plan.

## Plan self-review

- Design milestones A and B map to Tasks 1 through 12; C/D are explicitly deferred.
- Full Disk Access, stable identities, installation, and actual-app verification map to Tasks 1 and 12.
- Both pins, pane routing, histories, tabs, defaults, favorites, shelf, themes, sizing, and persistence each have an owning task and verification.
- All five Review Focus conditions map to named tests in their owning tasks.
- Transfer interfaces are defined before execution/orchestration consumers; persisted shelf values are defined before shelf UI.
- No implementation, build success, or permission grant is claimed by this planning document.

## Primary implementation references

- [Build macOS Apps: run bootstrap](/Users/ahuang/.codex/plugins/cache/openai-curated-remote/build-macos-apps/0.1.4/skills/build-run-debug/references/run-button-bootstrap.md)
- [XcodeGen project spec](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)
- [Apple: NSTableView](https://developer.apple.com/documentation/AppKit/NSTableView?changes=__2&language=objc)
- [Apple: FileManager](https://developer.apple.com/documentation/foundation/filemanager)
- [Apple: copyfile manual](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/copyfile.3.html), supplemented by current local SDK headers `usr/include/copyfile.h` and `usr/include/sys/stdio.h` inspected during planning.
- [Apple: Full Disk Access announcement, October 2, 2026](https://developer.apple.com/news/?id=p6zjojqw)

Status: Written for user review. Execution method has not yet been selected. Recommended: native inline execution because the tasks share state and transfer interfaces; review the completed branch independently before treating it as a usable file manager.
