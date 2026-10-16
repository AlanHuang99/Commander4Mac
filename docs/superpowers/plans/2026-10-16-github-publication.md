# GitHub publication implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Execute inline as requested by the user.

**Goal:** Publish Commander4Mac with working CI, signed notarized releases and complete public documentation.

**Architecture:** Reuse the existing XcodeGen project and release gates. Separate unsigned CI from trusted-tag signing and notarization. Publish only artifacts that pass the existing mounted-image checks.

**Tech stack:** GitHub Actions and CLI, XcodeGen, Xcode, Python, notarytool, dmgbuild.

**Spec:** `docs/superpowers/specs/2026-10-16-github-publication-design.md`

## Global constraints

- Public `AlanHuang99/Commander4Mac`, default branch `main`, GPL-3.0 following Sonance.
- macOS 15+, universal arm64/x86_64, production `com.alanhuang.Commander4Mac`, team `66LBY954DT`.
- No credentials or local app state in Git, artifacts or logs. Preserve the installed development app.
- Preserve upstream notices, bundled LGPL source, and Niels Provos attribution.
- Standing user authorization supersedes new approval handoffs. Keep the active worktree; push/publish are now explicitly requested.

## Review focus

- Mismatched or malicious tag values must fail before credentials are imported.
- A rejected or stalled notary submission must not publish or silently resubmit.
- Pull requests must not receive signing secrets or write permissions.
- Failed signing must still clean runner credentials; no secret files in uploaded diagnostics.
- Published checksum must match actual downloadable bytes and the mounted app must pass trust checks.

### Task 1: Publication files and reusable release metadata

**Files:** `README.md`, `LICENSE`, `Resources/Commander4MacLicense.txt`, `CONTRIBUTING.md`, `SECURITY.md`, `CHANGELOG.md`, `docs/DEVELOPMENT.md`, `docs/RELEASING.md`, `.github/ISSUE_TEMPLATE/*`, `.github/PULL_REQUEST_TEMPLATE.md`, `.github/dependabot.yml`, `script/release_metadata.py`, `Tests/test_publication.py`.

**Interfaces:** Metadata comes from checked-in `project.yml`, producing validated version, build and tag. Public documentation points to GitHub's latest release and existing detailed acceptance records.

- [ ] Write negative tests for mismatched tags, malformed versions and missing/duplicate metadata; watch them fail.
- [ ] Implement metadata validation and remove hard-coded version assumptions from release/notary scripts. Preserve optional local output isolation.
- [ ] Add GPL text to root and app resources, user documentation, issue templates and contribution guidance. Check links and avoid unsupported claims.
- [ ] Run Python release/publication tests and license checks. Commit the publication foundation.

### Task 2: CI and release automation

**Files:** `.github/workflows/ci.yml`, `.github/workflows/release.yml`, `script/ci.sh`, `script/ci_release.sh`, `script/ci_signing.sh`, `script/test.sh`, `script/notarize.sh`, `Tests/Support/Network/requirements.txt`.

**Interfaces:** CI uses `COMMANDER_CI=1` for unsigned builds; release uses existing signing and notarization verifiers with metadata from Task 1. Keychain cleanup is a separate `always()` step. Notary wait is bounded and saved IDs are reused.

- [ ] Add a failing bounded-wait behavior test against an owned fake notary executable, then implement wait support.
- [ ] Add secret-free native CI and trusted tag release workflows with pinned official actions, timeouts and minimal permissions.
- [ ] Verify shell syntax, actionlint, Python regressions, actual local native tests and an unsigned build. Commit automation.
- [ ] One fresh read-only whole-change review, followed by one substantive correction pass with tests.

### Task 3: Publish and verify the GitHub release

**Files:** Repository settings, encrypted secrets and `docs/verification/github-publication.md`.

**Interfaces:** Task 2's trusted workflow consumes encrypted signing/API-key secrets. The release is `v1.0` matching existing app metadata, with a final notarized DMG and checksum.

- [ ] Audit tracked history for secret material. Create the public repository, configure metadata, labels, Actions permissions and encrypted release secrets. Preserve Sonance unchanged.
- [ ] Push `main`, run and inspect hosted CI on Apple Silicon and Intel; fix actual failures before tagging.
- [ ] Push the validated version tag, inspect the release workflow and finish notarization/publishing.
- [ ] Download the public DMG/checksum, compare bytes and validate signature, ticket, Gatekeeper and mounted app. Record actual outcomes and residual limitations.
