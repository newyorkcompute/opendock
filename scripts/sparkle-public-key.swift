import CryptoKit
import Foundation

// Prints the SUPublicEDKey for SPARKLE_PRIVATE_KEY.
//
// Sparkle 2.10's generate_keys exports one base64 line. Decoded, that is either a 32-byte
// Ed25519 seed (current format; see Sparkle common_cli/Secret.swift) or the legacy 96-byte
// blob whose last 32 bytes are the public key. CryptoKit derives the public key from the
// seed the same way RFC 8032 does, which is the format Sparkle kept the seed for.

guard let raw = ProcessInfo.processInfo.environment["SPARKLE_PRIVATE_KEY"]?
    .trimmingCharacters(in: .whitespacesAndNewlines),
    !raw.isEmpty
else {
    fputs("SPARKLE_PRIVATE_KEY is empty\n", stderr)
    exit(1)
}

guard let secret = Data(base64Encoded: raw) else {
    fputs("SPARKLE_PRIVATE_KEY is not base64\n", stderr)
    exit(1)
}

let publicKey: Data
switch secret.count {
case 32:
    do {
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: secret)
        publicKey = key.publicKey.rawRepresentation
    } catch {
        fputs("could not derive an Ed25519 public key from the 32-byte seed (\(error))\n", stderr)
        exit(1)
    }
case 96:
    publicKey = secret.suffix(32)
default:
    fputs(
        "SPARKLE_PRIVATE_KEY decoded to \(secret.count) bytes; Sparkle expects 32 (seed) or 96 (legacy)\n",
        stderr
    )
    exit(1)
}

print(publicKey.base64EncodedString())
