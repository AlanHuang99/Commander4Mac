# Signed automatic updates from GitHub

## Intent and chosen approach

Add the standard macOS update experience used by Sonance, with GitHub Releases delivering updates. Use Sparkle 2.10.0, verified against its official release on October 17, 2026, pinned to its exact revision. A custom updater would duplicate download, signature, installation and relaunch machinery. A GitHub release asset at the stable latest-release appcast URL keeps both feed and binaries in the requested service without another hosting deployment.

## Runtime

Release builds embed Sparkle, a Commander4Mac-specific Ed25519 public key and HTTPS feed URL. Development and UI-test builds never start production update checks or install production over the development identity. Provide Check for Updates in the app menu and Updates settings, scheduled checks on by default and an optional automatic-download/install setting. Do not send system profiles. Use Sparkle's standard UI for releases/install/relaunch; do not interrupt active file operations. Defer installation/relaunch until operations finish and saved workspace state flushes, retaining the existing safe-quit behavior. Surface deferred/error state clearly.

Generate a separate Commander4Mac update-signing key, store private material outside Git with restricted permissions and recovery notes, and configure one encrypted release-environment secret. Never reuse or modify Sonance's update key, feed or repository. User authorization includes the new app-specific signing setup and release changes; OS authentication remains a user-only action if required.

## Release pipeline

Ship these features as version 1.1, build 2, preserving production bundle/team identity and universal macOS 15+ support. Sign all nested Sparkle helpers correctly, retain their necessary sandbox entitlements and verify every binary with existing trust gates. Update dependency notices and checks for the binary framework's included licenses. Sign the final stapled DMG with the update key and generate an appcast containing its exact version/build, length, signature, HTTPS GitHub release URL and macOS minimum. Include appcast.xml in the same release as the four existing artifacts. Missing/mismatched keys or malformed/unsigned feed entries must fail publication. Verify the published feed and archive using Sparkle tooling. Version 1.0 predates the updater and needs one manual installation of 1.1.

## Verification

Test update relaunch deferral against active operations and state flush, disabled development configuration, feed metadata/signatures and rejection of tampered artifacts with real official Sparkle tools. Perform an owned update probe/install test without replacing the user's development or production app. Run full core and native integration CI, one whole-change independent review, signed/notarized release checks, actual public-feed/download verification and installed-app UI acceptance. Do not claim a real upgrade was exercised from a probe alone.
