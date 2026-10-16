# SFTP phase decisions, October 16, 2026

- Ruling: Existing user authorization replaces new spec/plan approval handoffs. Reason: the user repeatedly requested inline implementation without permission questions. Cost if wrong: the user may redirect scope after implementation begins.
- Ruling: Deliver SFTP first with individual regular-file copies. SMB, WebDAV, recursive transfers, and remote destructive actions remain subsequent milestones. Reason: establish a testable transfer boundary. Cost if wrong: those workflows require follow-up work.
- Ruling: Reuse the attached isolated worktree and branch. Reason: preserve the already installed local implementation. Cost if wrong: phases share a checkout and may need later separation.
- Ruling: Rotate profile IDs when the endpoint, authentication scope, or established host key changes. Reason: old tabs and queued requests must never retarget to another identity. Cost if wrong: old tabs must be reopened from the new connection.
- Ruling: Copy file contents only over SFTP; retain sources and explicitly disclose that permissions, timestamps, xattrs, and resource forks are not preserved. Reason: the first transport has no portable metadata contract. Cost if wrong: users must manage metadata separately.
- Ruling: Own the TCP channel and adapt the library's event-loop boundary. Reason: real tests exposed an unclosed failed-handshake connection and native Debug exposed an off-loop handler assertion. Cost if wrong: this narrow lifecycle adapter needs maintenance against the pinned dependency.

- Ruling: Run core tests in Debug by default while keeping UI hosts in their separate UITest identity. Reason: the custom UITest configuration optimized dependency assertions away and missed a real installed Debug crash. Cost if wrong: test builds take longer and use more debug resources.

Final review and deferred findings will be recorded here after the one independent review.
