# Commander4Mac distribution plan

User authorization: build and notarize a distributable DMG and review dependency licensing, inline without new approval handoffs. Base: fe834e8. Keep the existing development installation and identity. Scope is release packaging; no public upload or repository push is requested. The brief in this plan is the reachable specification.

## Task 1: License and source package

Inventory the exact pinned dependencies and actual dynamic linkage. Retain all original license/notice texts, including source-file licenses and attribution requirements. Generate a deterministic LGPL corresponding-source package with pinned AMSMB2/libsmb2 and local build dependencies, checksum manifest and rebuild/replacement instructions. Put notices and source in the signed app, with a native menu entry. Permit personal modifications and reverse engineering to debug LGPL changes without licensing unrelated app source. Keep hardened-runtime protections on distributed code. Verify an independently rebuilt modified framework can be installed into a personal copy and loaded. First show the present package fails missing-source/attribution checks, then pass those same checks with the new artifacts.

Interfaces: Resources/ThirdPartyNotices.txt, Resources/OpenSource, Resources/OpenSource/Dependencies.json and scripts consumed by the release archive.

Expected: exact source snapshots and required notices present, replacement demonstrated without changing the distributed app’s entitlements.

## Task 2: Release archive and DMG

Build a Developer ID Release archive, bundle com.alanhuang.Commander4Mac, version 1.0 build 1, with secure timestamps, hardened runtime, no debug entitlement, separate from the existing development app. Validate nested signatures and both architectures. Produce a reproducible DMG build script and fail closed on identity, license, source or signing errors. Test actual mounted bundle and layout.

Interfaces: Task 1 resources into archive; archive path into existing DMG builder. Versioned output in .build/distribution.

Expected: production signed archive and DMG, complete notices/source package, and a verified mounted app signature. Preserve the existing development installation.

## Task 3: Notarize and validate

Use a user-configured notarytool Keychain profile. Never expose credentials in logs or source. Submit app ZIP, inspect accepted status and complete notary log, staple/validate app, package and submit final DMG, inspect its log, staple/validate DMG. Run Gatekeeper and Apple distribution checks on the actual mounted app and final image. Do not call success before accepted tickets and validation. Persist submission IDs, hashes and evidence. If credentials remain unavailable, finish all other work and report that exact authentication dependency honestly.

Expected: accepted app and DMG submissions, stapled tickets, Gatekeeper acceptance and recorded checksums, or a concrete authentication blocker.

## Review Focus

Check LGPL source completeness, actual framework separation and replacement under signing; third-party source-file licenses and notices; fail-closed release validation; identity/version consistency; nested timestamps, debug entitlements and hardened runtime; accepted notary logs plus stapling; source archives free of secrets and developer metadata. Do not infer clean-machine or Intel execution from a local build.

## Completion

One fresh read-only final review and one correction pass for substantive findings. Keep the branch/worktree. No merge or push. Record evidence and remaining release limitations.
