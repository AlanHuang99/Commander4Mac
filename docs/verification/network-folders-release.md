# Network connections and folder copies

As of October 16, 2026. Development identity: `/Applications/Commander4Mac Dev.app`, `com.alanhuang.Commander4Mac.dev`, team 66LBY954DT. Branch `codex/local-file-manager`; phase base `ddfd095`.

## Delivered

Protocol-qualified profiles and tabs preserve old SFTP JSON/Keychain scopes. SMB has server/port/share/domain and password/Guest; WebDAV has server/port/base collection, HTTPS, and password/Anonymous. The existing pane capture and cancellable editor workflow remain in use. Endpoint/root/authentication changes rotate identities; restoration never connects automatically.

SMB uses one serialized libsmb2 context with required signing for password sessions, exclusive CREATE, non-replacing rename, bounded worker I/O, and owned-socket shutdown. Native NetFS listing worked, but exclusive rename failed with ENOTSUP; mixing mounted I/O and protocol rename then produced stale destination metadata. The delivered provider uses direct protocol operations throughout. Pinned AMSMB2 revision 90737c486c9d1a6ed1c1d4307060587c7bb0dfec embeds libsmb2 aedafb2c8742c83188e27841e270fdaad6035d41; notices are retained. LGPL distribution/relinking review remains required before external release.

WebDAV uses system TLS trust, ephemeral credential/cookie/cache handling, same-origin Basic/Digest challenges, and no redirects. HTTP is allowed only to numeric loopback. Depth0/1 PROPFIND is bounded to 8 MiB with UTF-8 XML, entity/DTD refusal, DAV namespaces, status checks, contained literal hrefs, and byte-precise duplicate detection. GET/PUT use private disk spools and 64 KiB channels. PUT uses If-None-Match:*; MOVE uses Overwrite:F; MKCOL/MOVE/PUT require 201, so 207 partial mutation replies remain failures. Idle timeout 30s, resource lifetime 1 hour. Abort never uploads an incomplete spool. WebDAV validators may change during MOVE; final bytes are hashed when the strong validator cannot be carried across publication.

Folder copies between one local and one remote pane preflight the entire batch, reject links/packages/special files/undownloaded placeholders, detect local name aliases, and bound enumeration to 100,000 entries / 128 levels. Each root stages exclusively; files stream serially with aggregate byte/file progress. Source manifests and staged verified revisions are checked before one exclusive root rename. Final structure/revisions or content hashes are checked. Root conflicts offer Skip/Keep Both/Cancel without merge/replacement. Sources are retained. Only verified owned local staging is cleaned automatically; uncertain remote artifacts remain in recovery records with non-secret endpoint snapshots. Remote Activity actions copy readable paths; Finder reveal receives only local URLs.

## Verification

Core tests, owned OpenSSH/SMB2/WebDAV fixture tests, signed installed-app checks, UI compilation, and final independent review are recorded below when complete. Logs are in `.build/logs`.

## Limits

Remote copies transfer contents and structure, not timestamps, POSIX permissions, ACLs, xattrs, or resource forks. Moves, Trash, replacement, and remote-to-remote relays are unavailable. HTTP responses and upload/download spools consume temporary disk space; a WebDAV GET is received before its file channel starts yielding chunks. Cancellation stays active during those requests. UTF-16 XML is not accepted. No automatic remote artifact deletion or replay occurs.

Fixtures establish owned loopback interoperability, not every NAS, Windows Server, or Internet service. Real LAN/local-network permission failures must be checked in the exact installed app; successful curl alone is insufficient. No privacy database, user account, File Sharing, Remote Login, SSH configuration, or trust-store changes were made.

The XCTest UI runner remains stalled on this Mac; compiling the bundles does not establish UI automation success. Native CUA acceptance supplements compilation. End-to-end native drag completion remains unverified.

## Sources

- [WebDAV RFC 4918](https://www.rfc-editor.org/rfc/rfc4918.html)
- [Apple local-network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
- [Apple local-network ATS exception](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking)
- [AMSMB2 source](https://github.com/amosavian/AMSMB2)

Verified installed-app behavior: native SMB and WebDAV authenticated listing, regular-file upload/download, and nested/empty/zero-length folder upload/download. Downloaded bytes and directory structure matched owned fixtures. Activity displayed readable smb:// and http:// loopback paths and Copy Remote Path. The exact installed app listed `~/Library/Mail/V10` without opening mail contents, confirming FDA still works. Deep strict code signature verification passed with team 66LBY954DT and hardened runtime. Observed PID 77939 used the canonical installed executable; UUID 1BFAF630-68F1-3236-8C91-C0764A396F08 was nonzero and valid. Disposable profiles/window were removed, owned servers stopped, and original Desktop/Desktop tabs/locked pin preserved.

Final fixture results: SMB 4/4, WebDAV 5/5, SFTP 3/3, owned Keychain 1/1, all zero failures. SMB included an actually stopped peer during a pending write; cancellation returned within 3 seconds. WebDAV included refused self-signed TLS, Basic/Digest authentication (both exercised in this phase), redirect refusal, denied/missing/oversized responses, partial mutation failure, abort-not-PUT, and stalled-GET cancellation. Every protocol copied a nested 216 KB tree with empty and zero-length entries and verified downloaded bytes. UI build-for-testing succeeded; automated UI execution was not claimed.
