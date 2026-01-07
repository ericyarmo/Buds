/**
 * JarSyncManager (Phase 10.3 Module 4)
 *
 * Core sync engine - receives relay envelopes, verifies, applies to local state.
 * Handles imperfect networks: out-of-order delivery, packet loss, incomplete backfills.
 *
 * CRITICAL ARCHITECTURE (Relay Envelope):
 * - Client sends receipt WITHOUT sequence → relay assigns authoritative sequence
 * - This manager processes relay envelopes (which HAVE relay-assigned sequences)
 * - Gap detection: seq > expected → queue + backfill
 * - Late/duplicate: seq < expected → skip
 * - Happy path: seq == expected → process + try queue
 *
 * Processing Pipeline:
 * 1. Replay protection (check processed_jar_receipts)
 * 2. Tombstone check (skip deleted jars)
 * 3. Halt check (skip halted jars - need manual intervention)
 * 4. Gap detection (queue if seq > expected, skip if seq < expected)
 * 5. Signature + CID verification
 * 6. Apply receipt to local state (route to type-specific handler)
 * 7. Mark as processed + update sequence
 * 8. Process queued receipts (if any now unblocked)
 *
 * Receipt Types (9 total):
 * - jar.created, jar.member_added, jar.invite_accepted
 * - jar.member_removed, jar.member_left, jar.renamed
 * - jar.bud_shared, jar.bud_deleted, jar.deleted
 *
 * Concurrency Safety:
 * - JarSyncState actor handles all mutable state
 * - Prevents concurrent queue processing for same jar
 * - Prevents overlapping backfill requests
 *
 * Poison Handling:
 * - Poison receipt = can't process (verification fails, decode fails, etc.)
 * - Poison HALTS the jar (maintains sequence invariant)
 * - Halted jars require manual intervention or app restart to retry
 */

import Foundation
import GRDB
import CryptoKit

// MARK: - Actor for Concurrency-Safe State

/// Actor to manage sync state safely across concurrent calls
actor JarSyncState {
    /// Jars currently having their queues processed
    private var processingQueues: Set<String> = []

    /// Active backfill requests per jar (prevents storm)
    private var backfillInProgress: [String: BackfillState] = [:]

    struct BackfillState {
        let from: Int
        let to: Int
        let until: Date
    }

    // MARK: - Queue Processing Guards

    func tryStartQueueProcessing(jarID: String) -> Bool {
        if processingQueues.contains(jarID) {
            return false
        }
        processingQueues.insert(jarID)
        return true
    }

    func finishQueueProcessing(jarID: String) {
        processingQueues.remove(jarID)
    }

    // MARK: - Backfill Guards

    func shouldSkipBackfill(jarID: String, from: Int, to: Int) -> Bool {
        guard let state = backfillInProgress[jarID] else { return false }
        // Skip if: lock not expired AND requested range is subset of in-progress range
        return state.until > Date() && from >= state.from && to <= state.to
    }

    func startBackfill(jarID: String, from: Int, to: Int, lockDuration: TimeInterval = 15) {
        backfillInProgress[jarID] = BackfillState(
            from: from,
            to: to,
            until: Date().addingTimeInterval(lockDuration)
        )
    }

    func finishBackfill(jarID: String) {
        backfillInProgress.removeValue(forKey: jarID)
    }
}

// MARK: - QueuedReceipt Model

struct QueuedReceipt: Codable, FetchableRecord, PersistableRecord {
    let id: String
    let jarID: String
    let sequenceNumber: Int
    let receiptCID: String
    let receiptData: Data
    let signature: Data
    let senderDID: String
    let parentCID: String?
    let queuedAt: TimeInterval
    var retryCount: Int
    var lastRetryAt: TimeInterval?
    var poisonReason: String?

    static let databaseTableName = "jar_receipt_queue"

    enum CodingKeys: String, CodingKey {
        case id
        case jarID = "jar_id"
        case sequenceNumber = "sequence_number"
        case receiptCID = "receipt_cid"
        case receiptData = "receipt_data"
        case signature
        case senderDID = "sender_did"
        case parentCID = "parent_cid"
        case queuedAt = "queued_at"
        case retryCount = "retry_count"
        case lastRetryAt = "last_retry_at"
        case poisonReason = "poison_reason"
    }
}

