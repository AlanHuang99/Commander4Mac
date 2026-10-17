// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import NIOCore
@testable import NIOSSH

func makeCitadelPacketFixture() -> NIOSSHEncryptablePayload {
    .init(message: .ignore(.init(data: ByteBuffer(string: "fixture"))))
}
