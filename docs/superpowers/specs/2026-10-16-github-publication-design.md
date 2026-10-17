# GitHub publication

The user requests publishing Commander4Mac and setting up CI, release automation and documentation like `AlanHuang99/sonance`. Their standing authorization covers creating a public repository, configuring encrypted GitHub Actions secrets, pushing source and publishing the release. Execute inline without permission handoffs.

## Outcome

- Public `AlanHuang99/Commander4Mac`, default branch `main`, GPL-3.0 following Sonance, with the additional Citadel/CCitadelBcrypt linking permission in LICENSE-EXCEPTION. Upstream licenses retain their own terms.
- A user-facing README with the selected icon, download link, installation and Full Disk Access instructions, features, keyboard shortcuts and accurate limitations. Contributor, security, release and issue guidance accompany it.
- CI runs without distribution credentials on pushes and pull requests. Native Apple Silicon and Intel jobs build and run core tests. Owned loopback SMB/WebDAV fixtures exercise integration; SFTP and cross-volume fixtures run where supported. Release validation and unsigned universal Release builds also run.
- A protected release path runs on version tags and manual dispatch of an existing version tag. The tag must match checked-in marketing metadata. Only this repository's trusted version tags receive release secrets.
- Release automation imports the existing Developer ID identity into an ephemeral runner keychain, uses the existing Apple API key, signs a universal archive, verifies corresponding source and signatures, notarizes/staples the app, creates/notarizes/staples the DMG, validates the mounted app, then publishes the DMG and a portable checksum. Publish only after every gate passes.
- GitHub release notes include installation, macOS 15+, Full Disk Access, licensing/source and the required Niels Provos acknowledgement. Downloads never instruct users to disable Gatekeeper.

## Implementation boundaries

Use existing build/notary/DMG scripts rather than a separate CI-only packaging implementation. Remove fixed-version assumptions from reusable checks while preserving the current 1.0 metadata. Keep the installed development app and its signing identity untouched. No Sparkle integration or application feature changes are part of this publication task.

Retain existing history after checking it for secret material; do not publish credentials, signing archives, local state or fixture artifacts. Signing credentials are uploaded directly to encrypted repository secrets without logging values. Temporary exports are owner-only and removed after setup. Keep the private recovery notes outside Git and update them with the repository setup.

## Verification

Use real negative tests for tag/version validation and bounded notary waiting. Run the existing release-gate suite, local native core tests, shell/YAML checks and a fresh GitHub Actions run. Inspect failures and fix them before tagging. Verify the published release asset by downloading it, comparing SHA-256 and validating its ticket and Gatekeeper assessment. A hosted native Intel test run provides Intel evidence; it does not substitute for manual clean-machine onboarding acceptance.

## Decisions

Adopt Sonance's GPLv3 licensing and public repository model. Prefer the current build scripts and GitHub CLI over copying Sonance's older workflow literally. Use pinned official actions, minimal permissions, bounded jobs and cleanup that runs on failure. GitHub Actions holds signing secrets only in the release job, never fork pull requests. Do not copy Sonance's Sparkle key or alter Sonance's repository.
