# Local development acceptance, October 16, 2026

The signed local development app is installed and running at `/Applications/Commander4Mac Dev.app`. This is a development acceptance record, not a notarized distribution release. Remote protocols are deferred. Native drag completion and the XCTest UI harness remain open validation gaps.

## Automated evidence

The most recent full core run executed 66 XCTest tests: 64 passed, two environment-gated integration/performance tests skipped, zero failures. The skipped tests were run separately: real cross-volume APFS integration passed 1/1, and the opt-in 10,000-entry performance test passed 1/1. UI test bundles compile. `./script/test.sh --ui` built its runner and then stalled before any assertion result; that attempt was terminated, and the wrapper now bounds future attempts to 180 seconds. UI tests are not reported as passing.

Core coverage includes navigation generations, pane/window independence, both pin behaviors, bookmark identity checks, corrupt state preservation, preferences migration, independent sizing, literal filename/clipboard parsing, safe preflight, source and destination changes, ENOSPC, disconnection, journal failure, cancellation, conflict races, recursive source manifests, and partial move outcomes. Metadata assertions cover POSIX mode, timestamp, explicit ACL, xattr/resource fork, symlink, and package behavior. Rename/new-folder undo rejects replaced files and nonempty folders. Trash failure has no permanent-delete fallback.

An occupied staging-path regression initially failed. Transfers now create an exclusive private staging container and verify its identity before cleanup. Another regression exposed incorrect progress accounting for recursive copies; final byte/file totals and bounded notifications now pass.

## Installed-app native checks

All filesystem mutations below used disposable fixtures under the worktree's ignored `.build/acceptance-fixture`, test-owned temporary directories, or a disposable mounted APFS image. User document contents were not opened for diagnostics.

- Real Home and Downloads listings; independent filters; path navigation; independent tabs and histories.
- Locked pin retained its folder and created a new ordinary tab on navigation. Navigable pin kept its saved title/home while browsing and returned home on an active-tab click.
- A fixture favorite with a persisted Left override opened in the left pane while the right pane was active. Favorite and location rows now activate across their full width. The fixture favorite was removed afterward.
- Independent new window opened with Home/Downloads; navigation there did not replace the original window. Closing Settings now closes Settings rather than routing Command-W to a file tab. A two-tab Command-W regression was reproduced and fixed through a per-window delegate bridge; the same native window remained open with one tab.
- Shelf staged two files from different folders without moving them. Copy to Right completed both and kept originals; a subsequent multi-source move completed both and removed only the fixture sources. All destination contents matched.
- A 10,000-file copy and a second Keep Both copy each produced 10,000 entries. Keyboard pane switching remained responsive and did not change the captured destination.
- Native inline rename, Command-Z rename undo, F7 new folder with selection, Command-C/Tab/Command-V with Keep Both, and Command-Delete to macOS Trash.
- Space opened native Quick Look for a harmless text fixture; Escape closed it. Command-O opened the same file in TextEdit; only that fixture document was closed.
- List and icon modes preserved selection. Maximum grid size 128 and text size 20 displayed long Unicode filenames with truncation, full accessible names, and scrolling. Light, Dark, and System modes were exercised; System was restored. Settings exposes three separately labeled accessible sliders.
- An owned directory with POSIX mode 000 displayed an access-specific error. Its mode was restored after testing. A missing `/Volumes` fixture displayed an unavailable-location error.
- User acknowledged enabling Full Disk Access. Separately, the exact installed app successfully listed `~/Library/Mail`, including `V10`, after multiple signed rebuilds. No message contents were opened. The development bundle identity and certificate stayed stable; the executable UUID and signature are verified independently.
- An idle forced exit followed by relaunch restored pins, paths, and the large-icon view. A synthetic incomplete journal record was displayed for explicit review. No transfer replayed. Keep Files and Dismiss updated only the journal; source/staging fixture contents remained unchanged and no final destination appeared. A separate real copy was then killed with SIGKILL after 113 partial files existed. Its 10,000 source entries remained, the final destination was absent, and relaunch presented the incomplete journal without resuming or deleting staging. Explicit review retained the same 113 partial files.

## Remaining validation

Native drag source/destination handlers export and consume file URLs, and route through the planner/queue. CUA drag attempts did not produce a completed native dragging session or a validated drop. The app's mouse-down override was removed so AppKit retains its gesture handling. The XCTest drag regression compiles but has not executed on this Mac. Real-pointer file-list and shelf drops need validation before calling drag-and-drop complete.

Full VoiceOver speech traversal, removable-drive disappearance during a live native transfer, controlled cold-cache timing, scrolling frame-time/energy measurement remain unverified. Engine cancellation, disconnection, partial failures, and non-replay recovery have deterministic fixture coverage. Directory copies are not transactional snapshots of trees concurrently modified by other processes.

## Development identity

Debug uses `com.alanhuang.Commander4Mac.dev` and the canonical installed path above. Release and UITest hosts use distinct identifiers. The app has hardened runtime enabled and App Sandbox disabled. Setup acknowledgement is never treated as a global permission preflight. The Run script checks live PID, executable path, UUID, and active count before replacing a running development app. The app waits for canceled filesystem work before quitting.

## Decisions and review

Implementation ran inline in a managed worktree, with task commits and a required independent whole-branch review. Detailed decisions and review outcomes are recorded alongside this document after that review.
