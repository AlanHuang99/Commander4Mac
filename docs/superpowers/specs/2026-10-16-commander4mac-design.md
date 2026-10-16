# Commander4Mac proposed design

Date: October 16, 2026.

Status: Proposed for review. This document does not represent implemented functionality.

## 1. Intent and success

Build a native Mac file explorer for someone who values Total Commander's efficient two-pane workflow and wants a calmer interface that works well without extensive configuration.

User requirements:

- Dual panes, tabs, favorites, and a drop area or stack.
- System, Dark, and Light appearance.
- SFTP, SMB, WebDAV, and room for additional connection types.
- Responsive browsing and a sleek, original interface.
- Locked pins and pins that permit path changes. Both behaviors were explicitly confirmed.
- Control over the default current or left view and over text and icon sizes.
- Learn from Total Commander, Double Commander, Commander One, Path Finder, and ForkLift without copying their designs.
- Use the Build macOS Apps plugin.

Success means the user can browse two real locations, keep important places available, gather files from several folders, transfer them with a clear destination, and restore the workspace next launch without a setup tutorial.

Proposed assumptions for review: personal use is the first priority; direct installation precedes an App Store distribution decision; macOS 15 or later is the initial deployment target. Commander4Mac is a working name.

## 2. Approach

Recommended: native Swift app with SwiftUI scenes, toolbar composition, and settings, plus a focused AppKit file-table component. AppKit supplies direct control over column behavior, keyboard focus, selection, inline editing, and file dragging. Apple's documented table delegates and data sources support these interactions. [Apple: NSTableView](https://developer.apple.com/documentation/AppKit/NSTableView?changes=__2&language=objc).

Use an Xcode macOS application project with a separate test target and one app-producing scheme. Keep reusable filesystem and state logic independent of the app target's UI layer. Do not require a web runtime for the browsing interface.

Alternatives considered:

| Approach | Benefit | Trade-off |
| --- | --- | --- |
| SwiftUI shell with AppKit file tables | Modern scene structure with direct control over critical file interactions. | Requires a small, carefully bounded bridge between two UI systems. |
| SwiftUI throughout | One UI model and less bridging. | Selection, focus, drag-and-drop, and large-directory behavior would need early validation against our requirements. |
| AppKit throughout | Consistent responder-chain and desktop-control model. | More manual window and settings composition. |

The recommendation is an engineering choice, not a proven performance comparison. Directory and interaction benchmarks will decide whether the implementation meets the targets.

## 3. Window and visual direction

Use one primary window type with multiple windows supported. Each window owns its pane focus and browsing session. Settings have their own standard macOS window.

The main window has four stable regions:

1. A restrained toolbar with navigation, view options, Connect, and activity access.
2. A collapsible sidebar with Favorites, Locations, and Connections.
3. Two resizable file panes, each with its own tabs, breadcrumbs, table, and status line.
4. A shared bottom shelf for staged items, normally reduced to a slim strip when empty.

Conceptual layout, not a pixel specification:

```text
+-----------------------------------------------------------------------+
| Navigation       View options             Connect       Activities     |
+--------------+---------------------------+----------------------------+
| Favorites    | Left tabs             [+] | Right tabs             [+] |
|              | Location breadcrumbs      | Location breadcrumbs       |
| Locations    +---------------------------+----------------------------+
|              | Name       Size  Modified | Name        Size  Modified |
| Connections  |                           |                            |
|              |       file table          |        file table          |
|              |                           |                            |
|              +---------------------------+----------------------------+
|              | Selection and free space  | Selection and free space   |
+--------------+---------------------------+----------------------------+
| Shelf: staged items                 Copy to Right   Move to Right      |
+-----------------------------------------------------------------------+
```

Use system typography, semantic colors, native selection behavior, thin separators, and consistent spacing. Keep filenames visually dominant. Give the active pane both a visible accent and an accessible focus description. Preserve filename extensions when truncating names; show the full path on demand.

The shelf is a shared horizontal work area with explicit destination actions. It does not reproduce Path Finder's module layout, icons, styling, or assets. Reference research concerns tasks and interaction principles. [Research notes](../../research/2026-10-16-reference-review.md).

List view is the initial default. An icon view is a follow-up within the local-browser release sequence. Do not add permanent inspectors, a terminal, or configurable module grids to the initial interface.

## 4. Navigation and tabs

Each pane maintains its own tab collection. Each tab owns current location, back/forward history, selection, scroll position, sorting, filter, and display options. Switching one pane never changes the other pane's location.

