# SFTP connections design

Date: October 16, 2026. Implementation proceeds inline under the user's standing authorization to build more features without approval checkpoints.

## Outcome and scope

Extend the working local manager with saved SFTP profiles, password or OpenSSH Ed25519 key authentication, explicit host identity verification, remote listings in either pane, individual regular-file upload/download, remote rename, and remote new-folder creation. Preserve the quick two-pane workflow. SMB mounting and HTTPS WebDAV remain separate subsequent milestones in the approved order. Folder transfers, remote-to-remote copies, remote moves, remote Trash, remote previews, and remote shelf/favorite bookmarks are explicitly unsupported in this first SFTP slice, with useful explanations rather than local-filesystem fallbacks.

## Approach

Use Citadel pinned to release 0.12.1, a Swift SSH/SFTP library with an MIT license, rather than bundling Homebrew dylibs or managing secrets through subprocess arguments. Evaluate its actual source and use short-lived SFTP channels per listing/operation so server directory handles are released when channels close. Keep SSH sessions in an actor, disable automatic reconnect, bound connection/operation waits, and close transport on timeout/cancellation. Preserve dependency licenses.

Add provider-qualified `FileLocation.sftp(profileID:path:)`. Internal remote URLs contain a profile UUID and protocol path, never credentials. Remote paths are normalized lexically; server entry names containing slash, NUL, dot, or dot-dot are rejected. All local filesystem, bookmark, clipboard, watcher, preview, and mutation boundaries reject nonlocal locations. Old local session JSON remains readable. Restored remote tabs remain disconnected until an explicit connection action.

## Connection ownership and security

Profiles persist only name, host, port, username, initial path, authentication choice/key-file bookmark, routing override, and pinned public host key. Passwords/key passphrases are in Keychain or memory only. Keychain records bind to the profile's endpoint/authentication scope; editing host/port/user must not reuse another endpoint's secret. Private key contents are loaded on bounded workers, never copied into settings. Only tested OpenSSH Ed25519 private keys are offered initially.

Unknown host keys stop before authentication and present host/port, key type, SHA256 fingerprint, and an explicit Trust and Connect action. Changed keys stop with the old/new fingerprints and require explicit re-trust. No accept-anything validator. No automatic connections or credential requests during restoration. Connection state is disconnected, connecting, verification required, connected, or failed. Server failures and local-network prohibitions must not appear as empty successful directories. Use the installed canonical signed app for final checks; never reset unrelated permissions.

## Browsing and actions

A Connect toolbar/menu action opens a compact profile editor/list. Sidebar Connections offers saved profiles with Open Current/Left/Right, Edit, Disconnect, and Remove. Capture destination pane before asynchronous connection work. Existing tabs, histories, pins, filtering, sorting, and list/icon rendering use the provider router. A remote path bar edits that profile's protocol path. Local sidebar locations always return to local browsing.

Remote capabilities are explicit. Double-click browses directories. Remote file opening explains how to download to the other pane. Rename and mkdir use SFTP and never overwrite another entry. Remote destructive deletion is not exposed as Trash. Local-only actions reject remote locations at service boundaries even if invoked through keyboard/menu paths.

## Transfers

Reuse the serial queue and shared operation gate. Route fully local requests through the proven local executor. Mixed-provider copies support only one local side and regular files; reject unsupported batch kinds before making changes. Source locations and destination are immutable. Upload/download stream bounded 64 KiB chunks, check actual byte counts and source metadata before finalization, and preserve sources on all failures/cancellation. Local downloads use exclusive private staging containers and exclusive final rename. Remote uploads use exclusive-create temporary files followed by standard SFTP rename without replacement. Conflicts support Skip, Keep Both, and Cancel; replacement is hidden until a safe server-independent replacement strategy exists. Report partial artifacts through existing recovery records without replay or automatic reconnect. No source deletion for remote copies.

## Verification

Regression-first tests cover profile validation/no-secret persistence, Keychain binding, remote path identity and legacy session compatibility, local-boundary rejection, host-key first use/change/match, provider routing, stale replies, captured pane routing, transfer cancellation/collision/unsupported types/source mutation, and remote session restoration without connecting. Use an owned loopback SSH/SFTP fixture with generated host/user keys and isolated data. Verify real listing, denied/missing paths, upload/download bytes, rename/mkdir, same-name conflict, and changed host key rejection. Exercise the exact installed app with CUA, preserve existing Full Disk Access, run the complete core suite, compile UI bundles, and obtain one independent final review.

## Known costs and rulings

The user explicitly waived new approval questions; write spec/plan and execute inline without the skills' normal handoff gates. Reuse the already-attached isolated worktree. Start with single-file SFTP copies to make the safety boundary testable before recursive/cross-provider moves. Citadel has its own transitive Swift dependencies; pin resolved revisions and record notices. If the server cannot substantiate an operation, show failure rather than claim success.

Primary references reviewed: https://github.com/orlandos-nl/Citadel and its source/license at the pinned release. Existing approved project design remains authoritative for local behavior and subsequent protocols.
