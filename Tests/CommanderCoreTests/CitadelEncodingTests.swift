// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import XCTest
import NIOCore
import Crypto
import NIOSSH
@testable import Citadel

final class CitadelEncodingTests: XCTestCase {
    func testAESPacketHeaderGrowsAtBufferBoundaryAndRoundTrips() throws {
        let key = SymmetricKey(data: Array(repeating: UInt8(1), count: 16))
        let mac = SymmetricKey(data: Array(repeating: UInt8(2), count: 32))
        let keys = NIOSSHSessionKeys(initialInboundIV: Array(repeating: 0, count: 16),
            initialOutboundIV: Array(repeating: 0, count: 16), inboundEncryptionKey: key,
            outboundEncryptionKey: key, inboundMACKey: mac, outboundMACKey: mac)
        let cipher = try AES128CTR(initialKeys: keys, mac: "hmac-sha2-256")
        let payload = makeCitadelPacketFixture()
        var buffer = ByteBuffer(repeating: 0x5a, count: 256)
        buffer.moveWriterIndex(to: 253)
        try cipher.encryptPacket(payload, to: &buffer, sequenceNumber: 0)
        XCTAssertEqual(buffer.getBytes(at: 0, length: 253), Array(repeating: 0x5a, count: 253))
        var packet = try XCTUnwrap(buffer.getSlice(at: 253, length: buffer.writerIndex - 253))
        try cipher.decryptFirstBlock(&packet)
        let plaintext = try cipher.decryptAndVerifyRemainingPacket(&packet, sequenceNumber: 0)
        var expected = ByteBuffer()
        expected.writeEncryptablePayload(payload)
        XCTAssertEqual(plaintext, expected)
    }

    func testCompositeSSHStringPrefixGrowsAtBufferBoundary() throws {
        var buffer = ByteBuffer(repeating: 0x5a, count: 256)
        buffer.moveWriterIndex(to: 253)
        let written = buffer.writeCompositeSSHString { $0.writeString("ok") }
        XCTAssertEqual(written, 6)
        XCTAssertEqual(buffer.writerIndex, 259)
        XCTAssertEqual(buffer.getInteger(at: 253, as: UInt32.self), 2)
        XCTAssertEqual(buffer.getString(at: 257, length: 2), "ok")
    }

    func testSFTPPacketPrefixGrowsAtBufferBoundary() throws {
        var buffer = ByteBuffer(repeating: 0x5a, count: 256)
        buffer.moveWriterIndex(to: 253)
        try SFTPMessageSerializer().encode(data: .initialize(.init(version: .v3)), out: &buffer)
        XCTAssertEqual(buffer.writerIndex, 262)
        XCTAssertEqual(buffer.getInteger(at: 253, as: UInt32.self), 5)
        XCTAssertEqual(buffer.getInteger(at: 257, as: UInt8.self), 1)
        XCTAssertEqual(buffer.getInteger(at: 258, as: UInt32.self), 3)
    }

    func testSSHStringPrefixGrowsAtBufferBoundary() {
        var buffer = ByteBuffer(repeating: 0x5a, count: 256)
        buffer.moveWriterIndex(to: 253)
        buffer.writeSSHString("é")
        XCTAssertEqual(buffer.writerIndex, 259)
        XCTAssertEqual(buffer.getInteger(at: 253, as: UInt32.self), 2)
        XCTAssertEqual(buffer.getString(at: 257, length: 2), "é")
        XCTAssertEqual(buffer.getBytes(at: 0, length: 253), Array(repeating: 0x5a, count: 253))
    }
}
