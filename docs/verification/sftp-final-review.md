# SFTP independent review and fixes, October 16, 2026

One fresh, read-only whole-phase review examined `ce24845..4e4391f` against the approved SFTP spec, plan, and all five Review Focus items. No reviewer builds, application actions, source mutations, or second review occurred. Reviewer: gpt-6-astra, xhigh. It found no Critical issues, four Important issues, and two Minor issues. Executor re-grading retained those severities.

## Important findings corrected in one fix pass

1. **Stalled file I/O retained the shared operation gate.** SSH child-channel close waits for a peer response, so the original timeout could itself wait indefinitely. Real fixture tests now stop only the owned OpenSSH connection children after the first streamed chunk. Both timeout and Cancel initially failed to terminate the session/release the queue (`sftp-review-stall-red3.log`). File-channel deadlines and cancellation now hard-close the owned parent TCP transport, guarded by session token. Transfer cancellation propagates to pending async I/O. Both tests pass and the following queued local copy completes before the peer is resumed (`sftp-review-stall-green.log`, final integration log).
2. **Editor Cancel left asynchronous preparation running.** The editor now owns a cancellable submission across profile save, credential lookup, and connect. Cancellation checks prevent post-dismissal trust/navigation. Attempt-specific cleanup cannot disconnect a newer attempt or an existing session during Save. A final native retry check exposed an old editor UUID after successful endpoint save followed by missing-password entry. That regression was observed before correction; the editor now keeps the committed UUID before credential lookup, and the same retry reached connection setup afterward. Barrier tests cover cancellation before connect and during connect; a real transport assertion checks stale cancellation does not disconnect a successor.
3. **Missing-password fallback discarded pane routing.** The original request now passes through credential entry, with its resolved destination preserved. `testMissingCredentialHandoffPreservesExplicitPaneAfterFocusChanges` proves that an explicit Right request survives Left focus/default routing.
4. **Profile save failure deleted the old Keychain credential.** A testable persistence coordinator stages credential changes with rollback and removes old items only after the atomic profile document commits. Rotated-ID save failure, same-ID password update failure, and removal failure retain the old credential. Post-commit cleanup failure returns a warning while keeping memory and the committed document aligned. Keychain and filesystem cannot provide a shared atomic transaction; a rollback failure is explicitly reported for manual credential review.

The workflow/persistence regressions first failed for missing APIs (`sftp-review-workflow-red.log`), then passed 5/5 (`sftp-review-workflow-green.log`). Full Debug suite after fixes: 111 tests, six optional environment-gated skips, zero failures (`sftp-complete-core.log`). Real SFTP, final UI compile, signed install, and native follow-up results are recorded in [SFTP acceptance](sftp-release.md).

## Deferred minors

- Recovery records identify remote artifacts by profile UUID/path without a non-secret endpoint snapshot. After profile retirement, artifact discovery needs improvement. Sources and existing destinations are retained; no cleanup/replay can target the wrong server.
- Activity Reveal/Show actions still pass remote URLs to Finder. Remote navigation or a copy-path action should replace those controls; they do not currently reveal remote items.

## Declined-to-judge ruling

SMB/WebDAV implementations, recursion, remote Move/Trash/replacement/relay, and remote previews remain later milestones. Their current rejection boundaries were reviewed. This bounded scope stands under the user's authorization; its cost is follow-up implementation for those workflows. No delivered SFTP behavior was excluded because the spec was silent.
