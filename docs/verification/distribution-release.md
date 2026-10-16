# Commander4Mac 1.0 distribution acceptance

As of October 16, 2026. Version 1.0, build 1. Production bundle `com.alanhuang.Commander4Mac`, team `66LBY954DT`. The existing development installation remains separate and unchanged.

## Result

Apple accepted both the app ZIP and final DMG, with no issues in either downloaded notary log. Both tickets were stapled and validated. Gatekeeper accepted the app and image as Notarized Developer ID. The final image was mounted read-only; the actual inner app passed license/source checks, deep strict signatures, all architecture signing-policy checks, ticket validation, Gatekeeper and `syspolicy_check distribution`. The image checksum passed. The owned test mount was ejected.

| Item | Evidence |
| --- | --- |
| App submission | `28c7e91e-9f8e-49bc-9ac4-16d79eaea480`, Accepted |
| DMG submission | `ae03642b-021c-49e5-b12c-0bb9730200c2`, Accepted |
| Final image | `.build/distribution/Commander4Mac-1.0.dmg`, 14,446,569 bytes |
| Final SHA-256 | `f8e71073afd1ae8acbfe1ca3b1103f6dd1be13d89f242d96d1001e637970b0c9` |
| Source-kit SHA-256 | `682e96ecd63be7828e0a534e17f5964181f843127a5fb85f62847161754085c7` |
| Main arm64 UUID | `151AEF53-0DB0-3807-A584-EAF320A33A07` |
| Main x86_64 UUID | `255A79B4-8DFE-34B9-B99C-7B3667453B4F` |
| Main CDHash | `24cfa6c667c2116f8158c3a6a2187d11dde4ca76` |

The archive carries four signed Mach-O files, covering nine slices: arm64/x86_64 on the main executable, CommanderCore and AMSMB2, plus Apple's compatibility dylib with its additional arm64e slice. Each slice has a valid UUID, Developer ID Application authority, expected team and secure timestamp. Main-executable runtime protections and forbidden entitlement checks run for each architecture. The passive Apple compatibility library is not required to carry the executable's runtime flag. No debug or library-validation exception was added to the distribution.

## Licensing and replacement

The [dependency review](dependency-licensing.md) records 13 components, preserved notices, advertising acknowledgement and the corresponding-source approach. The signed app includes 471 hashed LGPL source/build files, exact revisions, offline rebuild and replacement scripts, and discoverable licenses. A modified independently rebuilt framework authenticated and listed Unicode content against an owned SMB server. A personal app copy launched with that replacement mapped; About and the license-folder action were checked natively. That copy was quit, unregistered and moved to Trash with a restore manifest. The official archive was not modified by the replacement test.

The initial package checks reproduced missing source/attribution; the initial production archive exposed missing version metadata. Both were fixed. A source-kit rebuild probe exposed a current SwiftPM output-path assumption; the tested script now queries `--show-bin-path`. The final source kit remains byte-identical to the one in the submitted and stapled app.

## Independent review and correction

One fresh read-only review examined `fe834e8..97bca84`. It found no Critical issues and four Important release-guard issues. One correction pass addressed all four:

1. Production assertions could disappear under Python optimization, including the notary-log gate. A real missing-attribution test first passed incorrectly with `PYTHONOPTIMIZE=1`. Validators now use unconditional checks; invalid notary logs are rejected by a dedicated unconditional verifier.
2. Untracked library inputs could compile without entering the source archive. An actual added Swift build input was initially accepted and omitted. The generator now rejects untracked inputs and relevant ignored build inputs. Tests use disposable real Git repositories to cover both cases, leaving package-cache metadata alone.
3. Policy checks previously examined the host architecture and did not enforce Developer ID authority. The verifier now reads signing details and entitlements explicitly for every slice and requires Developer ID Application. Focused negative tests cover a development certificate, missing executable runtime and debug entitlement; the actual archive passes all nine slices.
4. A fresh checkout failed before resolving dependencies. The documented release command now resolves locked packages/submodules before source preparation. An actual fresh-cache snapshot ran that preparation entrypoint, resolved the pinned sources and generated the identical LGPL kit. It did not reuse a project `.build` cache.

Six focused regression tests pass. The fresh-checkout preparation test and optimized-Python validation of the actual release archive also pass. The accepted app/DMG workflow then ran the corrected guards. No second independent review was requested.

## Credentials and release scope

Notarization initially failed because the requested local Keychain profile did not exist. At the user's request, the existing Sonance/MacConnect key file and matching active Apple key metadata were located. Apple validated those existing credentials, which were stored using notarytool under profile `Commander4Mac-notary`. Private setup notes were saved in the user's private Apple documents folder, outside this repository. No credential body was printed or committed, and no new Apple key or access scope was created.

The native production DMG preview showed the correct production app name, Applications symlink, selected icon, clear drag instruction, minimum OS label and required acknowledgement. This phase prepares the signed/notarized distributable; no public hosting, GitHub release, merge or push was performed. Retain the acknowledgement in future advertising. No clean-machine installation, Intel hardware execution, new production Full Disk Access/Local Network grant, or broad NAS interoperability is inferred from these checks. The universal build and trust checks are the evidence actually obtained.

## Reproduction and evidence

See [production workflow](../../Packaging/DISTRIBUTION.md). Logs under `.build/logs`: `release-build-final.log`, `release-nine-slices.log`, `release-gates-red.log`, `release-gates-final.log`, `release-fresh-cache.log`, `release-fresh-result.log`, `lgpl-rebuild-final.log`, `lgpl-personal-runtime.log`, `notary-app-submit.log`, `notary-app-finish.log`, `notary-dmg-submit.log` and `notary-dmg-finish.log`. Raw accepted status/log JSON and upload hashes are in `.build/distribution/notarization`. The final portable `.sha256` file names the DMG by basename. A byte-identical delivery copy, checksum and public installation README are in `~/Downloads/Commander4Mac-1.0`; the copied image passed ticket, signature, Gatekeeper and checksum verification.
