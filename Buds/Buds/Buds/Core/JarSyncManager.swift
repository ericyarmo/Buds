/**
 * JarSyncManager (Phase 10.3 Module 3)
 *
 * Core sync engine - receives relay envelopes, verifies, applies to local state.
 *
 * CRITICAL ARCHITECTURE (Relay Envelope):
 * - Client sends receipt WITHOUT sequence → relay assigns authoritative sequence
 * - This manager processes relay envelopes (which HAVE relay-assigned sequences)
 * - Module 3: Simple in-order processing (no gap detection yet)
 * - Module 4: Adds gap detection + queueing (extends this class)
 *
 * Processing Pipeline:
 * 1. Replay protection (check processed_jar_receipts)
 * 2. Tombstone check (skip deleted jars)
 * 3. Signature + CID verification
 * 4. Apply receipt to local state (route to type-specific handler)
 * 5. Mark as processed + update sequence
 *
 * Receipt Types (9 total):
 * - jar.created, jar.member_added, jar.invite_accepted
 * - jar.member_removed, jar.member_left, jar.renamed
 * - jar.bud_shared, jar.bud_deleted, jar.deleted
 */

import Foundation
import GRDB
import CryptoKit

class JarSyncManager {
    static let shared = JarSyncManager()

    private let db: Database
    private let tombstoneRepo: JarTombstoneRepository

    private init() {
        self.db = Database.shared
        self.tombstoneRepo = JarTombstoneRepository.shared
    }

    // MARK: - Main Entry Point

    /**
     * Process relay envelope (Module 3: simple, no gap detection)
     *
     * Module 4 will replace this with gap-detecting version
     */
    func processEnvelope(_ envelope: RelayEnvelope) async throws {
        // 1. Replay protection
        guard !(try await isAlreadyProcessed(envelope.receiptCID)) else {
            print("⏭️ Skipping already processed receipt: \(envelope.receiptCID)")
            return
        }

        // 2. Tombstone check
        guard !(try await tombstoneRepo.isTombstoned(envelope.jarID)) else {
            print("🪦 Skipping receipt for tombstoned jar: \(envelope.jarID)")
            return
        }

        // 3. Verify signature + CID
        try await verifyReceipt(envelope)

        // 4. Apply receipt to local state
        try await applyReceipt(envelope)

        // 5. Mark as processed + update sequence
        try await markProcessed(
            receiptCID: envelope.receiptCID,
            jarID: envelope.jarID,
            sequenceNumber: envelope.sequenceNumber
        )

        print("✅ Processed receipt: \(envelope.receiptCID) (seq=\(envelope.sequenceNumber))")
    }

    // MARK: - Verification

