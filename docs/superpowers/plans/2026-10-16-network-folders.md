# SMB, WebDAV, and folder transfers implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans inline, preserving the user's standing authorization and requested delivery order.

**Goal:** Deliver SMB, then WebDAV, then staged recursive copies in existing panes.
**Architecture:** Protocol-qualified models and one connection router dispatch to SFTP, direct serialized SMB sessions, and direct HTTPS WebDAV. A manifest-based tree executor reuses bounded regular-file copies and exclusive root publication.
**Tech Stack:** Swift 6, macOS 15+, libsmb2 through pinned AMSMB2, URLSession/FoundationXML, existing Citadel 0.12.1.
**Spec:** docs/superpowers/specs/2026-10-16-network-folders-design.md

## Global Constraints

- Preserve stable installed identity, Full Disk Access, local behavior, old profiles/sessions, and SFTP Keychain records.
- No passwords in profile/session/journal/URL/log/command arguments; no automatic restored connection or mount.
- Never unmount a borrowed/user mount, bypass TLS validation, forward credentials across origins, replace existing remote destinations, or delete copy sources.
- Streaming chunks 64 KiB; tree bound 100,000 entries / 128 levels; HTTP idle timeout 30 seconds, resource timeout 1 hour.
- Explicit unsupported symlinks/packages/special files, remote moves/Trash/replacement/relays; contents/structure only for remote copies.

## Review Focus

1. Protocol, root, domain, endpoint, or authentication edits must not retarget queued jobs, reuse another endpoint's secret, or lose the captured pane through credential entry.
2. A canceled or late SMB handshake must close only its owned transport; SMB protocol paths must never expose matching local directories or alter user mounts.
3. Malicious WebDAV hrefs, redirects, XML entities, failed propstats, or partial mutation responses must not leak credentials, escape the base collection, or report success.
4. Folder cancellation, collision, aliasing, and source changes must retain sources/existing destinations and identify uncertain artifacts after profile retirement.
5. Restored remote trees and background saves must not mount, connect, prompt, or touch matching local paths.

### Task 1: Protocol-qualified profiles and locations
**Files:** ConnectionProfile.swift, FileLocation.swift, ConnectionWorkflow.swift, ProviderRouter.swift, ApplicationStateStore.swift; NetworkProfileTests.swift.
**Interfaces:** `ConnectionProtocol`, `ConnectionProfile.protocolKind/share/domain/basePath`, `FileLocation.remote(kind:profileID:path:)`, `connectionProtocol`, legacy SFTP scope unchanged.
- [ ] Write tests for legacy decode/scope, protocol separation, share/base/domain ID rotation, path navigation and restored no-local resolution.
- [ ] Run ./script/test.sh NetworkProfileTests; expect missing API RED.
- [ ] Implement models, validation, credential scopes, remote construction/navigation and Codable compatibility.
- [ ] Run full ./script/test.sh; expect all enabled tests pass. Commit.

### Task 2: Direct SMB provider and owned fixture
**Files:** Remote/SMBConnectionManager.swift, project.yml, dependency notices, script/test_smb.sh; SMBTests.swift, SMBIntegrationTests.swift.
**Interfaces:** `SMBConnectionManager: RemoteFileAccess` with connect/disconnect/isConnected, owned socket cancellation, and protocol-qualified paths.
- [ ] Write failing mount-boundary and owned integration tests: real listing/bytes/exclusive collision/rename/mkdir, queued handshake cancellation and local fallback rejection.
- [ ] Run targeted tests; expect missing provider RED.
- [ ] Implement direct serialized libsmb2 lifecycle, timeout/cancel, protocol paths and bounded worker I/O; create disposable loopback SMB2 fixture in isolated test environment.
- [ ] Run core and real SMB integration; report any concrete platform limitation. Commit.

