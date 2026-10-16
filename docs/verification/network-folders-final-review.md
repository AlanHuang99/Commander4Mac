# Network and folder transfer final review

As of October 16, 2026. One fresh read-only review by gpt-6-astra at xhigh examined ddfd095..b446519 against the spec, plan and all five Review Focus items. It found no Critical issues, six Important issues and three Minor issues. Executor grading retained those severities. One implementer fix pass addressed all six Important findings. There was no second review.

## Significant fixes

1. Established WebDAV connections reuse their identity-matched transport. An owned-fixture reopen with an empty secret first failed authentication, then passed listing and use of an existing upload channel.
2. Every destination root and descendant is validated before batch mutation. Later-root SMB colon/backslash and WebDAV control/backslash regressions first wrote destinations, then failed with zero mutations. Outgoing WebDAV paths share the incoming-name restrictions.
3. Interior empty WebDAV path segments are rejected. Three formerly accepted href aliases now fail the regression.
4. Local readdir enforces the remaining entry budget and checks cancellation for each entry. SFTP bounds READDIR pages; SMB requests 64 KiB pages and stops before fetching another page on budget exhaustion. Missing bounded APIs first failed compilation, then provider-level regressions passed. Real stalled SMB page cancellation is prompt. A declared 32 MiB SFTP frame is rejected before its body arrives under the new 8 MiB packet cap.
5. SFTP uses direct no-follow LSTAT. An 80-file manifest first made 166 READDIR requests; its real-server regression now allows at most four, and a budget-three listing at most one page. Real symlink metadata retains link type and cannot be planned as a copy of the target. The exact MIT-licensed Citadel 0.12.1 snapshot and four changed source files are tracked in Vendor/Citadel.
6. SMB negotiation uses a cancellation-aware asynchronous service loop on separate bounded workers. Accepted-but-stalled negotiation first took 31.04 seconds; the regression now returns below three seconds. Socket duplicates are refreshed safely across reused descriptor numbers. Darwin refused-address HUP follows the library fallback branch; localhost fallback and stopped-peer write cancellation pass.

A local-listing regression discovered during this pass also has RED/GREEN evidence: files marked UF_HIDDEN remain excluded normally, including a zero-entry visible budget, and are included with Show Hidden. Logs: final-review-hidden-red.log and final-review-hidden-green.log.

## Verification

Full Debug suite: 152 tests, 17 environment-gated skips, zero failures. Separate owned fixtures: SMB 6/6, SFTP 5/5, WebDAV 6/6. Owned Keychain 1/1 also passed in this phase. Latest logs: network-final-suite.log, final-review-smb-green3.log, final-review-sftp-final.log, final-review-webdav-green2.log. Assertions were enabled. UI bundles compiled (network-reviewed-ui.log); automated UI execution remains unverified on this Mac.

The reviewed signed app was installed at its canonical path and repeated native SMB/WebDAV folder upload/download with matching bytes and structure. An active saved WebDAV profile reopened without credential entry. The exact installed app listed Mail/V10 under Full Disk Access. Deep strict signature verification passed, team 66LBY954DT, hardened runtime. Observed final PID 98945 used the canonical executable. Main UUID 1BFAF630-68F1-3236-8C91-C0764A396F08 remains valid; updated CommanderCore UUID CE0674BB-9BDD-3643-87DE-0DD5E54B2F24 identifies the final framework. The final installation log is network-final-install.log. Disposable profiles/window were removed and owned servers stopped. Original Desktop/Desktop tabs and locked pin remain intact.

Connect toolbar actions were used in the final native pass. Cmd-K did not open the editor in the CUA-observed focus state and was not reverified as a foreground keyboard action. Its cause was not established; no keyboard success is inferred from the toolbar checks.

## Rulings I made

- Ruling: Standing user authorization replaces new spec/plan/permission handoffs; execute all three requested stages inline. Cost if wrong: user may redirect selected details after work begins.
- Ruling: One staged plan covers SMB, WebDAV, and trees because they share identity, credential, routing, and transfer contracts; one final whole-phase review. Cost if wrong: larger review surface than separate protocol reviews.
- Ruling: Replace native/mixed SMB approach with direct libsmb2 after actual exclusive-rename and cache-coherency failures. Pin AMSMB2 revision 90737c486c9d1a6ed1c1d4307060587c7bb0dfec, libsmb2 aedafb2c8742c83188e27841e270fdaad6035d41; same session handles all operations. Cost if wrong: additional dynamic dependency, its maintenance, and LGPL distribution/relinking review before shipping outside this development Mac.
- Task 7: Ruling: Treat the brief's final-review checklist as the post-Task7 gate required by executing-plans, after implementation/native acceptance and Task7 test ledger completion. Why: avoids a cycle between the last task's completion and the required whole-phase review. Cost if wrong: review bookkeeping order differs from the plan bullet; product verification and final review are both still required.
- Final: Ruling: External distribution and LGPL relinking compliance remain deferred to release beyond this development Mac. Why: this task delivers the signed local development app. Cost if wrong: external distribution must wait for license/relinking and packaging review.
- Final: Ruling: Live NAS/Windows Server/public-service interoperability and current LAN privacy grants remain unverified; retain owned loopback and exact installed-app evidence only. Cost if wrong: server-specific or LAN-permission issues may appear on those environments.
- Final: Ruling: Automated XCTest UI execution and native drag completion remain unverified; retain compilation plus native acceptance as the available evidence. Cost if wrong: interaction gaps may remain outside the exercised flows.
- Final: Ruling: Remote metadata preservation, Move, Trash, replacement and server-to-server relays remain excluded behind guards. Why: this phase delivers safe contents/structure copies. Cost if wrong: those workflows require later implementation.
- Final: Ruling: Mutations preserving all available revision fields and servers deliberately falsifying bytes/validators are beyond the size/time/strong-ETag contract. Why: the client has no independent server snapshot or authenticity oracle. Cost if wrong: such changes can escape detection; no transactional snapshot guarantee is claimed.
- Final: Ruling: Vendor the exact MIT-licensed Citadel0.12.1 snapshot ae8562f895de06ccb86fdb1cbb65fd99c8976e12 with small bounded-READDIR, no-follow-LSTAT, and packet-bound patches. Why: the pinned public API buffers all directory groups and exposes following STAT only; a separate module cannot implement safe efficient metadata or budgeted enumeration through it. Cost if wrong: the project must maintain/rebase these small patches when updating Citadel; source provenance and license remain tracked.

## Deferred minors

- Final: minor (deferred): Generic synchronous libsmb2 -1 failures can initially appear as EPERM and leave stale state until a later listing retires the transport.
- Final: minor (deferred): Apply-to-all conflict decisions do not span regular-file and folder roots in a mixed remote batch.
- Final: minor (deferred): Late router attempt completions can overwrite a newer connection's sidebar state while its transport remains usable.

## Disposition

All six Important findings have regression-first evidence and a green full suite. The three Minor findings remain deferred. Keep codex/local-file-manager and its attached worktree; no merge or push was requested. External distribution is not claimed.

## Follow-up

The three minors and the Cmd-K gap were addressed in the subsequent [reliability and installer phase](reliability-icon-installer.md). The results above remain the historical record for the network phase.