// MARK: - JarSyncManager

class JarSyncManager {
    static let shared = JarSyncManager()

    private let db: Database
    private let tombstoneRepo: JarTombstoneRepository
    private let syncState = JarSyncState()

    /// Poison thresholds
    private let maxRetries = 5
    private let maxQueueAge: TimeInterval = 7 * 24 * 60 * 60  // 7 days

    /// Backfill retry delays (exponential backoff)
    private let backfillRetryDelays: [TimeInterval] = [5, 15, 60, 300, 900]  // 5s, 15s, 1m, 5m, 15m

    private init() {
        self.db = Database.shared
        self.tombstoneRepo = JarTombstoneRepository.shared
    }

    // MARK: - Main Entry Point

    /**
     * Process relay envelope with gap detection and queueing (Module 4)
     *
     * - Parameter envelope: The relay envelope to process
     * - Parameter skipGapDetection: If true, skip gap detection (used for backfill and queue processing)
     *
     * INVARIANTS:
     * - Receipts processed in relay sequence order (1, 2, 3, ...)
     * - Gaps trigger backfill requests
     * - Out-of-order receipts queued until dependencies satisfied
     * - Poison receipts HALT the jar (not skipped)
     */
    func processEnvelope(_ envelope: RelayEnvelope, skipGapDetection: Bool = false) async throws {
        let jarPrefix = String(envelope.jarID.prefix(8))

        // ═══════════════════════════════════════════════════════════════
        // STEP 1: REPLAY PROTECTION
        // ═══════════════════════════════════════════════════════════════

        guard !(try await isAlreadyProcessed(envelope.receiptCID)) else {
            print("⏭️ [REPLAY] Skipping: \(String(envelope.receiptCID.prefix(12)))...")
            return
        }

        // ═══════════════════════════════════════════════════════════════
        // STEP 2: TOMBSTONE CHECK
        // ═══════════════════════════════════════════════════════════════

        guard !(try await tombstoneRepo.isTombstoned(envelope.jarID)) else {
            print("🪦 [TOMBSTONE] Skipping receipt for deleted jar: \(jarPrefix)...")
            return
        }

        // ═══════════════════════════════════════════════════════════════
        // STEP 3: HALT CHECK
        // ═══════════════════════════════════════════════════════════════

        if try await isJarHalted(envelope.jarID) {
            print("🛑 [HALTED] Skipping receipt for halted jar: \(jarPrefix)...")
            throw SyncError.jarHalted(jarID: envelope.jarID)
        }

        // ═══════════════════════════════════════════════════════════════
        // STEP 4: GAP DETECTION (only for normal processing)
        // ═══════════════════════════════════════════════════════════════

        if !skipGapDetection {
            let lastSeq = try await getLastSequence(jarID: envelope.jarID)
            let expectedSeq = lastSeq + 1

            // CASE A: seq > expected → GAP DETECTED
            if envelope.sequenceNumber > expectedSeq {
                print("⚠️ [GAP] jar=\(jarPrefix) expected=\(expectedSeq) got=\(envelope.sequenceNumber)")

                // Verify BEFORE queueing (don't queue invalid receipts)
                do {
                    try await verifyReceipt(envelope)
                } catch {
                    print("❌ [VERIFY] Receipt failed verification, not queueing: \(error)")
                    throw error
                }

                // Queue this receipt
                try await queueReceipt(envelope)

                // Request missing receipts
                try await requestBackfill(
                    jarID: envelope.jarID,
                    from: expectedSeq,
                    to: envelope.sequenceNumber - 1
                )

                return
            }

            // CASE B: seq < expected → LATE/DUPLICATE
            if envelope.sequenceNumber < expectedSeq {
                print("⏪ [LATE] jar=\(jarPrefix) expected=\(expectedSeq) got=\(envelope.sequenceNumber)")
                return
            }

            // CASE C: seq == expected → HAPPY PATH (fall through)
        }

        // ═══════════════════════════════════════════════════════════════
        // STEP 5: VERIFY RECEIPT
        // ═══════════════════════════════════════════════════════════════

        try await verifyReceipt(envelope)

        // ═══════════════════════════════════════════════════════════════
        // STEP 6: APPLY RECEIPT
        // ═══════════════════════════════════════════════════════════════

        try await applyReceipt(envelope)

        // ═══════════════════════════════════════════════════════════════
        // STEP 7: MARK AS PROCESSED
        // ═══════════════════════════════════════════════════════════════

        try await markProcessed(
            receiptCID: envelope.receiptCID,
            jarID: envelope.jarID,
            sequenceNumber: envelope.sequenceNumber
        )

        print("✅ [PROCESSED] jar=\(jarPrefix) seq=\(envelope.sequenceNumber)")

        // ═══════════════════════════════════════════════════════════════
        // STEP 8: TRY TO PROCESS QUEUED RECEIPTS
        // Only when NOT skipGapDetection (prevents nested calls)
        // ═══════════════════════════════════════════════════════════════

        if !skipGapDetection {
            try await processQueuedReceipts(jarID: envelope.jarID)
        }
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
                INSERT INTO jars (id, name, description, owner_did, created_at, updated_at, last_sequence_number, parent_cid)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                envelope.jarID,
                payload.jarName,
                payload.jarDescription,
                payload.ownerDID,
                payload.createdAtMs / 1000,  // Convert ms to seconds
                payload.createdAtMs / 1000,  // updated_at = created_at initially
                envelope.sequenceNumber,
                envelope.receiptCID
            ])
        }

        // Add owner to jar_members (role: owner, status: active)
        // Note: Owner device details will be added when jar.member_added is processed
        try await db.writeAsync { db in
            try db.execute(sql: """
                INSERT OR IGNORE INTO jar_members (
                    jar_id, member_did, display_name, pubkey_x25519, role, status,
                    joined_at, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                envelope.jarID,
                payload.ownerDID,
                "Owner",  // Placeholder display name
                "",  // Placeholder pubkey (will be updated by jar.member_added)
                "owner",
                "active",
                payload.createdAtMs / 1000,
                Date().timeIntervalSince1970,
                Date().timeIntervalSince1970
            ])
        }

        print("✅ Jar created: \(payload.jarName)")
    }

    /**
     * jar.member_added - Add member to jar
     * Module 6: Includes TOFU device pinning for all jar members
     */
    func applyMemberAdded(_ envelope: RelayEnvelope) async throws {
        let payload = try decodeJarMemberAddedPayload(envelope.receiptData)

        print("👤 Adding member: \(payload.memberDisplayName) to jar \(envelope.jarID)")

        // STEP 1: Pin ALL devices for this member (TOFU key pinning)
        // CRITICAL: This allows all jar members to encrypt messages to invitee
        for device in payload.memberDevices {
            try await db.writeAsync { db in
                // Check if device already exists
                let exists = try Device
                    .filter(Device.Columns.deviceId == device.deviceId)
                    .fetchCount(db) > 0

                if !exists {
                    let deviceRecord = Device(
                        deviceId: device.deviceId,
                        ownerDID: payload.memberDID,
                        deviceName: "Unknown",  // We don't have device name in receipt
                        pubkeyX25519: device.pubkeyX25519,
                        pubkeyEd25519: device.pubkeyEd25519,
                        status: .active,
                        registeredAt: Date(),
                        lastSeenAt: nil
                    )
                    try deviceRecord.insert(db)
                    print("🔐 Pinned device \(device.deviceId) for \(payload.memberDID)")
                }
            }
        }

        // STEP 2: Get first device's X25519 key for jar_members table
        guard let firstDevice = payload.memberDevices.first else {
            throw SyncError.missingField("member_devices (empty array)")
        }

        // STEP 3: Add member to jar_members (status: pending, awaiting invite_accepted)
        // CRITICAL FIX: Use correct column names matching jar_members schema
        try await db.writeAsync { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO jar_members
                (jar_id, member_did, display_name, phone_number, pubkey_x25519, avatar_cid,
                 role, status, joined_at, invited_at, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                envelope.jarID,
                payload.memberDID,
                payload.memberDisplayName,
                payload.memberPhoneNumber,
                firstDevice.pubkeyX25519,  // Use first device's key
                nil,                       // avatar_cid
                "member",
                "pending",
                nil,                       // joined_at (set when invite accepted)
                payload.addedAtMs / 1000,  // invited_at
                Date().timeIntervalSince1970,
                Date().timeIntervalSince1970
            ])
        }

        print("✅ Member added: \(payload.memberDisplayName) (\(payload.memberDevices.count) devices pinned, status=pending)")
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

    // MARK: - Queue Management (Module 4)

    /**
     * Queue a receipt that arrived out of order
     *
     * PRE-CONDITIONS:
     * - Receipt has been verified (signature valid)
     * - Gap was detected (seq > expected)
     */
    private func queueReceipt(_ envelope: RelayEnvelope) async throws {
        try await db.writeAsync { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO jar_receipt_queue
                (id, jar_id, receipt_cid, parent_cid, sequence_number, receipt_data, signature, sender_did, queued_at, retry_count)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
            """, arguments: [
                UUID().uuidString,
                envelope.jarID,
                envelope.receiptCID,
                envelope.parentCID,
                envelope.sequenceNumber,
                envelope.receiptData,
                envelope.signature,
                envelope.senderDID,
                Date().timeIntervalSince1970
            ])
        }

        print("📥 [QUEUE] Queued seq=\(envelope.sequenceNumber) for jar \(String(envelope.jarID.prefix(8)))...")
    }

    /**
     * Process queued receipts that now have dependencies satisfied
     *
     * ALGORITHM:
     * 1. Get all queued receipts for this jar, sorted by sequence
     * 2. For each receipt:
     *    - seq < expected: ORPHANED (already processed via backfill) → remove
     *    - seq == expected: READY → process and remove
     *    - seq > expected: BLOCKED → stop and schedule backfill retry
     * 3. On poison: HALT the jar (don't skip to next)
     *
     * CONCURRENCY: Uses actor guard to prevent concurrent queue processing
     */
    private func processQueuedReceipts(jarID: String) async throws {
        let jarPrefix = String(jarID.prefix(8))

        // Actor-safe guard: prevent concurrent queue processing
        guard await syncState.tryStartQueueProcessing(jarID: jarID) else {
            print("⏳ [QUEUE] Already processing for \(jarPrefix)...")
            return
        }
        defer { Task { await syncState.finishQueueProcessing(jarID: jarID) } }

        // Get queued receipts
        let queued = try await getQueuedReceipts(jarID: jarID)
        guard !queued.isEmpty else { return }

        print("🔄 [QUEUE] Processing \(queued.count) queued receipts for \(jarPrefix)...")

        // Sort by sequence (ascending) - CRITICAL
        let sorted = queued.sorted { $0.sequenceNumber < $1.sequenceNumber }

        // Track last processed sequence
        var lastSeq = try await getLastSequence(jarID: jarID)

        for queuedReceipt in sorted {
            let expectedSeq = lastSeq + 1

            // ─────────────────────────────────────────────────────────
            // CHECK: Is receipt too old or too many retries?
            // ─────────────────────────────────────────────────────────

            let age = Date().timeIntervalSince1970 - queuedReceipt.queuedAt
            if queuedReceipt.retryCount >= maxRetries || age > maxQueueAge {
                let reason = queuedReceipt.retryCount >= maxRetries
                    ? "exceeded \(maxRetries) retries"
                    : "expired after \(Int(age / 86400)) days"

                print("☠️ [POISON] seq=\(queuedReceipt.sequenceNumber): \(reason)")

                // HALT the jar - poison breaks sequence invariant
                try await haltJar(jarID: jarID, reason: "Poison receipt at seq=\(queuedReceipt.sequenceNumber): \(reason)")
                return
            }

            // ─────────────────────────────────────────────────────────
            // CASE A: seq < expected → ORPHANED (already processed)
            // ─────────────────────────────────────────────────────────

            if queuedReceipt.sequenceNumber < expectedSeq {
                print("🧹 [ORPHAN] Removing seq=\(queuedReceipt.sequenceNumber) (expected \(expectedSeq))")
                try await removeFromQueue(queuedReceipt.id)
                continue
            }

            // ─────────────────────────────────────────────────────────
            // CASE B: seq == expected → READY TO PROCESS
            // ─────────────────────────────────────────────────────────

            if queuedReceipt.sequenceNumber == expectedSeq {
                print("✅ [DEQUEUE] Processing seq=\(queuedReceipt.sequenceNumber)")

                // Reconstruct envelope
                let envelope = RelayEnvelope(
                    jarID: queuedReceipt.jarID,
                    sequenceNumber: queuedReceipt.sequenceNumber,
                    receiptCID: queuedReceipt.receiptCID,
                    receiptData: queuedReceipt.receiptData,
                    signature: queuedReceipt.signature,
                    senderDID: queuedReceipt.senderDID,
                    receivedAt: Int64(queuedReceipt.queuedAt * 1000),
                    parentCID: queuedReceipt.parentCID
                )

                do {
                    // Process with skipGapDetection=true (prevents nested queue calls)
                    try await processEnvelope(envelope, skipGapDetection: true)

                    // Remove from queue AFTER success
                    try await removeFromQueue(queuedReceipt.id)

                    // Update local tracking
                    lastSeq = queuedReceipt.sequenceNumber

                } catch {
                    // Processing failed - increment retry and HALT
                    print("❌ [POISON] Failed to process queued receipt: \(error)")
                    try await incrementRetryCount(queuedReceipt.id)
                    try await haltJar(jarID: jarID, reason: "Processing failed at seq=\(queuedReceipt.sequenceNumber): \(error.localizedDescription)")
                    return
                }

                continue
            }

            // ─────────────────────────────────────────────────────────
            // CASE C: seq > expected → STILL BLOCKED
            // ─────────────────────────────────────────────────────────

            print("⏸️ [BLOCKED] Waiting for seq=\(expectedSeq), have seq=\(queuedReceipt.sequenceNumber)")

            // Schedule delayed backfill retry (not immediate)
            try await scheduleBackfillRetry(
                jarID: jarID,
                from: expectedSeq,
                to: queuedReceipt.sequenceNumber - 1
            )

            break  // Can't process rest of queue
        }
    }

    /**
     * Request missing receipts from relay (backfill)
     *
     * GUARDS:
     * - Actor-safe: prevents overlapping requests (storm prevention)
     * - Processes backfilled receipts with skipGapDetection=true
     */
    private func requestBackfill(jarID: String, from: Int, to: Int) async throws {
        let jarPrefix = String(jarID.prefix(8))

        // Actor-safe guard: prevent overlapping backfill requests
        if await syncState.shouldSkipBackfill(jarID: jarID, from: from, to: to) {
            print("⏳ [BACKFILL] Already in progress for \(jarPrefix)...")
            return
        }

        await syncState.startBackfill(jarID: jarID, from: from, to: to)
        defer { Task { await syncState.finishBackfill(jarID: jarID) } }

        print("🔁 [BACKFILL] Requesting seq=\(from)-\(to) for \(jarPrefix)...")

        // Fetch from relay
        let envelopes: [RelayEnvelope]
        do {
            envelopes = try await RelayClient.shared.getJarReceipts(jarID: jarID, from: from, to: to)
        } catch {
            print("❌ [BACKFILL] Failed to fetch: \(error)")

            // Schedule retry with backoff
            try await scheduleBackfillRetry(jarID: jarID, from: from, to: to)
            return
        }

        let requestedCount = to - from + 1
        print("📬 [BACKFILL] Received \(envelopes.count)/\(requestedCount) receipts")

        if envelopes.isEmpty {
            print("⚠️ [BACKFILL] Relay returned no receipts - scheduling retry")
            try await scheduleBackfillRetry(jarID: jarID, from: from, to: to)
            return
        }

        // Process in sequence order (CRITICAL)
        for envelope in envelopes.sorted(by: { $0.sequenceNumber < $1.sequenceNumber }) {
            do {
                try await processEnvelope(envelope, skipGapDetection: true)
            } catch {
                print("❌ [BACKFILL] Failed to process seq=\(envelope.sequenceNumber): \(error)")
                // Don't halt here - the individual processEnvelope handles halting
                break
            }
        }

        // Check if incomplete (got fewer than requested)
        if envelopes.count < requestedCount {
            print("⚠️ [BACKFILL] Incomplete: \(envelopes.count)/\(requestedCount)")
            // Queue processing will trigger retry for remaining gap
        }
    }

    /**
     * Schedule a delayed backfill retry with exponential backoff
     */
    private func scheduleBackfillRetry(jarID: String, from: Int, to: Int) async throws {
        // Get current attempt count from jar_sync_state
        let (attempt, _) = try await getBackfillState(jarID: jarID)
        let nextAttempt = attempt + 1

        // Calculate delay with exponential backoff
        let delayIndex = min(nextAttempt - 1, backfillRetryDelays.count - 1)
        let delay = backfillRetryDelays[delayIndex]
        let nextRetryAt = Date().addingTimeInterval(delay)

        // Save state
        try await db.writeAsync { db in
            try db.execute(sql: """
                INSERT INTO jar_sync_state (jar_id, next_backfill_at, backfill_from, backfill_to, backfill_attempt)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(jar_id) DO UPDATE SET
                    next_backfill_at = excluded.next_backfill_at,
                    backfill_from = excluded.backfill_from,
                    backfill_to = excluded.backfill_to,
                    backfill_attempt = excluded.backfill_attempt
            """, arguments: [jarID, nextRetryAt.timeIntervalSince1970, from, to, nextAttempt])
        }

        print("📅 [BACKFILL] Scheduled retry #\(nextAttempt) in \(Int(delay))s for \(String(jarID.prefix(8)))...")

        // Schedule the actual retry
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            // Check if we should still retry (not halted, not already succeeded)
            guard !(try await isJarHalted(jarID)) else { return }

            let (_, scheduledAt) = try await getBackfillState(jarID: jarID)
            guard let scheduled = scheduledAt, scheduled <= Date() else { return }

            print("🔄 [BACKFILL] Executing scheduled retry for \(String(jarID.prefix(8)))...")
            try? await requestBackfill(jarID: jarID, from: from, to: to)
        }
    }

    // MARK: - Jar Halt Management

    /**
     * Halt a jar - stops all processing until manual intervention
     *
     * CRITICAL: Poison handling halts, doesn't skip
     * This maintains the sequence invariant
     *
     * NOTE: Internal visibility for InboxManager (Module 5a) to halt on 403
     */
    func haltJar(jarID: String, reason: String) async throws {
        print("🛑 [HALT] Halting jar \(String(jarID.prefix(8)))...: \(reason)")

        try await db.writeAsync { db in
            try db.execute(sql: """
                INSERT INTO jar_sync_state (jar_id, is_halted, halt_reason, halted_at)
                VALUES (?, 1, ?, ?)
                ON CONFLICT(jar_id) DO UPDATE SET
                    is_halted = 1,
                    halt_reason = excluded.halt_reason,
                    halted_at = excluded.halted_at
            """, arguments: [jarID, reason, Date().timeIntervalSince1970])
        }

        // TODO: Post notification to UI about halted jar
    }

    /**
     * Check if a jar is halted
     */
    func isJarHalted(_ jarID: String) async throws -> Bool {
        try await db.readAsync { db in
            let isHalted = try Int.fetchOne(
                db,
                sql: "SELECT is_halted FROM jar_sync_state WHERE jar_id = ?",
                arguments: [jarID]
            )
            return isHalted == 1
        }
    }

    /**
     * Unhalt a jar - allows retrying after manual intervention
     */
    func unhaltJar(_ jarID: String) async throws {
        print("▶️ [UNHALT] Unhalting jar \(String(jarID.prefix(8)))...")

        try await db.writeAsync { db in
            try db.execute(sql: """
                UPDATE jar_sync_state
                SET is_halted = 0, halt_reason = NULL, halted_at = NULL, backfill_attempt = 0
                WHERE jar_id = ?
            """, arguments: [jarID])
        }
    }

    // MARK: - Helpers

    /**
     * Get last processed sequence for a jar
     * Returns 0 if jar doesn't exist (expects seq=1 for jar.created)
     */
    func getLastSequence(jarID: String) async throws -> Int {
        try await db.readAsync { db in
            try Int.fetchOne(
                db,
                sql: "SELECT last_sequence_number FROM jars WHERE id = ?",
                arguments: [jarID]
            ) ?? 0
        }
    }

    /**
     * Get all queued receipts for a jar (excluding poisoned)
     */
    private func getQueuedReceipts(jarID: String) async throws -> [QueuedReceipt] {
        try await db.readAsync { db in
            try QueuedReceipt.fetchAll(db, sql: """
                SELECT * FROM jar_receipt_queue
                WHERE jar_id = ? AND poison_reason IS NULL
                ORDER BY sequence_number ASC
            """, arguments: [jarID])
        }
    }

    /**
     * Remove a receipt from the queue
     */
    private func removeFromQueue(_ queueID: String) async throws {
        try await db.writeAsync { db in
            try db.execute(
                sql: "DELETE FROM jar_receipt_queue WHERE id = ?",
                arguments: [queueID]
            )
        }
    }

    /**
     * Increment retry count for a queued receipt
     */
    private func incrementRetryCount(_ queueID: String) async throws {
        try await db.writeAsync { db in
            try db.execute(sql: """
                UPDATE jar_receipt_queue
                SET retry_count = retry_count + 1, last_retry_at = ?
                WHERE id = ?
            """, arguments: [Date().timeIntervalSince1970, queueID])
        }
    }

    /**
     * Get backfill state for a jar
     */
    private func getBackfillState(jarID: String) async throws -> (attempt: Int, nextRetryAt: Date?) {
        try await db.readAsync { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT backfill_attempt, next_backfill_at FROM jar_sync_state WHERE jar_id = ?
            """, arguments: [jarID])

            let attempt = row?["backfill_attempt"] as? Int ?? 0
            let nextRetryAt: Date?
            if let timestamp = row?["next_backfill_at"] as? TimeInterval {
                nextRetryAt = Date(timeIntervalSince1970: timestamp)
            } else {
                nextRetryAt = nil
            }

            return (attempt, nextRetryAt)
        }
    }

    // MARK: - Sync Interface (Module 5a)

    /**
     * Get jars that need syncing
     *
     * Returns array of (jarID, lastSeq, isHalted) for InboxManager to poll
     *
     * INVARIANT: JarSyncManager owns all writes to jars.last_sequence_number
     * InboxManager only reads via this interface.
     */
    func getSyncTargets() async throws -> [JarSyncTarget] {
        try await db.readAsync { db in
            // Fetch all active jars (not tombstoned)
            let rows = try Row.fetchAll(db, sql: """
                SELECT j.id, j.last_sequence_number, COALESCE(s.is_halted, 0) AS is_halted
                FROM jars j
                LEFT JOIN jar_sync_state s ON j.id = s.jar_id
                WHERE j.id NOT IN (SELECT jar_id FROM jar_tombstones)
                ORDER BY j.created_at DESC
            """)

            return rows.map { row in
                JarSyncTarget(
                    jarID: row["id"] as! String,
                    lastSequenceNumber: Int(row["last_sequence_number"] as? Int64 ?? 0),
                    isHalted: (row["is_halted"] as? Int64 ?? 0) == 1
                )
            }
        }
    }

    /**
     * Process batch of envelopes for a jar
     *
     * Handles:
     * - Sorting by sequence (ascending)
     * - In-memory deduplication by sequenceNumber (pagination bugs)
     * - DB replay protection by receiptCID
     * - Routing to processEnvelope()
     *
     * CRITICAL: Envelopes from relay might be out-of-order or contain duplicates.
     * We MUST sort + dedupe before processing to avoid unnecessary gap detection.
     */
    func processEnvelopes(for jarID: String, _ envelopes: [RelayEnvelope]) async throws {
        guard !envelopes.isEmpty else { return }

        let jarPrefix = String(jarID.prefix(8))
        print("📦 [BATCH] Processing \(envelopes.count) envelopes for \(jarPrefix)...")

        // CRITICAL FIX 1a: Sort by sequence (ascending)
        let sorted = envelopes.sorted { $0.sequenceNumber < $1.sequenceNumber }

        // CRITICAL FIX 1b: In-memory dedupe by sequenceNumber (keep first occurrence)
        // Handles pagination bugs where relay returns seq=3 twice
        var seenSequences: Set<Int> = []
        let deduped = sorted.filter { envelope in
            if seenSequences.contains(envelope.sequenceNumber) {
                print("⚠️  [BATCH] Duplicate seq=\(envelope.sequenceNumber), skipping")
                return false
            }
            seenSequences.insert(envelope.sequenceNumber)
            return true
        }

        // Process each envelope with DB replay protection
        var processed = 0
        var skipped = 0

        for envelope in deduped {
            // CRITICAL FIX 2: Check DB for (jarID, seq, CID) consistency
            if let existingCID = try await getProcessedReceiptCID(jarID: jarID, sequenceNumber: envelope.sequenceNumber) {
                if existingCID != envelope.receiptCID {
                    // CORRUPTION: Same sequence with different CID
                    print("🚨 [CORRUPTION] jar=\(jarPrefix) seq=\(envelope.sequenceNumber) CID mismatch!")
                    print("🚨   Expected: \(existingCID)")
                    print("🚨   Got:      \(envelope.receiptCID)")
                    try await haltJar(jarID: jarID, reason: "Sequence \(envelope.sequenceNumber) CID mismatch (corruption detected)")
                    throw SyncError.sequenceCIDMismatch(jarID: jarID, sequence: envelope.sequenceNumber)
                }
                // Same CID, already processed (replay)
                skipped += 1
                continue
            }

            // Process envelope (gap detection, verification, apply)
            do {
                try await processEnvelope(envelope)
                processed += 1
            } catch {
                print("❌ [BATCH] Failed to process seq=\(envelope.sequenceNumber): \(error)")
                // Continue processing rest (don't let one failure stop the batch)
                // Individual failures are handled by processEnvelope (halting, etc.)
            }
        }

        print("✅ [BATCH] Processed \(processed)/\(deduped.count) (\(skipped) skipped)")
    }

    /**
     * Get CID of already-processed receipt for (jarID, sequence)
     *
     * Returns:
     * - nil if not processed
     * - CID if processed (for mismatch detection)
     */
    private func getProcessedReceiptCID(jarID: String, sequenceNumber: Int) async throws -> String? {
        try await db.readAsync { db in
            try String.fetchOne(db, sql: """
                SELECT receipt_cid FROM processed_jar_receipts
                WHERE jar_id = ? AND sequence_number = ?
            """, arguments: [jarID, sequenceNumber])
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
              case .array(let devicesArray) = fields["member_devices"],
              case .text(let addedByDID) = fields["added_by_did"],
              case .int(let addedAtMs) = fields["added_at_ms"] else {
            throw SyncError.missingField("member_added fields")
        }

        // Parse devices array
        var devices: [DeviceInfo] = []
        for deviceValue in devicesArray {
            guard case .map(let devicePairs) = deviceValue else {
                throw SyncError.invalidCBORStructure("Expected device map")
            }

            var deviceFields: [String: CBORValue] = [:]
            for (key, val) in devicePairs {
                guard case .text(let keyStr) = key else { continue }
                deviceFields[keyStr] = val
            }

            guard case .text(let deviceId) = deviceFields["device_id"],
                  case .text(let pubkeyEd25519) = deviceFields["pubkey_ed25519"],
                  case .text(let pubkeyX25519) = deviceFields["pubkey_x25519"] else {
                throw SyncError.missingField("device fields")
            }

            devices.append(DeviceInfo(
                deviceId: deviceId,
                pubkeyEd25519: pubkeyEd25519,
                pubkeyX25519: pubkeyX25519
            ))
        }

        return JarMemberAddedPayload(
            memberDID: memberDID,
            memberDisplayName: memberDisplayName,
            memberPhoneNumber: memberPhoneNumber,
            memberDevices: devices,
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

// MARK: - Models

/**
 * Jar sync target (Module 5a)
 *
 * Used by InboxManager to poll jars without knowing DB schema
 */
struct JarSyncTarget {
    let jarID: String
    let lastSequenceNumber: Int
    let isHalted: Bool
}

// MARK: - Errors

enum SyncError: Error, LocalizedError {
    case cidMismatch(expected: String, actual: String)
    case unknownReceiptType(String)
    case notBudOwner(budUUID: String, deletedBy: String)
    case invalidCBORStructure(String)
    case missingField(String)
    case jarHalted(jarID: String)
    case backfillFailed(jarID: String, reason: String)
    case sequenceCIDMismatch(jarID: String, sequence: Int)  // Module 5a: Corruption detection

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
        case .jarHalted(let jarID):
            return "Jar \(jarID) is halted - requires manual intervention"
        case .backfillFailed(let jarID, let reason):
            return "Backfill failed for jar \(jarID): \(reason)"
        case .sequenceCIDMismatch(let jarID, let sequence):
            return "Sequence \(sequence) CID mismatch for jar \(jarID) - corruption detected"
        }
    }
}
