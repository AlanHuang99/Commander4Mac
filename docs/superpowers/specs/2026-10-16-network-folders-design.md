# SMB, WebDAV, and folder transfers

## Intent and delivery order

Extend Commander4Mac's existing saved connections and dual panes in the user's requested order: usable SMB, then WebDAV, then recursive folder copies. Keep the interface compact, preserve Full Disk Access and local behavior, and execute inline under the user's standing authorization without new approval handoffs. These stages share provider identity, credentials, routing, and the queue, so one staged implementation plan and one final independent review cover their interactions.

## Shared connection model

Add protocol-qualified SMB and WebDAV profiles/locations alongside SFTP. Old profile/session JSON must decode as SFTP. Retain the exact legacy SFTP credential scope and Keychain service so existing credentials remain usable. Bind new credentials to protocol, endpoint, user/domain, and share/base collection. Endpoint/root/authentication changes rotate IDs. URLs and journals never contain passwords. Capture pane routing before awaits; retain the cancellable editor workflow. Restoration does not connect, mount, or request credentials.

## SMB

Use a direct libsmb2 connection per profile, consumed through the pinned AMSMB2 dynamic package. Native NetFS was tested successfully for browsing, but the real volume rejected RENAME_EXCL; a mixed mount/protocol rename then produced stale destination metadata. The direct provider keeps all listing, stat, streaming, and ReplaceIfExists=false rename on the same protocol context. Password sessions require signing; server-required encryption uses the library's SMB3 negotiation. Profiles specify server, port, share, optional domain, username/password or Guest, and an initial path within that share.

Never mount or unmount system shares. Protocol paths cannot fall through to local paths. Serialize each C context on bounded workers, set network operation timeout to 30 seconds, and shut down only its owned socket on cancel/disconnect. Keep credentials in memory/Keychain and outside URLs/arguments. Enforce exclusive CREATE, no-replacement rename, literal paths, and explicit disconnected errors. Preserve pinned source revisions and LGPL notices; distribution packaging needs the dependency's licensing/relinking review before release.

## WebDAV

Use direct URLSession HTTPS with system TLS validation, ephemeral credentials/cookies/cache, same-origin authentication, and no redirects. HTTP is permitted only for numeric loopback test endpoints; production profiles use HTTPS. Specify server, port, base collection, credentials/anonymous, and an initial relative path. Parse bounded depth-one PROPFIND XML without external entities. Validate origin, base-root containment, depth, percent-decoded components, byte identity, duplicates, and per-property status. Never interpret a foreign href as a local path.

Use GET downloads and PUT uploads backed by private disk spools so memory stays bounded; file channels read/write 64 KiB chunks. Upload to a unique remote staging path with If-None-Match: *, then MOVE with Overwrite: F. Require successful non-replacing finalization; errors remain errors, including HTTP 207 partial mutation responses. MKCOL creates directories exclusively. Credentials are never forwarded to another origin or persisted in URLSession credential storage. Cancel terminates pending HTTP work; request idle timeout is 30 seconds and resource lifetime is bounded. Spools are removed on finish/abort and never uploaded by error cleanup. Preserve source revisions using actual size/time/strong ETag information.

## Folder copies

After both protocols work, extend Copy between one local and one remote pane to regular directory trees. Fully local copies continue through the existing metadata-preserving local engine. Preflight every root before destination mutation; enumerate at most 100,000 entries and 128 levels, using validated literal names and byte-precise relative identities. Reject symlinks, packages, special files, unsafe names, and source changes explicitly. No remote moves, deletion, replacement, or server-to-server relays in this scope.

Stage each entire root tree under an exclusive private name. Stream files serially, verify source manifests again and verify staged/finalized structure, then perform one exclusive root rename. Conflicts apply to the root with Skip/Keep Both/Cancel, without merging/replacing existing trees. Cancellation/disconnect retains sources and existing destinations. Remove only verified owned local staging; retain uncertain remote artifacts for explicit recovery. Remote transfers copy contents/structure, not POSIX permissions, dates, ACLs, xattrs, or resource forks. Show useful aggregate byte/file progress.

## Recovery and interface

Protocol picker and protocol-specific fields share the existing compact editor/sidebar. Capability guards enable supported folders only after the tree engine exists. Preserve tab/history/pin semantics and native text editing. Recovery journals capture non-secret endpoint snapshots so retired profile IDs remain identifiable. Remote Activity actions copy readable remote paths instead of sending internal URLs to Finder.

## Verification

Use regression-first tests for protocol isolation, legacy decoding, root changes, restoration, mount identity/fallback, malicious WebDAV hrefs/XML/statuses, redirected auth, literal names, recursive structure/conflicts/source changes/cancellation, and recovery endpoints. Owned loopback fixtures use generated credentials/keys and disposable roots; never enable Remote Login/File Sharing or alter user accounts, SSH files, trust stores, or privacy databases. Verify real SMB mounting and WebDAV operations where the environment permits, with exact limitations reported. Keep canonical signed /Applications/Commander4Mac Dev.app identity stable; inspect actual installed process/logs for network permission failures, and reverify protected listing. UI bundles must compile; native CUA acceptance supplements the currently stalled XCTest UI runner. One fresh whole-phase reviewer, one regression-tested significant-fix pass, no second review.

## Primary references checked

- Current Xcode SDK NetFS.h: NetFSMountURLAsync, NetFSMountURLCancel, new-session/NoUI/soft-mount options.
- RFC 4918: https://www.rfc-editor.org/rfc/rfc4918.html
- Apple local-network privacy: https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy
