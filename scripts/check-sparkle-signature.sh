#!/usr/bin/env bash
set -euo pipefail

PUBLIC_KEY="${1:?Usage: check-sparkle-signature.sh public-key signature file}"
SIGNATURE="${2:?Usage: check-sparkle-signature.sh public-key signature file}"
FILE="${3:?Usage: check-sparkle-signature.sh public-key signature file}"

swift - "$PUBLIC_KEY" "$SIGNATURE" "$FILE" <<'SWIFT'
import CryptoKit
import Foundation

guard CommandLine.arguments.count == 4,
      let publicBytes = Data(base64Encoded: CommandLine.arguments[1]),
      let signature = Data(base64Encoded: CommandLine.arguments[2]) else {
    fputs("ERR: invalid Sparkle public key or signature encoding\n", stderr)
    exit(2)
}

do {
    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicBytes)
    let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
    guard publicKey.isValidSignature(signature, for: archive) else {
        fputs("ERR: Sparkle signature does not match the app's public key\n", stderr)
        exit(1)
    }
    print("  ✓ Sparkle signature verifies against the app's update key")
} catch {
    fputs("ERR: could not verify Sparkle signature: \(error)\n", stderr)
    exit(1)
}
SWIFT
