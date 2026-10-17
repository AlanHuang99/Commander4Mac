# Automatic Updates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans inline as already requested. Steps use checkbox syntax.

**Goal:** Ship Commander4Mac 1.1 with signed automatic updates from GitHub Releases.
**Architecture:** Sparkle owns update UI/install. App-specific relaunch coordination protects file operations and workspace persistence. Existing trusted release gates add update signing and a release-hosted appcast.
**Tech Stack:** Sparkle 2.10.0, XcodeGen, SwiftUI/AppKit, Python, GitHub Actions and Apple notarization.
**Spec:** `docs/superpowers/specs/2026-10-17-automatic-updates-design.md`

## Global Constraints

- Version 1.1/build 2; production `com.alanhuang.Commander4Mac`, team `66LBY954DT`, macOS 15+, universal arm64/x86_64.
- Separate new Commander4Mac update key; private key never enters Git, logs or release assets.
- Feed is `https://github.com/AlanHuang99/Commander4Mac/releases/latest/download/appcast.xml`; archives remain in GitHub Releases.
- Development/UI-test apps cannot start production updates. Active operations and state flush gate installation/relaunch.
- Preserve third-party licenses, LGPL replacement support and original installed app data/permissions. Standing authorization covers encrypted setup and publication.

## Review Focus

- Active/just-starting file operations must not be interrupted by updater relaunch.
- Development apps and test feeds must never replace the user's production/development installation.
- Signed feed metadata must match final stapled archive bytes/version/build and minimum OS.
- Missing/wrong signing key, tampered archive or invalid feed must fail verification/publication.
- Sparkle's nested helper signing/entitlements and cleanup must survive archive/notarization.

### Task 1: Sparkle runtime and safe relaunch

**Files:** `project.yml`, generated project/plist/resolved pins; new `Sources/Commander4Mac/Updates/*`, `Sources/CommanderCore/Services/UpdateRelaunchCoordinator.swift`, core tests; app commands/delegate/services/settings; license preparation resources.
**Interfaces:** `UpdateRelaunchCoordinator` accepts active operation count and an async flush before releasing a deferred install callback. `UpdaterController` exposes check availability, automatic-check/download settings and deferred state; only production starts it.

- [ ] Write failing real coordination tests for active operations, drain/flush, repeated callbacks and cancellation/termination. Expected: missing coordinator behavior fails.
- [ ] Pin the official Sparkle revision; generate a separate update key with restricted local storage and encrypted release secret. Implement production-only updater/menu/settings and safe relaunch coordination using documented delegate APIs.
- [ ] Build and test runtime integration; update license resources and nested-signature validation. Expected: core suite, native builds and actual nested signatures pass; Dev cannot invoke production updates. Commit runtime and key-free configuration.

### Task 2: Signed feed, release automation and delivery

**Files:** new `script/update_feed.py` and regression tests, release/signing/notarization scripts/workflow, release docs/README/changelog and acceptance record.
**Interfaces:** Generate `appcast.xml` from validated project metadata, final DMG and official Sparkle signature output. Trusted CI consumes `SPARKLE_ED_PRIVATE_KEY` in the existing release environment and publishes feed alongside current assets only after all gates pass.

- [ ] Write behavior tests for feed version/build/length/URL, malformed metadata, absent/wrong keys and tampered archive. Expected: missing feed/signature gate fails. Verify with real official Sparkle tools rather than text assertions.
- [ ] Implement signing/feed pipeline, required secret validation and temporary-key cleanup. Add Sparkle nested signing/entitlement handling and preserve existing notary/publication gates. Update version/build, release docs and notices.
- [ ] Run core/Python/protocol/native UI checks, an owned Sparkle probe/install exercise and one fresh independent review across all three plans. Correct material findings with failing regression tests. Expected: full suite and owned real update flow pass.
- [ ] Publish main and validated v1.1 tag, inspect hosted CI/release, download actual public feed/assets, verify Ed25519 signature and mounted app trust, install the new Dev build safely and record exact outcomes. Expected: accepted/stapled production artifacts and usable update feed; disclose one manual 1.0-to-1.1 install and any unexercised acceptance explicitly.
