// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.
import Foundation
import CryptoKit

do {
    guard CommandLine.arguments.count == 4,
          let publicBytes = Data(base64Encoded: CommandLine.arguments[1]),
          let signature = Data(base64Encoded: CommandLine.arguments[3]) else { exit(2) }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicBytes)
    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]), options: .mappedIfSafe)
    guard key.isValidSignature(signature, for: data) else { exit(1) }
} catch { exit(2) }
