//
//  ReactionRepository.swift
//  Buds
//
//  Created by Eric Yarmolinsky on 12/28/25.
//
//  Phase 10.1 Module 1.4/1.5: Reactions CRUD operations with E2EE sync
//

import Foundation
import GRDB

struct ReactionRepository {
    private let db = Database.shared
    private let receiptManager = ReceiptManager.shared
    private let e2eeManager = E2EEManager.shared
    private let relayClient = RelayClient.shared

    // MARK: - Fetch

    /// Fetch all reactions for a memory, grouped by type
    func fetchReactionSummaries(for memoryID: UUID) async throws -> [ReactionSummary] {
        try await db.readAsync { db in
            let sql = """
                SELECT reaction_type, COUNT(*) as count, GROUP_CONCAT(sender_did) as senders
                FROM reactions
                WHERE memory_id = ?
                GROUP BY reaction_type
                ORDER BY count DESC
                """

            let rows = try Row.fetchAll(db, sql: sql, arguments: [memoryID.uuidString])

            return rows.compactMap { row in
                guard let typeString = row["reaction_type"] as? String,
                      let type = ReactionType(rawValue: typeString),
                      let count = row["count"] as? Int,
                      let sendersString = row["senders"] as? String else {
                    return nil
                }

                let senderDIDs = sendersString.split(separator: ",").map(String.init)

                return ReactionSummary(
                    type: type,
                    count: count,
                    senderDIDs: senderDIDs
                )
            }
        }
    }

    /// Get user's current reaction for a memory (if any)
    func fetchUserReaction(for memoryID: UUID, senderDID: String) async throws -> Reaction? {
        try await db.readAsync { db in
            let sql = """
                SELECT id, memory_id, sender_did, reaction_type, created_at
                FROM reactions
                WHERE memory_id = ? AND sender_did = ?
                """

            guard let row = try Row.fetchOne(db, sql: sql, arguments: [memoryID.uuidString, senderDID]) else {
                return nil
            }

            return try parseReaction(from: row)
        }
    }

    // MARK: - Create/Update

