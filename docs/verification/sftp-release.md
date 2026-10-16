# SFTP development acceptance, October 16, 2026

The SFTP milestone extends the existing local file manager. Canonical installed build: `/Applications/Commander4Mac Dev.app`, bundle `com.alanhuang.Commander4Mac.dev`. This is a signed development build, not a notarized distribution release.

## Delivered behavior

Saved SFTP profiles support password or OpenSSH Ed25519 private-key authentication, optional Keychain storage, explicit SHA256 host-key trust, routing to current/left/right pane, connection states, edit, disconnect, and remove. Credentials never enter profile/session JSON or remote URLs. Editing an endpoint/authentication scope or re-trusting an established changed key creates a new identity so old tabs and queued work cannot silently retarget. Restored remote tabs remain disconnected.

Remote panes share tabs, history, pins, sorting, filtering, and list/icon modes. Rename and mkdir use the serial operation gate. Queued regular-file upload/download streams 64 KiB chunks with coalesced progress, exclusive staging/finalization, source/destination checks, and Skip/Keep Both/Cancel conflicts. Existing destinations and sources are retained on failure. Uncertain temporary artifacts are journaled without replay or automatic cleanup.

SFTP copies file contents only. Permissions, timestamps, extended attributes, and resource forks are not preserved. Folder/package/symlink transfers, remote Move/Trash, replacement, server-to-server relay, remote Quick Look, and remote drag exports are unavailable in this milestone. SMB and WebDAV remain subsequent milestones. Mounted network volumes still use the local provider.

## Automated evidence

The final Debug core suite executed 104 tests, with four optional environment-gated skips and zero failures (`.build/logs/sftp-final-core-debug.log`). The owned real OpenSSH test separately passed host-key first use/match/change, no socket after rejected verification, listing/read/write/exclusive create, rename/mkdir, missing and denied directories, Unicode-name upload/download with byte equality, collision, and disconnect. Real Keychain create/read/delete passed using a random test-owned service and item, including the final Debug run (1/1, `.build/logs/sftp-final-keychain.log`).

Native Debug acceptance exposed a dependency handler assertion hidden by optimized SPM dependencies in the custom UITest configuration. The real integration test reproduced the crash with Debug assertions before the fix. A narrow task executor now runs the library's existing-channel handshake on its NIO event loop; the same Debug integration test passed afterward. Core test scripts now default to Debug so those assertions remain enabled.

Final UI bundles compiled successfully (`.build/logs/sftp-final-ui-compile.log`). The XCTest UI runner stalls on this Mac before assertions; UI execution is not reported as passing. Native CUA checks supply the installed-app evidence below.

## Installed-app evidence

All remote and local mutations used owned fixtures under ignored `.build`, a rootless OpenSSH server listening only on loopback, and generated test-only host/user keys. No user SSH key or authorized_keys was used; Remote Login and privacy databases were not changed.

- Created a saved Ed25519 test connection through Command-K, with Right pane override while Left was active. Compared its displayed public host fingerprint with the generated fixture's SHA256 value before trusting.
- Right pane loaded real remote contents while Left stayed local. Download and upload completed with matching bytes and retained sources.
- Inline remote rename and F7 mkdir changed the owned server fixture. Remote Move/Stage were disabled. Duplicate download offered Cancel/Skip/Keep Both, without Replace; Keep Both produced a matching separate file.
- Normal quit/relaunch restored the remote tab disconnected. The exact installed process had no TCP connection to the fixture port. Explicit sidebar opening reconnected using its saved host pin and loaded real contents.
- Editing the saved port without connecting created a new UUID and cleared the host-key pin. Existing remote tabs retained the old UUID. Editing back created another UUID rather than repointing those tabs.

The final signed build again loaded real SFTP contents after the handler-thread fix. It successfully listed the protected `~/Library/Mail` folder, including `V10`, without opening message contents. Deep strict signature verification passed with the stable development identifier/team and hardened runtime. The running executable is the canonical installed path with a valid arm64 UUID.

The generated test profile and test window were removed through the app. Persisted state confirms zero test profiles and one original window with Desktop in both panes. The owned server remains available only for final review verification, then is stopped through its cleanup trap.

## Validation limits

Password authentication and encrypted Ed25519 keys are implemented but have not been accepted against a real server in this session. Real LAN/public-server interoperability, native large-transfer cancellation, full VoiceOver traversal, and external network privacy recovery remain unverified. The loopback fixture proves real app/protocol behavior on this Mac, not access to another LAN host. Earlier native drag-completion gaps remain documented in [local acceptance](local-release.md).

The app includes `NSLocalNetworkUsageDescription`. An enabled Local Network switch or successful CLI request is not treated as proof that the installed app can connect. Consult Apple's [TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy) when a real installed-app log reports a prohibition. No system-wide privacy resets are performed.

## Dependency and final review

Citadel 0.12.1 is pinned exactly, and resolved transitive revisions are tracked. License notices are embedded in `ThirdPartyNotices.txt`. The transport owns TCP lifetime and closes rejected/canceled handshakes; it never uses an accept-anything host validator or automatic reconnect. See the pinned [upstream source](https://github.com/orlandos-nl/Citadel) and the [SFTP v3 rename contract](https://datatracker.ietf.org/doc/html/draft-ietf-secsh-filexfer-02).

One independent whole-phase review is required before completion. Findings and final verification will be appended here. Decisions are preserved in [SFTP decisions](sftp-decisions.md).