### Task 3: SMB connection UI and dispatch
**Files:** Remote/RemoteConnectionManager.swift, AppServices.swift, ConnectionController.swift, ConnectionEditor.swift, WorkspaceController.swift, sidebar/toolbars.
**Interfaces:** `RemoteConnectionManager: RemoteFileAccess`, `connect(_:secret:attempt:)`, `cancelAttempt`, `snapshots`, `isConnected`, `disconnect`; same API consumed by app.
- [ ] Write routing/state tests for protocol dispatch and canceled credential entry preserving pane/identity.
- [ ] Run targeted suite; expect missing dispatch RED.
- [ ] Wire shared router, SMB fields/guest/password, gate-safe disconnect and state presentation. Keep WebDAV hidden until implemented.
- [ ] Run full core, compile UI, signed build and SMB installed acceptance. Commit usable SMB milestone.

### Task 4: Safe WebDAV transport
**Files:** Remote/WebDAVConnectionManager.swift, WebDAVXML.swift, WebDAVFileChannel.swift; WebDAVTests.swift, WebDAVIntegrationTests.swift, script/test_webdav.sh.
**Interfaces:** `WebDAVConnectionManager: RemoteFileAccess` with explicit connect/disconnect/isConnected, bounded authenticated HTTP operations and file-backed channels; `RemoteFileChannel.abort()`; remote revision includes optional ETag.
- [ ] Write failing tests for PROPFIND parsing/root containment/percent identities/failed propstats/XXE, redirects/auth, exclusive PUT/MOVE, real bytes, denied/missing/stalled requests and abort-not-uploading.
- [ ] Run targeted suite; expect missing transport RED.
- [ ] Implement HTTPS/session ownership, bounded XML, spools, idle/resource deadlines, MKCOL, Overwrite:F finalization and cancellation.
- [ ] Run full core and owned real WebDAV integration. Commit.

### Task 5: WebDAV UI and dispatch
**Files:** connection router/editor and profile UI; NetworkConnectionTests.swift.
**Interfaces:** Task 3 router dispatches WebDAV, editor exposes HTTPS base collection and anonymous/password modes.
- [ ] Write failing dispatch/protocol-change tests; run targeted suite for RED.
- [ ] Enable WebDAV, preserve SFTP credentials and pane capture, provide permission-specific/actionable errors when actual evidence supports them.
- [ ] Run core, UI compile, signed build and installed WebDAV acceptance. Commit usable WebDAV milestone.

### Task 6: Recursive manifest and staged tree executor
**Files:** Remote/TransferTreeManifest.swift, Remote/RemoteTreeTransferExecutor.swift, RemoteTransferExecutor.swift; RemoteTreeTransferTests.swift.
**Interfaces:** `TransferTreePlanner.plan(_:) async throws -> TransferTreeManifest`, verify root manifest; tree executor consumes same RemoteFileAccess/journal/conflict/cancellation contracts as regular copy.
- [ ] Write failing tests for nested/empty/Unicode trees, root Skip/Keep Both, source mutation, bounds, links/packages rejection, local alias collision, cancellation/disconnect and exclusive finalization.
- [ ] Run targeted tree suite; expect missing API RED.
- [ ] Implement bounded no-follow manifests, exclusive root staging, reused bounded file copying, revalidation and accurate artifacts/outcomes/progress.
- [ ] Run full suite and real protocol folder round trips (SFTP/SMB/WebDAV). Commit.

### Task 7: Folder UI, recovery, final installed acceptance
**Files:** capability checks, ActivityView.swift, OperationJournal.swift, endpoint snapshot model, README and docs/verification/network-folders-release.md.
**Interfaces:** remote folder Copy enabled through one shared capability predicate; journal has backward-compatible optional endpoint snapshot; remote actions copy readable paths.
- [ ] Write failing capability/recovery tests including retired profile endpoint identity and no local Finder routing.
- [ ] Run targeted tests for RED; implement controls and recovery presentation.
- [ ] Run full Debug suite, owned integration fixtures, UI compile, signed install and native checks. Preserve original workspace and FDA. Record exact limitations; commit.
- [ ] One independent whole-phase review from ddfd095, significant findings fixed in one RED/GREEN pass, final green suite, preserve rulings/minors, clean only this plan scratch, keep branch/worktree.

## Self-review

All five focus areas are assigned regression tests. Shared identity precedes transports, SMB ships before WebDAV, both precede tree copies. Local and SFTP compatibility remains mandatory at every full-suite gate. This is one coupled connection/transfer extension; user authorization replaces review/approval pauses while inline implementation and the final independent review remain required.
