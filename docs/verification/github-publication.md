# GitHub publication acceptance

Repository: https://github.com/AlanHuang99/Commander4Mac

## Setup

Public repository with `main` as the publication branch, README with an actual app screenshot containing demonstration files only, download/install/Full Disk Access guidance, contributor/security/release docs, changelog, issue/PR templates and monthly Actions dependency updates. Original code is GPLv3 with the Citadel/CCitadelBcrypt permission in `LICENSE-EXCEPTION`; both texts are bundled and verified. Upstream licenses and acknowledgement are retained.

The `release` environment accepts `v*` tags only. Seven encrypted environment secrets configure the existing Developer ID identity and notarization API key. Secret values were sent through stdin, not logged or committed. Temporary certificate export/password were removed. The original private key and installed development app were preserved. Default workflow tokens are read-only; only the trusted release job requests write permission. Actions are restricted to official GitHub actions with pinned commits. Private vulnerability reporting and dependency alerts are enabled.

## Local validation and review

- All 36 pre-publication commits scanned with Gitleaks. Initial matches were verified public upstream Citadel parser/test/example bytes and generated upstream license/source hashes. Only exact historical fingerprints are excepted; no broad path exclusions.
- Local native core: 160 tests, 20 opt-in skips, zero failures. Owned SMB, WebDAV, OpenSSH SFTP and APFS cross-volume checks passed. Unsigned universal Release build and bundled source/license checks passed.
- Fourteen Python publication/release regressions pass normally and under optimized Python. actionlint, shell syntax and documentation relative-link checks passed.
- Fresh independent review identified Bash 3.2 empty-array failures and the original BSD/GPL linking conflict, plus future-version test brittleness and missing rejected-notary diagnostics. One correction pass addressed all four with negative/positive tests. Core and wait scripts are exercised with the system `/bin/bash`; no second review was dispatched.

Hosted CI and public downloadable release verification are recorded below after execution. Local tests do not establish clean-machine onboarding acceptance.
