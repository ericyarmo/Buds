//
//  CBOREncoder.swift
//  Buds
//
//  Canonical CBOR encoding for deterministic CIDs
//  Based on CANONICALIZATION_SPEC.md
//  Physics-tested: 0.11ms p50 latency (BudsKernelGolden)
//

import Foundation

/// Canonical CBOR encoder for receipt signing
/// Implements RFC 8949 with deterministic ordering
struct CanonicalCBOREncoder {

    /// Encode SessionPayload to canonical CBOR
    static func encode(_ payload: SessionPayload) throws -> Data {
        return try ReceiptCanonicalizer.encodeSessionPayload(payload)
    }

    /// Compute CID from canonical CBOR data
    /// CIDv1: multibase(base32) + multicodec(dag-cbor) + multihash(sha2-256)
    static func computeCID(from data: Data) -> String {
        // Compute SHA-256 hash
        let hash = SHA256.hash(data: data)
        let hashBytes = Data(hash)

        // Create multihash: 0x12 (sha2-256) + 0x20 (32 bytes) + hash
        var multihash = Data([0x12, 0x20])
        multihash.append(hashBytes)

        // Create CIDv1: 0x01 (version) + 0x71 (dag-cbor) + multihash
        var cidBytes = Data([0x01, 0x71])
        cidBytes.append(multihash)

        // Base32 encode (lowercase for CIDv1)
        let cid = "b" + base32Encode(cidBytes)

        return cid
    }
}

// MARK: - SHA256 Helper

import CryptoKit

extension SHA256 {
    static func hash(data: Data) -> SHA256Digest {
        return SHA256.hash(data: data)
    }
}

// MARK: - Base32 Encoding (RFC 4648)
// Lowercase alphabet for CIDv1 (matches BudsKernelGolden implementation)

private func base32Encode(_ data: Data) -> String {
    let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")
    var bits = 0
    var value: UInt32 = 0
    var out = ""

    for byte in data {
        value = (value << 8) | UInt32(byte)
        bits += 8
        while bits >= 5 {
            let idx = Int((value >> UInt32(bits - 5)) & 0x1F)
            out.append(alphabet[idx])
            bits -= 5
        }
    }

    if bits > 0 {
        let idx = Int((value << UInt32(5 - bits)) & 0x1F)
        out.append(alphabet[idx])
    }

    return out
}

// MARK: - Unsigned Preimage Pattern

/// Helper to create unsigned receipt preimage (for CID computation)
/// This avoids CID/signature circularity
struct UnsignedReceiptPreimage: Codable {
    let did: String
    let deviceId: String
    let parentCID: String?
    let rootCID: String
    let receiptType: String
    let payload: Data  // Encoded payload

    // Note: NO cid, NO signature fields
    // These are computed AFTER encoding this preimage
}

/// Helper to build unsigned preimage for SessionPayload receipts
extension UnsignedReceiptPreimage {
    static func buildSessionReceipt(
        did: String,
        deviceId: String,
        parentCID: String?,
        rootCID: String,
        receiptType: String,
        payload: SessionPayload
    ) throws -> UnsignedReceiptPreimage {
        let payloadData = try CanonicalCBOREncoder.encode(payload)

        return UnsignedReceiptPreimage(
            did: did,
            deviceId: deviceId,
            parentCID: parentCID,
            rootCID: rootCID,
            receiptType: receiptType,
            payload: payloadData
        )
    }
}