- Double-click opens folders; double-click on a file opens its default application.
- Return renames the selected local item, following the proposed Mac shortcut scheme. Command-O opens it.
- Command-Up opens the parent. Command-Left and Command-Right navigate history.
- Space invokes Quick Look when the table has focus.
- Tab switches between the panes when a file table has focus. Text fields and dialogs retain normal Tab behavior.
- Command-L edits the active location. Command-T opens a tab in the active pane. Command-W closes the active unpinned tab; closing the last tab follows standard window closing behavior.
- Type-to-select works in the table. Command-F focuses an explicitly labeled filter for the current directory; recursive search is a later feature.

One pane remains the command destination when a sidebar or toolbar receives focus. Commands capture the source selection and destination at invocation time so later focus changes cannot redirect a running operation.

Pin behaviors:

| Mode | Navigation | Return behavior | Closing |
| --- | --- | --- | --- |
| Ordinary tab | Freely changes location. | No saved home. | Standard close. |
| Locked pin | The pinned tab remains at its saved location. A navigation request opens an ordinary tab in the same pane. | The original pin stays available. | Unpin before standard close. |
| Navigable pin | Freely browses while keeping a separate saved home. | Clicking an already active pinned tab or choosing Return to Pinned Folder restores home. Switching away and back preserves the browsed location. | Unpin before standard close. |

The navigable pin's explicit return behavior is a proposed default. It avoids silently resetting a browsing session. Automatic reset on tab re-entry is a possible later option if the user prefers the Double Commander behavior. The reference documents that behavior; it is not assumed to be the only valid design. [Double Commander help](https://doublecmd.github.io/doc/en/help.html).

Pinned titles retain the home name. Breadcrumbs always show the actual current location. A navigable pin away from home has a small return indicator and an accessible explanation. Users can explicitly change its saved home through the tab menu.

## 5. Favorites and opening destinations

Favorites are named shortcuts, separate from tabs. Allow add, reorder, rename, and remove. Store local locations using durable bookmarks where possible, together with enough display metadata to explain an unavailable location. Never silently retarget a missing favorite.

Interpret “open with default current/left view” as the destination for favorites, saved connections, and incoming folder-open requests. Default to the current pane; provide Current, Left, and Right choices. Show the destination in the action's context menu. A favorite or connection may override the global destination.

Resolve the target before opening and make it the active pane. If that target is a locked pin, create an ordinary tab there instead of replacing the pin. Provide an explicit Open in New Tab action. Opening ordinary files with their default macOS application remains a separate action from this pane-routing preference.

Restore the previous session at launch by default. On first launch use Home on the left and Downloads on the right, handling unavailable or permission-restricted locations visibly. Do not override the system's default folder handler during installation.

## 6. Shelf