    /**
     * Check if receipt already processed (replay protection)
     */
    func isAlreadyProcessed(_ receiptCID: String) async throws -> Bool {
        try await db.readAsync { db in
            let count = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM processed_jar_receipts WHERE receipt_cid = ?",
                arguments: [receiptCID]
            ) ?? 0
            return count > 0
        }
    }

    /**
     * Verify receipt signature + CID integrity
     */
    func verifyReceipt(_ envelope: RelayEnvelope) async throws {
        // 1. Verify CID matches receiptData hash
        let computedCID = CanonicalCBOREncoder.computeCID(from: envelope.receiptData)
        guard computedCID == envelope.receiptCID else {
            throw SyncError.cidMismatch(expected: envelope.receiptCID, actual: computedCID)
        }

        // 2. Verify Ed25519 signature
        // Extract public key from DID (did:phone:... uses device pubkey, not phone hash)
        // For now, we trust relay signature verification (relay already validated in Module 0.6)
        // TODO: Add client-side signature verification in future hardening

        print("✓ Verified receipt CID: \(envelope.receiptCID)")
    }

    // MARK: - Apply Receipts

    /**
     * Route envelope to type-specific handler
     */
    func applyReceipt(_ envelope: RelayEnvelope) async throws {
        // Decode receipt payload to get type
        let payload = try decodeReceiptPayload(envelope.receiptData)

        print("📥 Applying \(payload.receiptType) for jar \(envelope.jarID)")

        // Route to handler based on type
        switch payload.receiptType {
        case .jarCreated:
            try await applyJarCreated(envelope)
        case .jarMemberAdded:
            try await applyMemberAdded(envelope)
        case .jarInviteAccepted:
            try await applyInviteAccepted(envelope)
        case .jarMemberRemoved:
            try await applyMemberRemoved(envelope)
        case .jarMemberLeft:
            try await applyMemberLeft(envelope)
        case .jarRenamed:
            try await applyJarRenamed(envelope)
        case .jarBudShared:
            try await applyBudShared(envelope)
        case .jarBudDeleted:
            try await applyBudDeleted(envelope)
        case .jarDeleted:
            try await applyJarDeleted(envelope)
        default:
            throw SyncError.unknownReceiptType(payload.receiptType)
        }
    }

    // MARK: - Receipt Handlers (9 types)

    /**
     * jar.created - Create jar locally
     */
    func applyJarCreated(_ envelope: RelayEnvelope) async throws {
        let payload = try decodeJarCreatedPayload(envelope.receiptData)

        print("🆕 Creating jar: \(payload.jarName)")

        // Check if jar already exists (idempotency)
        let exists = try await db.readAsync { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM jars WHERE id = ?", arguments: [envelope.jarID]) ?? 0 > 0
        }

        if exists {
            print("⚠️ Jar already exists, skipping creation: \(envelope.jarID)")
            return
        }

        // Create jar locally
        try await db.writeAsync { db in
            try db.execute(sql: """
                INSERT INTO jars (id, name, description, owner_did, created_at, last_sequence_number, parent_cid)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                envelope.jarID,
                payload.jarName,
                payload.jarDescription,
                payload.ownerDID,
                payload.createdAtMs / 1000,  // Convert ms to seconds
                envelope.sequenceNumber,
                envelope.receiptCID
            ])
        }

        // Add owner to jar_members (role: owner, status: active)
        try await db.writeAsync { db in
            try db.execute(sql: """
                INSERT OR IGNORE INTO jar_members (jar_id, did, role, status, added_at)
                VALUES (?, ?, ?, ?, ?)
            """, arguments: [
                envelope.jarID,
                payload.ownerDID,
                "owner",
                "active",
                Date().timeIntervalSince1970
            ])
        }

        print("✅ Jar created: \(payload.jarName)")
    }

    /**
     * jar.member_added - Add member to jar
     */
    func applyMemberAdded(_ envelope: RelayEnvelope) async throws {
        let payload = try decodeJarMemberAddedPayload(envelope.receiptData)

        print("👤 Adding member: \(payload.memberDisplayName) to jar \(envelope.jarID)")

        // Add member (status: pending, awaiting invite_accepted)
        try await db.writeAsync { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO jar_members (jar_id, did, display_name, phone_number, role, status, added_at, added_by_did)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                envelope.jarID,
                payload.memberDID,
                payload.memberDisplayName,
                payload.memberPhoneNumber,
                "member",
                "pending",
                payload.addedAtMs / 1000,
                payload.addedByDID
            ])
        }

        print("✅ Member added: \(payload.memberDisplayName) (pending)")
    }

    /**
     * jar.invite_accepted - Member accepts invite
     */
    func applyInviteAccepted(_ envelope: RelayEnvelope) async throws {
        let payload = try decodeJarInviteAcceptedPayload(envelope.receiptData)

        print("✓ Member accepted invite: \(payload.memberDID)")

        // Update status: pending → active
        try await db.writeAsync { db in
            try db.execute(sql: """
                UPDATE jar_members
                SET status = 'active', accepted_at = ?
                WHERE jar_id = ? AND did = ?
            """, arguments: [
                payload.acceptedAtMs / 1000,
                envelope.jarID,
                payload.memberDID
            ])
        }

        print("✅ Member is now active")
    }

    /**
     * jar.member_removed - Owner removes member
     */
    func applyMemberRemoved(_ envelope: RelayEnvelope) async throws {
        let payload = try decodeJarMemberRemovedPayload(envelope.receiptData)

        print("🚫 Removing member: \(payload.memberDID)")

        // Update status: active → removed
        try await db.writeAsync { db in
            try db.execute(sql: """
                UPDATE jar_members
                SET status = 'removed', removed_at = ?
                WHERE jar_id = ? AND did = ?
            """, arguments: [
                payload.removedAtMs / 1000,
                envelope.jarID,
                payload.memberDID
            ])
        }

        print("✅ Member removed")
    }

    /**
     * jar.member_left - Member leaves voluntarily
     */
    func applyMemberLeft(_ envelope: RelayEnvelope) async throws {
        let payload = try decodeJarMemberLeftPayload(envelope.receiptData)

        print("👋 Member left: \(payload.memberDID)")

        // Update status: active → removed
        try await db.writeAsync { db in
            try db.execute(sql: """
                UPDATE jar_members
                SET status = 'removed', removed_at = ?
                WHERE jar_id = ? AND did = ?
            """, arguments: [
                payload.leftAtMs / 1000,
                envelope.jarID,
                payload.memberDID
            ])
        }

        print("✅ Member left voluntarily")
    }

    /**
     * jar.renamed - Owner renames jar
     */
    func applyJarRenamed(_ envelope: RelayEnvelope) async throws {
        let payload = try decodeJarRenamedPayload(envelope.receiptData)

        print("✏️ Renaming jar to: \(payload.jarName)")

        // Update jar name
        try await db.writeAsync { db in
            try db.execute(sql: """
                UPDATE jars
                SET name = ?
                WHERE id = ?
            """, arguments: [payload.jarName, envelope.jarID])
        }

        print("✅ Jar renamed")
    }

    /**
     * jar.bud_shared - Member shares bud to jar
     */
    func applyBudShared(_ envelope: RelayEnvelope) async throws {
        let payload = try decodeJarBudSharedPayload(envelope.receiptData)

        print("🌿 Sharing bud: \(payload.budUUID) to jar \(envelope.jarID)")

        // Link bud to jar (ucr_headers.jar_id = envelope.jarID)
        try await db.writeAsync { db in
            try db.execute(sql: """
                UPDATE ucr_headers
                SET jar_id = ?
                WHERE uuid = ?
            """, arguments: [envelope.jarID, payload.budUUID])
        }

        // Verify bud CID matches (optional integrity check)
        let budCID = try await db.readAsync { db in
            try String.fetchOne(db, sql: "SELECT cid FROM ucr_headers WHERE uuid = ?", arguments: [payload.budUUID])
        }

        if let budCID = budCID, budCID != payload.budCID {
            print("⚠️ Bud CID mismatch: expected \(payload.budCID), got \(budCID)")
            // Don't throw - bud is still shared, just log warning
        }

        print("✅ Bud shared to jar")
    }

    /**
     * jar.bud_deleted - Owner deletes bud from jar
     */
    func applyBudDeleted(_ envelope: RelayEnvelope) async throws {
        let payload = try decodeJarBudDeletedPayload(envelope.receiptData)

        print("🗑️ Deleting bud: \(payload.budUUID) from jar \(envelope.jarID)")

        // Validate: deletedByDID must match bud.ownerDID (only owner can delete)
        let budOwnerDID = try await db.readAsync { db in
            try String.fetchOne(db, sql: "SELECT did FROM ucr_headers WHERE uuid = ?", arguments: [payload.budUUID])
        }

        guard budOwnerDID == payload.deletedByDID else {
            throw SyncError.notBudOwner(budUUID: payload.budUUID, deletedBy: payload.deletedByDID)
        }

        // Unlink bud from jar (jar_id = NULL)
        try await db.writeAsync { db in
            try db.execute(sql: """
                UPDATE ucr_headers
                SET jar_id = NULL
                WHERE uuid = ?
            """, arguments: [payload.budUUID])
        }

        print("✅ Bud deleted from jar (moved to Solo)")
    }

    /**
     * jar.deleted - Owner deletes jar
     */
    func applyJarDeleted(_ envelope: RelayEnvelope) async throws {
        let payload = try decodeJarDeletedPayload(envelope.receiptData)

        print("🗑️ Deleting jar: \(payload.jarName)")

        // 1. Create tombstone
        try await tombstoneRepo.create(
            jarID: envelope.jarID,
            jarName: payload.jarName,
            deletedByDID: payload.deletedByDID
        )

        // 2. Move jar buds to Solo jar (jar_id = NULL or 'solo')
        try await db.writeAsync { db in
            try db.execute(sql: """
                UPDATE ucr_headers
                SET jar_id = NULL
                WHERE jar_id = ?
            """, arguments: [envelope.jarID])
        }

        // 3. Delete jar locally
        try await db.writeAsync { db in
            try db.execute(sql: "DELETE FROM jars WHERE id = ?", arguments: [envelope.jarID])
            try db.execute(sql: "DELETE FROM jar_members WHERE jar_id = ?", arguments: [envelope.jarID])
        }

        print("✅ Jar deleted, buds moved to Solo")
    }

    // MARK: - Persistence

    /**
     * Mark receipt as processed + update jar sequence
     */
    func markProcessed(receiptCID: String, jarID: String, sequenceNumber: Int) async throws {
        try await db.writeAsync { db in
            // Insert into processed_jar_receipts (replay protection)
            try db.execute(sql: """
                INSERT OR IGNORE INTO processed_jar_receipts (receipt_cid, jar_id, sequence_number, processed_at)
                VALUES (?, ?, ?, ?)
            """, arguments: [receiptCID, jarID, sequenceNumber, Date().timeIntervalSince1970])

            // Update jars.last_sequence_number
            try db.execute(sql: """
                UPDATE jars
                SET last_sequence_number = ?, parent_cid = ?
                WHERE id = ?
            """, arguments: [sequenceNumber, receiptCID, jarID])
        }
    }

    // MARK: - CBOR Decoding Helpers

    /**
     * Decode outer envelope to get receiptType and inner payload
     */
    private func decodeReceiptPayload(_ cborData: Data) throws -> JarReceiptPayload {
        let decoder = CBORDecoder()
        let value = try decoder.decode(cborData)

        guard case .map(let pairs) = value else {
            throw SyncError.invalidCBORStructure("Expected map at root")
        }

        var fields: [String: CBORValue] = [:]
        for (key, val) in pairs {
            guard case .text(let keyStr) = key else { continue }
            fields[keyStr] = val
        }

        // Extract required fields
        guard case .text(let jarID) = fields["jar_id"] else {
            throw SyncError.missingField("jar_id")
        }
        guard case .text(let receiptType) = fields["receipt_type"] else {
            throw SyncError.missingField("receipt_type")
        }
        guard case .text(let senderDID) = fields["sender_did"] else {
            throw SyncError.missingField("sender_did")
        }
        guard case .int(let timestamp) = fields["timestamp"] else {
            throw SyncError.missingField("timestamp")
        }
        guard case .bytes(let payload) = fields["payload"] else {
            throw SyncError.missingField("payload")
        }

        // Optional parent_cid
        let parentCID: String?
        if case .text(let parent) = fields["parent_cid"] {
            parentCID = parent
        } else {
            parentCID = nil
        }

        return JarReceiptPayload(
            jarID: jarID,
            receiptType: receiptType,
            senderDID: senderDID,
            timestamp: timestamp,
            parentCID: parentCID,
            payload: Data(payload)
        )
    }

    /**
     * Decode jar.created payload
     */
    private func decodeJarCreatedPayload(_ cborData: Data) throws -> JarCreatedPayload {
        // First decode envelope
        let envelope = try decodeReceiptPayload(cborData)

        // Then decode inner payload
        let decoder = CBORDecoder()
        let value = try decoder.decode(envelope.payload)

        guard case .map(let pairs) = value else {
            throw SyncError.invalidCBORStructure("Expected map in payload")
        }

        var fields: [String: CBORValue] = [:]
        for (key, val) in pairs {
            guard case .text(let keyStr) = key else { continue }
            fields[keyStr] = val
        }

        guard case .text(let jarName) = fields["jar_name"] else {
            throw SyncError.missingField("jar_name")
        }
        guard case .text(let ownerDID) = fields["owner_did"] else {
            throw SyncError.missingField("owner_did")
        }
        guard case .int(let createdAtMs) = fields["created_at_ms"] else {
            throw SyncError.missingField("created_at_ms")
        }

        let jarDescription: String?
        if case .text(let desc) = fields["jar_description"] {
            jarDescription = desc
        } else {
            jarDescription = nil
        }

        return JarCreatedPayload(
            jarName: jarName,
            jarDescription: jarDescription,
            ownerDID: ownerDID,
            createdAtMs: createdAtMs
        )
    }

    private func decodeJarMemberAddedPayload(_ cborData: Data) throws -> JarMemberAddedPayload {
        let envelope = try decodeReceiptPayload(cborData)
        let decoder = CBORDecoder()
        let value = try decoder.decode(envelope.payload)

        guard case .map(let pairs) = value else {
            throw SyncError.invalidCBORStructure("Expected map")
        }

        var fields: [String: CBORValue] = [:]
        for (key, val) in pairs {
            guard case .text(let keyStr) = key else { continue }
            fields[keyStr] = val
        }

        guard case .text(let memberDID) = fields["member_did"],
              case .text(let memberDisplayName) = fields["member_display_name"],
              case .text(let memberPhoneNumber) = fields["member_phone_number"],
              case .text(let addedByDID) = fields["added_by_did"],
              case .int(let addedAtMs) = fields["added_at_ms"] else {
            throw SyncError.missingField("member_added fields")
        }

        return JarMemberAddedPayload(
            memberDID: memberDID,
            memberDisplayName: memberDisplayName,
            memberPhoneNumber: memberPhoneNumber,
            addedByDID: addedByDID,
            addedAtMs: addedAtMs
        )
    }

    private func decodeJarInviteAcceptedPayload(_ cborData: Data) throws -> JarInviteAcceptedPayload {
        let envelope = try decodeReceiptPayload(cborData)
        let decoder = CBORDecoder()
        let value = try decoder.decode(envelope.payload)

        guard case .map(let pairs) = value else {
            throw SyncError.invalidCBORStructure("Expected map")
        }

        var fields: [String: CBORValue] = [:]
        for (key, val) in pairs {
            guard case .text(let keyStr) = key else { continue }
            fields[keyStr] = val
        }

        guard case .text(let memberDID) = fields["member_did"],
              case .int(let acceptedAtMs) = fields["accepted_at_ms"] else {
            throw SyncError.missingField("invite_accepted fields")
        }

        return JarInviteAcceptedPayload(
            memberDID: memberDID,
            acceptedAtMs: acceptedAtMs
        )
    }

    private func decodeJarMemberRemovedPayload(_ cborData: Data) throws -> JarMemberRemovedPayload {
        let envelope = try decodeReceiptPayload(cborData)
        let decoder = CBORDecoder()
        let value = try decoder.decode(envelope.payload)

        guard case .map(let pairs) = value else {
            throw SyncError.invalidCBORStructure("Expected map")
        }

        var fields: [String: CBORValue] = [:]
        for (key, val) in pairs {
            guard case .text(let keyStr) = key else { continue }
            fields[keyStr] = val
        }

        guard case .text(let memberDID) = fields["member_did"],
              case .text(let removedByDID) = fields["removed_by_did"],
              case .int(let removedAtMs) = fields["removed_at_ms"] else {
            throw SyncError.missingField("member_removed fields")
        }

        let reason: String?
        if case .text(let r) = fields["reason"] {
            reason = r
        } else {
            reason = nil
        }

        return JarMemberRemovedPayload(
            memberDID: memberDID,
            removedByDID: removedByDID,
            removedAtMs: removedAtMs,
            reason: reason
        )
    }

    private func decodeJarMemberLeftPayload(_ cborData: Data) throws -> JarMemberLeftPayload {
        let envelope = try decodeReceiptPayload(cborData)
        let decoder = CBORDecoder()
        let value = try decoder.decode(envelope.payload)

        guard case .map(let pairs) = value else {
            throw SyncError.invalidCBORStructure("Expected map")
        }

        var fields: [String: CBORValue] = [:]
        for (key, val) in pairs {
            guard case .text(let keyStr) = key else { continue }
            fields[keyStr] = val
        }

        guard case .text(let memberDID) = fields["member_did"],
              case .int(let leftAtMs) = fields["left_at_ms"] else {
            throw SyncError.missingField("member_left fields")
        }

        return JarMemberLeftPayload(
            memberDID: memberDID,
            leftAtMs: leftAtMs
        )
    }

    private func decodeJarRenamedPayload(_ cborData: Data) throws -> JarRenamedPayload {
        let envelope = try decodeReceiptPayload(cborData)
        let decoder = CBORDecoder()
        let value = try decoder.decode(envelope.payload)

        guard case .map(let pairs) = value else {
            throw SyncError.invalidCBORStructure("Expected map")
        }

        var fields: [String: CBORValue] = [:]
        for (key, val) in pairs {
            guard case .text(let keyStr) = key else { continue }
            fields[keyStr] = val
        }

        guard case .text(let jarName) = fields["jar_name"],
              case .text(let renamedByDID) = fields["renamed_by_did"],
              case .int(let renamedAtMs) = fields["renamed_at_ms"] else {
            throw SyncError.missingField("jar_renamed fields")
        }

        return JarRenamedPayload(
            jarName: jarName,
            renamedByDID: renamedByDID,
            renamedAtMs: renamedAtMs
        )
    }

    private func decodeJarBudSharedPayload(_ cborData: Data) throws -> JarBudSharedPayload {
        let envelope = try decodeReceiptPayload(cborData)
        let decoder = CBORDecoder()
        let value = try decoder.decode(envelope.payload)

        guard case .map(let pairs) = value else {
            throw SyncError.invalidCBORStructure("Expected map")
        }

        var fields: [String: CBORValue] = [:]
        for (key, val) in pairs {
            guard case .text(let keyStr) = key else { continue }
            fields[keyStr] = val
        }

        guard case .text(let budUUID) = fields["bud_uuid"],
              case .text(let sharedByDID) = fields["shared_by_did"],
              case .int(let sharedAtMs) = fields["shared_at_ms"],
              case .text(let budCID) = fields["bud_cid"] else {
            throw SyncError.missingField("bud_shared fields")
        }

        return JarBudSharedPayload(
            budUUID: budUUID,
            sharedByDID: sharedByDID,
            sharedAtMs: sharedAtMs,
            budCID: budCID
        )
    }

    private func decodeJarBudDeletedPayload(_ cborData: Data) throws -> JarBudDeletedPayload {
        let envelope = try decodeReceiptPayload(cborData)
        let decoder = CBORDecoder()
        let value = try decoder.decode(envelope.payload)

        guard case .map(let pairs) = value else {
            throw SyncError.invalidCBORStructure("Expected map")
        }

        var fields: [String: CBORValue] = [:]
        for (key, val) in pairs {
            guard case .text(let keyStr) = key else { continue }
            fields[keyStr] = val
        }

        guard case .text(let budUUID) = fields["bud_uuid"],
              case .text(let deletedByDID) = fields["deleted_by_did"],
              case .int(let deletedAtMs) = fields["deleted_at_ms"] else {
            throw SyncError.missingField("bud_deleted fields")
        }

        let reason: String?
        if case .text(let r) = fields["reason"] {
            reason = r
        } else {
            reason = nil
        }

        return JarBudDeletedPayload(
            budUUID: budUUID,
            deletedByDID: deletedByDID,
            deletedAtMs: deletedAtMs,
            reason: reason
        )
    }

    private func decodeJarDeletedPayload(_ cborData: Data) throws -> JarDeletedPayload {
        let envelope = try decodeReceiptPayload(cborData)
        let decoder = CBORDecoder()
        let value = try decoder.decode(envelope.payload)

        guard case .map(let pairs) = value else {
            throw SyncError.invalidCBORStructure("Expected map")
        }

        var fields: [String: CBORValue] = [:]
        for (key, val) in pairs {
            guard case .text(let keyStr) = key else { continue }
            fields[keyStr] = val
        }

        guard case .text(let deletedByDID) = fields["deleted_by_did"],
              case .int(let deletedAtMs) = fields["deleted_at_ms"],
              case .text(let jarName) = fields["jar_name"] else {
            throw SyncError.missingField("jar_deleted fields")
        }

        return JarDeletedPayload(
            deletedByDID: deletedByDID,
            deletedAtMs: deletedAtMs,
            jarName: jarName
        )
    }
}

// MARK: - Errors

enum SyncError: Error, LocalizedError {
    case cidMismatch(expected: String, actual: String)
    case unknownReceiptType(String)
    case notBudOwner(budUUID: String, deletedBy: String)
    case invalidCBORStructure(String)
    case missingField(String)

    var errorDescription: String? {
        switch self {
        case .cidMismatch(let expected, let actual):
            return "CID mismatch: expected \(expected), got \(actual)"
        case .unknownReceiptType(let type):
            return "Unknown receipt type: \(type)"
        case .notBudOwner(let budUUID, let deletedBy):
            return "User \(deletedBy) is not owner of bud \(budUUID)"
        case .invalidCBORStructure(let msg):
            return "Invalid CBOR structure: \(msg)"
        case .missingField(let field):
            return "Missing required field: \(field)"
        }
    }
}
