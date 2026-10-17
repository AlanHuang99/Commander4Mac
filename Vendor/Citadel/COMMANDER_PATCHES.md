# Commander4Mac dependency snapshot

Upstream Citadel 0.12.1, commit ae8562f895de06ccb86fdb1cbb65fd99c8976e12, [repository](https://github.com/orlandos-nl/Citadel). MIT license retained in LICENSE. Commander4Mac changes to this snapshot use the same MIT terms; separate per-file third-party terms remain intact. Sources, Tests, Package.swift, and README.md came from the pinned SwiftPM checkout.

Commander patches add bounded READDIR, direct no-follow LSTAT, an 8 MiB SFTP frame limit, and initialized/growing length-prefix writes at buffer-capacity boundaries. The upstream public API cannot request these safely from a separate module. Rebase these small patches when updating the snapshot. The remaining source files match the pinned upstream snapshot.

Changed source files:

- Sources/Citadel/Errors.swift
- Sources/Citadel/SFTP/Client/SFTPClient.swift
- Sources/Citadel/SFTP/SFTPMessage.swift
- Sources/Citadel/SFTP/SFTPMessageParser.swift
- Sources/Citadel/ByteBufferHelpers.swift
- Sources/Citadel/SFTP/SFTPSerializer.swift
- Sources/Citadel/Algorithms/DH-Helpers.swift
- Sources/Citadel/Algorithms/AES.swift
