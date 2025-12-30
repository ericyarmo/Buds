//
//  ReceiptManager.swift
//  Buds
//
//  Core receipt creation, signing, and storage
//

import Foundation
import GRDB
import CryptoKit

actor ReceiptManager {
    static let shared = ReceiptManager()

    private let identity = IdentityManager.shared
    private let db = Database.shared

    // MARK: - Create Receipt

    /// Create and sign a new session receipt
    /// Returns (cid, signature) for the created receipt
    func createSessionReceipt(
        type: String,
        payload: SessionPayload,
        parentCID: String? = nil
    ) async throws -> (cid: String, signature: String) {

        // Get identity info
        let did = try await identity.getDID()
        let deviceId = try await identity.getDeviceID()

        // Determine rootCID
        let rootCID: String
        if let parentCID = parentCID {
            // This is an edit/delete - root is parent's root
            rootCID = try fetchRootCID(for: parentCID)
        } else {
            // New chain - root will be this CID (computed below)
            rootCID = "SELF"  // Placeholder
        }

        // Build unsigned preimage
        let preimage = try UnsignedReceiptPreimage.buildSessionReceipt(
            did: did,
            deviceId: deviceId,
            parentCID: parentCID,
            rootCID: rootCID,
            receiptType: type,
            payload: payload
        )

        // Encode to canonical CBOR
        let canonicalBytes = try ReceiptCanonicalizer.canonicalCBOR(preimage)

        // Compute CID
        let cid = try computeCID(from: canonicalBytes)

        // If this is a new chain, update rootCID to point to self
        let finalRootCID = rootCID == "SELF" ? cid : rootCID

        // Sign the canonical bytes
        let signatureData = try await identity.sign(data: canonicalBytes)
        let signature = signatureData.base64EncodedString()

        // Store in database
        try db.write { db in
            // Encode payload to JSON for querying
            let payloadJSON = try String(data: JSONEncoder().encode(payload), encoding: .utf8) ?? "{}"

            // Insert into ucr_headers
            try db.execute(
                sql: """
                    INSERT INTO ucr_headers (
                        cid, did, device_id, parent_cid, root_cid,
                        receipt_type, signature, raw_cbor, payload_json, received_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    cid, did, deviceId, parentCID, finalRootCID,
                    type, signature, canonicalBytes, payloadJSON, Date().timeIntervalSince1970
                ]
            )
        }

        print("✅ Created receipt: \(cid)")

        return (cid: cid, signature: signature)
    }

    /// Create and sign a reaction receipt (Phase 10.1 Module 1.5)
    /// Returns (cid, signature) for the created receipt
    func createReactionReceipt(
        type: String,
        payload: ReactionAddedPayload,
        parentCID: String? = nil
    ) async throws -> (cid: String, signature: String) {

        // Get identity info
        let did = try await identity.getDID()
        let deviceId = try await identity.getDeviceID()

        // Determine rootCID
        let rootCID: String
        if let parentCID = parentCID {
            rootCID = try fetchRootCID(for: parentCID)
        } else {
            rootCID = "SELF"  // Placeholder
        }

        // Build unsigned preimage
        let preimage = try UnsignedReceiptPreimage.buildReactionAddedReceipt(
            did: did,
            deviceId: deviceId,
            parentCID: parentCID,
            rootCID: rootCID,
            receiptType: type,
            payload: payload
        )

        // Encode to canonical CBOR
        let canonicalBytes = try ReceiptCanonicalizer.canonicalCBOR(preimage)

        // Compute CID
        let cid = try computeCID(from: canonicalBytes)

        // If this is a new chain, update rootCID to point to self
        let finalRootCID = rootCID == "SELF" ? cid : rootCID

        // Sign the canonical bytes
        let signatureData = try await identity.sign(data: canonicalBytes)
        let signature = signatureData.base64EncodedString()

        // Store in database
        try db.write { db in
            // Encode payload to JSON for querying
            let payloadJSON = try String(data: JSONEncoder().encode(payload), encoding: .utf8) ?? "{}"

            // Insert into ucr_headers
            try db.execute(
                sql: """
                    INSERT INTO ucr_headers (
                        cid, did, device_id, parent_cid, root_cid,
                        receipt_type, signature, raw_cbor, payload_json, received_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    cid, did, deviceId, parentCID, finalRootCID,
                    type, signature, canonicalBytes, payloadJSON, Date().timeIntervalSince1970
                ]
            )
        }

        print("✅ Created reaction receipt: \(cid)")

        return (cid: cid, signature: signature)
    }

    // MARK: - Verify Receipt

    /// Verify receipt signature
    func verifyReceipt(cid: String) async throws -> Bool {
        let row = try db.read { db in
            try UCRHeaderRow.fetchOne(
                db,
                sql: "SELECT * FROM ucr_headers WHERE cid = ?",
                arguments: [cid]
            )
        }

        guard let row = row else {
            throw ReceiptError.notFound
        }

        // Extract public key from DID
        // did:buds:<base58> -> decode base58 to get first 20 bytes of pubkey
        // For now, we'll skip full verification (need to store pubkeys)

        // Verify signature matches canonical bytes
        let signatureData = Data(base64Encoded: row.signature)!

        // TODO: Full signature verification
        // Would need to store Ed25519 public keys in a separate table

        return true  // Placeholder
    }

    /// Verify receipt signature with provided public key (Phase 7 - for received memories)
    func verifyReceipt(cborData: Data, signature: String, publicKey: Curve25519.Signing.PublicKey) throws -> Bool {
        print("🔐 [ReceiptManager] Verifying signature...")
        print("🔐 [ReceiptManager] CBOR size: \(cborData.count) bytes")
        print("🔐 [ReceiptManager] Signature: \(signature.prefix(20))...")

        // Decode signature from base64
        guard let signatureData = Data(base64Encoded: signature) else {
            print("❌ [ReceiptManager] Invalid signature format (not base64)")
            throw ReceiptError.invalidSignature
        }

        print("🔐 [ReceiptManager] Signature data size: \(signatureData.count) bytes (expected: 64)")

        // Verify Ed25519 signature over canonical CBOR bytes
        let isValid = publicKey.isValidSignature(signatureData, for: cborData)

        if isValid {
            print("✅ [ReceiptManager] Signature verification PASSED")
        } else {
            print("❌ [ReceiptManager] Signature verification FAILED")
        }

        return isValid
    }

    // MARK: - Helpers

    /// Compute CID from canonical CBOR bytes
    /// Used for receipt creation and verification of received receipts
    func computeCID(from canonicalBytes: Data) -> String {
        return CanonicalCBOREncoder.computeCID(from: canonicalBytes)
    }

    private func fetchRootCID(for cid: String) throws -> String {
        try db.read { db in
            if let rootCID = try String.fetchOne(
                db,
                sql: "SELECT root_cid FROM ucr_headers WHERE cid = ?",
                arguments: [cid]
            ) {
                return rootCID
            } else {
                throw ReceiptError.parentNotFound
            }
        }
    }
}

// MARK: - Errors

enum ReceiptError: Error, LocalizedError {
    case notFound
    case parentNotFound
    case invalidSignature
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Receipt not found"
        case .parentNotFound:
            return "Parent receipt not found"
        case .invalidSignature:
            return "Invalid receipt signature"
        case .encodingFailed:
            return "Failed to encode receipt"
        }
    }
}
