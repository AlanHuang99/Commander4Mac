# SFTP Connections Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Execute inline under existing user authorization.

**Goal:** Add usable saved SFTP connections, remote pane browsing, and safe individual-file upload/download.
**Architecture:** Provider-qualified locations and a session actor isolate network operations. A request-level executor routes local work to the existing engine and remote copies to bounded streamed staging. SwiftUI connection controls share profiles/Keychain services and capture pane routing before awaits.
**Tech Stack:** Swift 6, macOS 15+, SwiftUI/AppKit, Security Keychain, Citadel 0.12.1.
**Spec:** docs/superpowers/specs/2026-10-16-sftp-connections-design.md

## Global Constraints

- Preserve stable installed development identity and existing Full Disk Access.
- No secrets in profile JSON, URLs, command arguments, session snapshots, or logs.
- No accept-anything host-key validation and no automatic restored connections.
- Keep local operations and old session JSON compatible.
- Single regular-file copies only across providers; reject remote move/folder/remote-to-remote batches before mutation.
- Bounded background filesystem/network work and useful error states.

## Review Focus

1. Profile endpoint edits must never send a previously stored secret to a different host/user.
2. Malicious remote filenames/paths must not escape the captured local destination or alias another profile.
3. Disconnect/cancel/collision after partial copying must retain sources and existing destinations, with accurate artifacts/outcomes.
4. Restored remote tabs and background saves must not connect, prompt for credentials, or touch local paths matching remote paths.
5. Focus/window changes during connect or conflict waits must not redirect the captured destination.

### Task 1: Profile, credentials, and remote locations

**Files:** Models/ConnectionProfile.swift, Services/KeychainCredentialStore.swift, Stores/ConnectionStore.swift, FileLocation.swift; local boundary adapters; ConnectionProfileTests.swift and RemoteLocationTests.swift.
**Interfaces:** `ConnectionProfile.validated() throws -> ConnectionProfile`, `ConnectionStore.load()/save([ConnectionProfile])`, `CredentialVault.read/write/remove(profile:)`, `FileLocation.sftp(profileID:path:)`, `isLocal`, `remotePath`, `profileID`.
- [ ] Write failing tests for validation, non-secret JSON, endpoint-bound credentials, provider-specific IDs, lexical paths, legacy location/session decode, and local service rejection.
- [ ] Run ./script/test.sh ConnectionProfileTests; expect missing API failure.
- [ ] Implement models, Keychain boundary, atomic profile store, remote locations, and explicit local guards. Preserve old Codable cases.
- [ ] Run full ./script/test.sh; expect all enabled tests pass.
- [ ] Commit feat: add secure SFTP profiles and provider locations.

### Task 2: Verified SFTP transport

**Files:** Remote/SFTPTransport.swift, Remote/CitadelSFTPTransport.swift, Remote/HostKeyVerification.swift, project.yml, script/test_sftp.sh, SFTPIntegrationTests.swift.
**Interfaces:** `SFTPTransport` protocol for list/stat/read/writeExclusive/rename/mkdir/removeOwnedTemporary/disconnect; `SFTPConnectionManager` actor with explicit connect/disconnect and no reconnect during listing. `RemoteFileMetadata` and regular-file mode checks.
- [ ] Write failing tests for unknown/matching/changed keys, safe entry names, missing/disconnected listing, and real loopback key-auth operations.
- [ ] Run targeted tests; expect missing API failure.
- [ ] Pin Citadel 0.12.1, implement strict validator, credential/key loading, quiet logging, connection deadlines and channel cleanup. Create isolated loopback fixture using generated keys and owned files only.
- [ ] Run targeted host tests plus fixture integration; expect real listing/read/write/rename/mkdir and changed-key rejection.
- [ ] Commit feat: add verified SFTP transport.

### Task 3: Remote pane integration and persistence

**Files:** ProviderRouter.swift, DirectoryLoader callers, ApplicationStateStore.swift, WorkspaceController.swift, LocationBarView.swift, PaneView.swift; ProviderRouterTests.swift.
**Interfaces:** `ProviderRouter(local:remote:)` implements DirectoryProviding; `WorkspaceController.openPath(_:in:)` retains profile identity; remote TabSnapshot restores without resolving a bookmark or connecting.
- [ ] Write failing tests for provider dispatch, stale remote replies, remote saved tabs/pins/history, and no-connect restoration.
- [ ] Run targeted tests; expect missing behavior.
- [ ] Implement provider routing, remote-aware path navigation, capability guards for local-only actions, and snapshot compatibility.
- [ ] Run full core suite; expect pass. Build app; expect success.
- [ ] Commit feat: browse SFTP locations in both panes.

### Task 4: Safe queued remote file copies and management

**Files:** RemoteTransferExecutor.swift, TransferQueue.swift, TransferModels.swift, ConflictSheet.swift, WorkspaceController.swift; RemoteTransferTests.swift.
**Interfaces:** Request-level `TransferExecuting.executeRequest(_:cancellation:resolveConflict:emit:)`, default local adapter; remote executor delegates all-local requests, streams 64 KiB, journals artifacts, excludes unsupported moves/folders/remote relays, and exposes conflict replacement capability.
- [ ] Write failing tests for upload/download bytes, skip/keep-both/collision, source mutation, cancellation/disconnect, unsupported batches, and literal/traversal names.
- [ ] Run targeted suite; expect missing API failure.
- [ ] Implement request routing, bounded copy staging/finalization, accurate outcomes, remote rename/mkdir with gate serialization, and explicit unsupported actions.
- [ ] Run full suite and real fixture transfers; expect retained sources and byte matches.
- [ ] Commit feat: add safe queued SFTP file transfers.

### Task 5: Connection interface and installed acceptance

**Files:** ConnectionsView.swift, ConnectionEditor.swift, ConnectionController.swift, SidebarView.swift, WorkspaceView.swift, AppServices.swift, project permissions strings, docs/verification/sftp-release.md.
**Interfaces:** Saved profiles and session states shared app-wide; pane destination captured before async connect; trust challenge handled explicitly; credentials stay out of Observable profile values and persistence.
- [ ] Write failing routing/state/credential tests and UI test source for Connect/sidebar flow.
- [ ] Run targeted core tests; expect missing API failure.
- [ ] Implement compact Connect sheet, sidebar profile actions, auth/key picker, explicit trust sheet, disconnect/edit/remove, capability presentation and actionable errors.
- [ ] Run full core suite, loopback integration, UI compile, signed install and CUA checks against canonical app. Reverify protected listing and local workflow.
- [ ] Record exact executed/unverified evidence and dependency licenses; commit feat: ship first SFTP connection milestone.

## Self-review

Scope intentionally implements the first protocol and individual-file transfers; subsequent protocols/recursive and remote destructive operations stay separate. Every Review Focus item has a task-owned regression. Models precede transport; transport precedes routing/transfers; UI consumes all interfaces. User standing authorization replaces new spec/plan confirmation checkpoints; native inline execution remains selected.