    /// Toggle user's reaction (add if not exists, remove if exists, replace if different type)
    /// Creates receipt and broadcasts to jar members (Phase 10.1 Module 1.5)
    func toggleReaction(
        memoryID: UUID,
        senderDID: String,
        type: ReactionType,
        jarID: String
    ) async throws {
        try await db.writeAsync { db in
            // Check if user already has a reaction
            let existingReaction = try Row.fetchOne(
                db,
                sql: "SELECT reaction_type FROM reactions WHERE memory_id = ? AND sender_did = ?",
                arguments: [memoryID.uuidString, senderDID]
            )

            if let existing = existingReaction,
               let existingType = existing["reaction_type"] as? String {
                // User already reacted
                if existingType == type.rawValue {
                    // Same type → Remove reaction (toggle off)
                    try db.execute(
                        sql: "DELETE FROM reactions WHERE memory_id = ? AND sender_did = ?",
                        arguments: [memoryID.uuidString, senderDID]
                    )
                    print("🔄 Removed reaction: \(type.emoji) for memory \(memoryID)")
                    // TODO: Create and send reaction.removed receipt
                } else {
                    // Different type → Update reaction
                    try db.execute(
                        sql: """
                            UPDATE reactions
                            SET reaction_type = ?, created_at = ?
                            WHERE memory_id = ? AND sender_did = ?
                            """,
                        arguments: [type.rawValue, Date().timeIntervalSince1970, memoryID.uuidString, senderDID]
                    )
                    print("🔄 Updated reaction: \(existingType) → \(type.emoji) for memory \(memoryID)")
                    // TODO: Create and send reaction.added receipt (replaces old one)
                }
            } else {
                // No existing reaction → Add new
                try db.execute(
                    sql: """
                        INSERT INTO reactions (id, memory_id, sender_did, reaction_type, created_at)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        UUID().uuidString,
                        memoryID.uuidString,
                        senderDID,
                        type.rawValue,
                        Date().timeIntervalSince1970
                    ]
                )
                print("➕ Added reaction: \(type.emoji) for memory \(memoryID)")
            }
        }

        // Phase 10.1 Module 1.5: Create receipt and broadcast to jar members
        // Create reaction receipt (always create for local storage)
        let payload = ReactionAddedPayload(
            memoryID: memoryID.uuidString,
            reactionType: type.rawValue,
            createdAtMs: Int64(Date().timeIntervalSince1970 * 1000)
        )

        let (cid, _) = try await receiptManager.createReactionReceipt(
            type: ReceiptType.reactionAdded,
            payload: payload,
            parentCID: nil
        )

        print("✅ Reaction receipt created: \(cid)")

        // Get jar members (excluding current user)
        let currentUserDID = try await IdentityManager.shared.getDID()
        let jarMemberDIDs = try await db.readAsync { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT member_did FROM jar_members
                    WHERE jar_id = ? AND member_did != ? AND status = 'active'
                    """,
                arguments: [jarID, currentUserDID]
            )
        }

        // Skip relay broadcast if no other members
        guard !jarMemberDIDs.isEmpty else {
            print("ℹ️ Jar has no other active members - skipping relay broadcast")
            return
        }

        print("📡 Broadcasting reaction to \(jarMemberDIDs.count) jar member(s)...")

        // Get raw CBOR for the reaction receipt
        let rawCBOR = try await db.readAsync { db in
            try UCRHeaderRow.fetchOne(
                db,
                sql: "SELECT * FROM ucr_headers WHERE cid = ?",
                arguments: [cid]
            )?.rawCBOR
        }

        guard let rawCBOR = rawCBOR else {
            print("❌ Failed to fetch reaction receipt CBOR")
            return
        }

        // Lookup devices for all jar members
        let devices = try await DeviceManager.shared.getDevices(for: jarMemberDIDs)
        guard !devices.isEmpty else {
            print("⚠️ No devices found for jar members")
            return
        }

        // Encrypt message for all devices
        let encrypted = try await e2eeManager.encryptMessage(
            receiptCID: cid,
            rawCBOR: rawCBOR,
            recipientDevices: devices
        )

        // Send to relay
        try await relayClient.sendMessage(encrypted)

        print("✅ Reaction broadcast to \(devices.count) device(s)")
    }

    // MARK: - Receive (Phase 10.1 Module 1.5)

    /// Store received reaction from another jar member
    func storeReceivedReaction(
        memoryID: UUID,
        senderDID: String,
        reactionType: ReactionType,
        createdAtMs: Int64
    ) async throws {
        try await db.writeAsync { db in
            // Check if this reaction already exists (idempotency)
            let existing = try Row.fetchOne(
                db,
                sql: "SELECT id FROM reactions WHERE memory_id = ? AND sender_did = ?",
                arguments: [memoryID.uuidString, senderDID]
            )

            if existing != nil {
                // Update existing reaction
                try db.execute(
                    sql: """
                        UPDATE reactions
                        SET reaction_type = ?, created_at = ?
                        WHERE memory_id = ? AND sender_did = ?
                        """,
                    arguments: [
                        reactionType.rawValue,
                        Double(createdAtMs) / 1000.0,
                        memoryID.uuidString,
                        senderDID
                    ]
                )
                print("🔄 Updated received reaction: \(reactionType.emoji) from \(senderDID)")
            } else {
                // Insert new reaction
                try db.execute(
                    sql: """
                        INSERT INTO reactions (id, memory_id, sender_did, reaction_type, created_at)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        UUID().uuidString,
                        memoryID.uuidString,
                        senderDID,
                        reactionType.rawValue,
                        Double(createdAtMs) / 1000.0
                    ]
                )
                print("➕ Stored received reaction: \(reactionType.emoji) from \(senderDID)")
            }
        }
    }

    // MARK: - Delete

    /// Delete all reactions for a memory (called when deleting memory)
    func deleteAllReactions(for memoryID: UUID) async throws {
        try await db.writeAsync { db in
            try db.execute(
                sql: "DELETE FROM reactions WHERE memory_id = ?",
                arguments: [memoryID.uuidString]
            )
        }
    }

    // MARK: - Helper

    private func parseReaction(from row: Row) throws -> Reaction {
        guard let id = UUID(uuidString: row["id"] as String),
              let memoryID = UUID(uuidString: row["memory_id"] as String),
              let senderDID = row["sender_did"] as? String,
              let typeString = row["reaction_type"] as? String,
              let type = ReactionType(rawValue: typeString),
              let timestamp = row["created_at"] as? Double else {
            throw DatabaseError(message: "Failed to parse reaction from row")
        }

        return Reaction(
            id: id,
            memoryID: memoryID,
            senderDID: senderDID,
            type: type,
            createdAt: Date(timeIntervalSince1970: timestamp)
        )
    }
}