The user can stage selections from either pane or drop files from another app. Staging stores references; it does not relocate, upload, or duplicate the files. The established use case is gathering items across directories before placing them together. [Cocoatech: Drop Stack](https://support.cocoatech.com/hc/en-us/articles/43505869579796-Drop-Stack-Temporary-Holding-Area-for-Files).

Deduplicate identical provider/item references. Show filename, source location on demand, and an unavailable state if an item disappears. Removing an item from the shelf only removes its reference. Staging a folder does not recursively enumerate its contents.

Copy to Left/Right and Move to Left/Right always name the current destination folder. Disable unsupported operations and explain why. On successful transfer, remove completed entries from the shelf. Failed and canceled entries remain available for review and retry. Partial batch results are reported per item.

Persist shelf references between launches. Resolve them lazily. Restoring a remote reference must not automatically connect or request credentials.

## 7. Appearance and configuration

The first run should be useful immediately. Keep the primary settings to General, Appearance, Connections, and Shortcuts.

- Appearance: System, Light, Dark. Apply the chosen mode to all app-controlled browsing surfaces.
- Text size: independent list text control, proposed default 13 points and range 11 through 20.
- List icon size: independent control, proposed default 20 points and range 16 through 32. Row height accommodates both text and icons.
- Icon view size, when introduced: separate from list icon size.
- View options near each pane expose sorting, visible columns, folders first, hidden files, text size, and icon size. Global defaults seed new tabs; local overrides persist per tab. Do not automatically generate per-folder preference files.
- Keyboard: Mac shortcuts by default, with F5 Copy to Other Pane, F6 Move to Other Pane, and F7 New Folder as additional commands. Hardware function-key settings can affect these keys, so all actions also have menus and clickable controls.
- Command-Delete moves to Trash where supported. Do not bind an immediate permanent deletion to F8.

No mandatory shortcut wizard, theme editor, or long configuration tour. Every core action is discoverable through standard menus and context menus.

## 8. Architecture and ownership

Organize source by App, Views, Models, Stores, Services, and Support, using the Build macOS Apps plugin guidance. The root view composes features rather than owning filesystem or networking code.

| Component | Responsibility | Inputs and dependencies |
| --- | --- | --- |
| Window session | Two pane sessions, focus, split ratio, command routing. | Settings and per-window saved state. |
| Pane and tab state | Navigation, pins, selection, sorting, filter, display state. | Provider-backed locations and directory snapshots. |
| Browser service | Directory loading, cancellation, change observation, cached metadata. | A filesystem provider; no UI dependency. |
| File table bridge | Render snapshots and report user intents. | Values and callbacks; never performs disk or network access itself. |
| Provider interface | List, inspect, read, write, create, rename, move, and supported capabilities. | Provider-specific clients. Unsupported capabilities remain explicit. |
| Operation coordinator | Plan, queue, execute, cancel, and report item operations. | Providers, source references, immutable destination, conflict decisions. |
| Favorites and shelf stores | Persist location references and ordering. | Versioned state storage. |
| Connection store | Non-secret profiles and connection states. | Provider adapters; Keychain references for secrets. |
| Settings store | Appearance, defaults, routing, and shortcuts. | Durable preferences. |

Use a provider-qualified location, not a raw POSIX path as the universal location type. A remote location includes a profile identifier and a protocol path without passwords. File identity is separate from row order and display name. Selection is keyed by stable item identity where available.

Directory work runs off the main thread. Each navigation request has a generation token; a slow response for an old location cannot replace the current tab. The UI receives immutable snapshots or bounded updates. An unavailable directory is an error state, never an empty successful listing.

Observe active local directories, debounce changes, and reconcile by item identity. Refresh when a tab regains focus. Use bounded metadata and icon caches; defer thumbnails and recursive size calculations. Mounted shares may stall filesystem calls, so use bounded concurrent work and cancellation of interest; do not promise cancellation can interrupt every system call.

Persist versioned preferences and session snapshots atomically. Keep the last valid snapshot if a write fails. A corrupt session should produce a recoverable fresh workspace and preserve the damaged file for diagnosis.

## 9. Local operations and reliability

Local copy, move, rename, create-folder, and Trash are necessary for the first usable release. Foundation provides the relevant file APIs; the application adds routing, orchestration, and error presentation. [Apple: FileManager](https://developer.apple.com/documentation/foundation/filemanager).

- Default to one active transfer job initially, with subsequent jobs queued. Browsing remains available.
- Preflight obvious self-copy and folder-into-descendant mistakes. Revalidate immediately before mutation; preflight is not a guarantee against concurrent changes.
- Conflicts offer Skip, Keep Both, Replace, and Cancel. Apply-to-all is scoped to the current job. No silent overwrite.
- Copy to a unique temporary destination and finalize only when complete. For replacement, retain the old destination until successful finalization where the filesystem permits safe replacement.
- For moves within one filesystem, prefer a native move. Cross-volume moves copy and validate completion before removing the source. Cancellation or failure before completion keeps the source.
- Preserve local metadata supported by the chosen implementation. Verify timestamps, permissions, extended attributes, resource forks, packages, and symlinks using fixtures. Report unsupported preservation across remote providers later.
- Treat application bundles and other packages as files for ordinary opening. Expose Show Package Contents separately. Copy symlinks as links instead of following them recursively by default.
- Cancellation occurs at a documented safe boundary. Display cancellation requested while a non-interruptible operation completes. Never display canceled while the job is still mutating files.
- Show operation progress that the engine can substantiate. Indeterminate progress is acceptable during enumeration; percentage or byte counts require measured totals.
- Record completed, skipped, failed, and partial results separately. After interruption, inspect journaled destinations before offering retry. Do not automatically replay destructive actions on launch.
- Trash failures stay failures. Never fall back to permanent deletion without an explicit, separate user action.

Undo in the first release covers successful local rename and create-folder actions when their preconditions still hold. Conflicts stop undo with a useful explanation. Broad transfer undo, replacement undo, and remote undo are later work and must not appear as unsupported UI promises.

## 10. Connections

The local-first implementation must leave room for real providers, not present placeholder remote folders as working connections.

Order after the local release:

1. SFTP: saved profiles, password and key authentication, server identity verification, listing, download, upload, and remote management with capability-aware behavior.
2. SMB: integrate macOS-managed mounts so normal file browsing uses the mounted filesystem. Mount creation, credentials, reconnect behavior, and ownership of unmounting require a focused feasibility check first. Existing mounted SMB volumes can be browsed in the local release, but that is not integrated SMB connection management.
3. WebDAV over HTTPS: collections, upload/download, rename/move where supported, authentication, redirects, and server compatibility checks.

Each protocol is a separate implementation milestone with its own spec and integration fixtures. Evaluate maintained libraries and their licenses, packaging, and cancellation behavior before selecting dependencies. FTP/FTPS, S3, and cloud-account APIs are candidates for later scope, not first-release promises.

Connection state is explicit: disconnected, connecting, verifying identity, authenticating, connected, reconnect required, and failed. Store secrets in Keychain; keep them out of URLs, command arguments, preferences, logs, and session snapshots. A changed SFTP host key or invalid TLS certificate must produce an actionable identity error.

Remote-to-remote transfer may require a streamed relay through the Mac with bounded buffering. Direct server-side operations are used only when the adapter verifies support. Cross-provider Move removes a source only after the destination is finalized and the completion requirements are met.

## 11. Platform access and distribution

Propose direct distribution initially, with a normal app bundle, hardened runtime for distribution, and stable application/signing identity. An App Store sandboxed build is a separate distribution decision. macOS privacy and filesystem restrictions still need correct handling; do not request Full Disk Access as a default onboarding step. If sandboxing is introduced, manage persistent security-scoped access and stale bookmarks explicitly. [Apple: File access](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox?language=objc).

Use distinct development and production bundle identities. Give executables valid, unique build UUIDs and avoid scattering duplicate registered app bundles. Log the actual running executable and bundle identity for diagnostics without recording secrets or file contents.

Follow the user's shared Local Network lessons: an enabled permission switch and a successful command-line request do not establish access for the app. Distinguish actual permission evidence from generic connectivity failures. Include the appropriate usage description and test authenticated content access in the installed app. Do not reset network privacy databases or unrelated permissions as routine troubleshooting. [Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).

The Build macOS Apps workflow will provide one project-local build-and-run script and a Codex Run action when implementation begins. The script must launch a real app bundle. Native UI verification must inspect the running app, not just its process identifier.

## 12. Milestones and acceptance

### A. Local workspace

Working two-pane list browsing, per-pane tabs and histories, both pin modes, favorites and destination routing, editable paths, directory filtering, selection restoration, shelf reference collection, session persistence, themes, and text/icon size controls. Include file opening and Quick Look.

Acceptance: browse two temporary fixture directories, open multiple tabs, exercise both pin modes, route a favorite to the left while the right pane is active, stage items from multiple folders, change appearance, and relaunch with state restored. Missing locations and permission failures are visible. This milestone becomes useful for browsing, but is not described as a complete file manager until milestone B.

### B. Local file manager

Copy, move, rename, new folder, Trash, conflicts, operation queue, safe cancellation boundaries, drag-and-drop, and the documented limited undo. Add icon view after list interaction and operations are stable.

Acceptance: complete a real multi-source shelf copy and move; verify contents and metadata in fixtures; test duplicate names, package and symlink behavior, cross-volume failure, cancellation, partial batches, and disk/access errors. No test manipulates the user's unrelated files.

### C. Remote providers

Implement SFTP, SMB management, and WebDAV as separate slices, using the existing location and operation interfaces. Each protocol must complete authenticated listing and real content transfer in the installed app before it is called supported.

### D. Extensions

Evaluate recursive and Spotlight search, archive browsing, batch rename, directory comparison/sync, saved workspaces, remote editing, and additional providers after the core workflows are dependable. These are backlog candidates.

## 13. Verification and performance

Automate meaningful state and operation behavior: pin routing, pane independence, stale asynchronous responses, conflict decisions, data preservation, cancellation states, and session migrations. Use disposable filesystem fixtures and protocol integration fixtures.

Run native interaction checks for keyboard-only navigation, focused-pane routing, multi-selection, drag-and-drop, VoiceOver, long and Unicode names, display scaling, window resizing, multiple windows, and all three appearances. Test cloud placeholder behavior without hydrating whole directories just to render a list.

Proposed performance budgets, not measurements:

| Scenario | Target and measurement condition |
| --- | --- |
| Switch to an already loaded tab | Updated visible state within 100 ms at the 95th percentile. |
| Open a local folder with 10,000 simple fixture entries | First useful rows within 500 ms warm and 1.5 seconds cold, thumbnails disabled. |
| Browse while a large copy runs | Selection and navigation input response within 100 ms at the 95th percentile. |
| Scroll large directories | No long main-thread stalls from enumeration, thumbnail work, or transfer execution. Profile the actual table. |

Record machine, storage, OS, build configuration, fixture shape, and sample count for benchmark results. Large or remote directories may take longer to finish listing; show progress and keep navigation responsive rather than claiming a universal speed guarantee.

Current environment limitation: the local toolchain reported unaccepted Xcode license agreements. The user must review and accept them before builds can be verified. No product code or build has been created during this design stage.

## 14. Review state

- [x] Reflect the user's requirements and separate assumptions.
- [x] Inspect the empty workspace and installed reference apps.
- [x] Verify reference workflows and platform guidance against primary sources.
- [x] Confirm that both pin modes are wanted.
- [x] Compare implementation approaches and recommend one.
- [x] Write and self-review the proposed design.
- [ ] User review of this written design, including navigable-pin return timing and milestone order.
- [ ] Write the implementation plan after design approval.
- [ ] Implement, build, and validate the approved first milestone.
