# Dependency licensing engineering review

As of October 16, 2026. Scope: exact SwiftPM pins, vendored Citadel changes, nested libraries and notices in the production archive. This records evidence and implemented distribution requirements rather than a guarantee about every jurisdiction or future release.

## Inventory and licenses

`Resources/OpenSource/Dependencies.json` records all 13 resolved/vendored components, revisions and upstream URLs. The corresponding original license files and source-file notices are collected without changing their text. ColorizeSwift is resolved for Citadel's example executable and is not a dependency of the shipped app target; including its MIT notice is conservative.

| Component | Root license / additional obligations |
| --- | --- |
| AMSMB2, revision 90737c486c9d1a6ed1c1d4307060587c7bb0dfec | LGPL 2.1 or later for the combined framework; individual Swift headers say MIT, while upstream README explicitly describes LGPL distribution due to embedded libsmb2 |
| libsmb2, revision aedafb2c8742c83188e27841e270fdaad6035d41 | LGPL 2.1 or later, with original embedded-source notices retained |
| Citadel 0.12.1 snapshot plus four recorded patches | MIT; embedded OpenBSD bcrypt uses ISC-style terms, and Blowfish source has BSD four-clause conditions |
| BigInt, ColorizeSwift | MIT |
| swift-asn1, swift-atomics, swift-collections, swift-crypto, swift-log, swift-nio, swift-nio-ssh, swift-system | Apache 2.0 root licenses and notices; additional embedded-source licenses and copyright notices retained |

The archive also embeds Apple's toolchain-provided Swift compatibility dylib, copied and signed by Xcode. It is a platform/toolchain runtime, not an additional SwiftPM pin or modified third-party checkout. No Xcode toolchain is redistributed.

## Findings and remediation

The previous development preview included root license texts but did not carry the corresponding LGPL sources or all embedded-source acknowledgements. The pre-change checks failed for the absent source kit, absent Blowfish conditions and absent advertising attribution. The release now bundles complete AMSMB2 and its libsmb2 submodule, original build files, two local Swift package dependencies, license texts, a revision inventory, and a SHA-256 manifest covering 471 files. These accompany the binary rather than relying on a future written offer or an upstream branch remaining available.

All original license/notice files and relevant source-file license prefixes are collected, including Citadel's OpenBSD code, libsmb2 crypto sources, and NIO's llhttp license. Original upstream whitespace is preserved. The combined notices are present at the top resource level and in OpenSource. GNU LGPL 2.1 sections 4 and 6 require corresponding source and an appropriate application/library arrangement; the actual binaries use `CommanderCore -> @rpath/AMSMB2.framework`, with `_smb2_init_context` defined in AMSMB2 rather than copied into CommanderCore. See the [license text](https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html).

The personal-use modification and reverse-engineering permission for debugging library changes is explicit. The source kit includes offline rebuild and replacement instructions. No new open-source license is applied to unrelated application code. The shipped app keeps hardened runtime and library validation; a user modifies and re-signs a separate personal copy. Apple's [library-validation rules](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.disable-library-validation) explain the signing constraint. No distribution runtime exception was added.

The BSD advertising acknowledgement appears in About, the combined notices, installation artwork and README: This product includes software developed by Niels Provos. Future advertising mentioning features or use of the included software must retain the acknowledgement. The authors' names must not be used to endorse derived products.

## Verification

- The kit was extracted into an owned test directory. A marker function was added only to that test's libsmb2 source, then the included rebuild script built a fresh framework using local dependencies. No remote checkout was needed. The first probe exposed a SwiftPM output-layout assumption, fixed by querying `--show-bin-path`.
- The modified framework exported the new marker and original SMB API. A ctypes probe verified the marker, authenticated to an owned loopback SMB2 server and listed the Unicode fixture filename. The server and disposable data were cleaned afterward.
- The replacement script installed the modified framework into a personal copy of the production app and ad-hoc signed that copy. It launched natively. `vmmap` of the exact running executable confirmed the replacement framework was mapped. About displayed version 1.0 (1) and the acknowledgement; Open Source Components opened the actual resource folder with all five source/license files. The copy was quit, unregistered, and moved to Trash with a restore manifest. The production archive and installed development app were preserved.
- The validator checked 13 component records and 471 source-file hashes. A deliberately corrupted source archive was rejected. The actual production bundle passed source/license validation, dynamic linkage inspection, nested deep strict signature checks and runtime-entitlement checks. Further final release results belong in the distribution acceptance record.

Ignored logs under `.build/logs`: `lgpl-rebuild-final.log`, `lgpl-replacement-proof.log`, `lgpl-personal-sign.log`, `lgpl-personal-runtime.log`, and `release-verification.log`. The generated source kit and inventory are committed with the app resources. Re-run preparation and validation after any dependency, source, notice or build-script change.
