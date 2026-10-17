# GitHub publication acceptance

Repository: https://github.com/AlanHuang99/Commander4Mac

## Setup

Public repository with `main` as the publication branch, README with an actual app screenshot containing demonstration files only, download/install/Full Disk Access guidance, contributor/security/release docs, changelog, issue/PR templates and monthly Actions dependency updates. Original code is GPLv3 with the Citadel/CCitadelBcrypt permission in `LICENSE-EXCEPTION`; both texts are bundled and verified. Upstream licenses and acknowledgement are retained.

The `release` environment accepts `v*` tags only. Seven encrypted environment secrets configure the existing Developer ID identity and notarization API key. Secret values were sent through stdin, not logged or committed. Temporary certificate export/password were removed. The original private key and installed development app were preserved. Default workflow tokens are read-only; only the trusted release job requests write permission. Actions are restricted to official GitHub actions with pinned commits. Private vulnerability reporting and dependency alerts are enabled.

## Local validation and review

- All 38 commits through the release source were scanned with Gitleaks. Initial matches were verified public upstream Citadel parser/test/example bytes and generated upstream license/source hashes. Only exact historical fingerprints are excepted; no broad path exclusions.
- Local native core: 160 tests, 20 opt-in skips, zero failures. Owned SMB, WebDAV, OpenSSH SFTP and APFS cross-volume checks passed. Unsigned universal Release build and bundled source/license checks passed.
- Fourteen Python publication/release regressions pass normally and under optimized Python. actionlint, shell syntax and documentation relative-link checks passed.
- Fresh independent review identified Bash 3.2 empty-array failures and the original BSD/GPL linking conflict, plus future-version test brittleness and missing rejected-notary diagnostics. One correction pass addressed all four with negative/positive tests. Core and wait scripts are exercised with the system `/bin/bash`; no second review was dispatched.

Hosted CI and public downloadable release verification are recorded below. Local tests do not establish clean-machine onboarding acceptance.

## First hosted-run finding

CI run `38984297958` caught a real Citadel buffer-capacity trap in SFTP on Apple Silicon. A deterministic local boundary test reproduced the exact writer-index 257/capacity 256 failure. Four unreserved prefix writers now write initialized placeholders that grow the buffer before encoding data. Four boundary tests verify SSH strings, composite strings, SFTP framing and an AES encrypted packet round trip. The AES test also reproduced its original 258/capacity 256 trap before the fix. Local core now passes 164 tests (20 opt-in skips), and all six real OpenSSH fixture tests pass. Test fixture cleanup restores owner permissions before removing deliberately denied test directories after a crash.

## Hosted acceptance

[CI run 38985166979](https://github.com/AlanHuang99/Commander4Mac/actions/runs/38985166979) passed on commit `e2372ad364f9b82f503f1a7d2a20b30a21a4b9f1`, with native Apple Silicon (`macos-26`) and Intel (`macos-15-intel`) jobs. The actual completed job logs confirm 164 core tests with 20 opt-in skips, eight SMB tests, six WebDAV tests, six OpenSSH SFTP tests and one APFS cross-volume test, all with zero failures. Both jobs passed the 14 Python regressions normally and optimized, unsigned universal Release builds, and source/license validation.

The clean source commit matched remote `main` before the annotated `v1.0` tag was created and pushed. [Release run 38987468660](https://github.com/AlanHuang99/Commander4Mac/actions/runs/38987468660) passed both tag-specific native CI jobs, then built, signed, notarized, stapled, validated and published the production distribution. Temporary signing-credential cleanup passed before publication. The complete release run succeeded at `2026-10-17T01:11:54Z` (October 16 in the local Eastern time zone).

The public repository and README were also inspected in an unauthenticated browser. The chosen icon, demonstration-only app screenshot, links and installation guidance rendered correctly.

## Published release and actual-download verification

[Commander4Mac 1.0](https://github.com/AlanHuang99/Commander4Mac/releases/tag/v1.0) is a public, non-prerelease release, published by GitHub Actions at `2026-10-17T01:11:50Z`. It includes the DMG, portable checksum, LGPL source archive and third-party notices, plus GitHub's source archive links. The release page and all four explicit assets were also visible without signing in.

Apple returned `Accepted` for both submissions; the downloaded full notary logs contain `issues: null`:

| Submission | ID | Result |
| --- | --- | --- |
| App archive | `fb28e145-8ef5-48b7-a5d6-a72f3ea0f27a` | Accepted, app stapled and validated |
| Disk image | `5f193436-d9eb-4a93-b608-26f596bd110a` | Accepted, DMG stapled and validated |

All four public assets were downloaded again after publication. The final stapled `Commander4Mac-1.0.dmg` is **14,640,948 bytes**, SHA-256 **`b84abf5f6a4d5f140d6f39253c046ccd0e1b3a47805d8b62cbc8e292b8f4118b`**. This matches both the downloaded checksum and GitHub's published asset digest. Submission hashes precede stapling and are not the final DMG checksum.

The actual downloaded image passed strict code-signature verification, stapler validation, disk-image integrity verification and Gatekeeper assessment (`Notarized Developer ID`). It was mounted read-only in an owned temporary directory. The Applications shortcut and Finder layout were present. The actual mounted app passed production identity/version checks (`com.alanhuang.Commander4Mac`, version 1.0, build 1), universal arm64/x86_64 and every Mach-O slice's signing/runtime/UUID checks, license and LGPL source validation, app stapler validation, `syspolicy_check distribution` and Gatekeeper assessment. The separately downloaded LGPL archive and notices match their bundled app copies byte-for-byte. The owned image was then ejected and its temporary mount directory removed.

Logs, notarization JSON, workflow metadata and the machine-readable public-download receipt are retained locally under `.build`; the hosted release diagnostics artifact is retained for 14 days. This publication check did not install the production app, grant permissions or establish clean-machine first-launch acceptance. Those manual checks remain separate from the successful artifact and hosted CI checks.

## Installed development app

The existing `/Applications/Commander4Mac Dev.app` was refreshed with the verified SFTP correction while retaining its development identity and workspace. After observing no active operations, the app was quit normally, the signed build was installed at the same path and strict signature validation passed. The actual running executable path and UUID were checked; the two-pane workspace restored, and Cmd-K opened the connection sheet and cancelled normally. No system permissions were reset. This UI check does not establish new protected-folder or network access acceptance.
