//
//  MemoryRepository.swift
//  Buds
//
//  GRDB repository for memory CRUD operations
//

import Foundation
import GRDB
import Combine

struct MemoryRepository {
    private let db = Database.shared
    private let receiptManager = ReceiptManager.shared

    // MARK: - Fetch

    /// Fetch all memories (most recent first)
    func fetchAll() async throws -> [Memory] {
        try await db.readAsync { db in
            let sql = """
                SELECT
                    lr.uuid,
                    h.cid,
                    h.payload_json,
                    h.received_at,
                    lr.is_favorited,
                    lr.tags_json,
                    lr.local_notes,
                    lr.image_cids,
                    lr.jar_id,
                    rm.sender_did
                FROM local_receipts lr
                JOIN ucr_headers h ON lr.header_cid = h.cid
                LEFT JOIN received_memories rm ON rm.header_cid = h.cid
                WHERE h.receipt_type = ?
                ORDER BY h.received_at DESC
                """

            let rows = try Row.fetchAll(db, sql: sql, arguments: [ReceiptType.sessionCreated])
            return try rows.compactMap { row in
                try parseMemory(from: row, db: db)
            }
        }
    }

    /// Fetch memories for a specific jar (Phase 8)
    func fetchByJar(jarID: String) async throws -> [Memory] {
        try await db.readAsync { db in
            let sql = """
                SELECT
                    lr.uuid,
                    h.cid,
                    h.payload_json,
                    h.received_at,
                    lr.is_favorited,
                    lr.tags_json,
                    lr.local_notes,
                    lr.image_cids,
                    lr.jar_id,
                    rm.sender_did
                FROM local_receipts lr
                JOIN ucr_headers h ON lr.header_cid = h.cid
                LEFT JOIN received_memories rm ON rm.header_cid = h.cid
                WHERE h.receipt_type = ? AND lr.jar_id = ?
                ORDER BY h.received_at DESC
                """

            let rows = try Row.fetchAll(db, sql: sql, arguments: [ReceiptType.sessionCreated, jarID])
            return try rows.compactMap { row in
                try parseMemory(from: row, db: db)
            }
        }
    }

    /// Fetch single memory by ID
    func fetch(id: UUID) async throws -> Memory? {
        try await db.read { db in
            let sql = """
                SELECT
                    lr.uuid,
                    h.cid,
                    h.payload_json,
                    h.received_at,
                    lr.is_favorited,
                    lr.tags_json,
                    lr.local_notes,
                    lr.image_cids,
                    lr.jar_id,
                    rm.sender_did
                FROM local_receipts lr
                JOIN ucr_headers h ON lr.header_cid = h.cid
                LEFT JOIN received_memories rm ON rm.header_cid = h.cid
                WHERE lr.uuid = ?
                """

            guard let row = try Row.fetchOne(db, sql: sql, arguments: [id.uuidString]) else {
                return nil
            }

            return try parseMemory(from: row, db: db)
        }
    }

    // MARK: - Create

    /// Create new memory (creates receipt + local metadata)
    func create(
        strainName: String,
        productType: ProductType,
        rating: Int,
        notes: String?,
        brand: String?,
        thcPercent: Double?,
        cbdPercent: Double?,
        amountGrams: Double?,
        effects: [String],
        consumptionMethod: ConsumptionMethod?,
        locationCID: String? = nil,
        jarID: String = "solo"  // Phase 8: Default to solo jar
    ) async throws -> Memory {

        // Build payload
        let payload = SessionPayload(
            claimedTimeMs: Int64(Date().timeIntervalSince1970 * 1000),
            productName: strainName,
            productType: productType.rawValue,
            rating: rating,
            notes: notes,
            brand: brand,
            thcPercent: thcPercent,
            cbdPercent: cbdPercent,
            amountGrams: amountGrams,
            effects: effects,
            consumptionMethod: consumptionMethod?.rawValue,
            locationCID: locationCID
        )

        // Create receipt
        let (cid, _) = try await receiptManager.createSessionReceipt(
            type: ReceiptType.sessionCreated,
            payload: payload
        )

        // Create local metadata
        let uuid = UUID()
        let now = Date().timeIntervalSince1970

        try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO local_receipts (
                        uuid, header_cid, is_favorited, tags_json, local_notes,
                        image_cids, jar_id, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [uuid.uuidString, cid, false, nil, nil, "[]", jarID, now, now]
            )
        }

        // Return created memory
        return Memory(
            id: uuid,
            receiptCID: cid,
            strainName: strainName,
            productType: productType,
            rating: rating,
            notes: notes,
            brand: brand,
            thcPercent: thcPercent,
            cbdPercent: cbdPercent,
            amountGrams: amountGrams,
            effects: effects,
            consumptionMethod: consumptionMethod,
            createdAt: Date(),
            claimedTimeMs: payload.claimedTimeMs,
            hasLocation: locationCID != nil,
            locationName: nil,
            isFavorited: false,
            isShared: false,
            imageData: [],
            jarID: jarID,
            senderDID: nil
        )
    }

    // MARK: - Update

    /// Toggle favorite status
    func toggleFavorite(id: UUID) async throws {
        try db.write { db in
            try db.execute(
                sql: "UPDATE local_receipts SET is_favorited = NOT is_favorited, updated_at = ? WHERE uuid = ?",
                arguments: [Date().timeIntervalSince1970, id.uuidString]
            )
        }
    }

    // MARK: - Delete

    /// Delete memory (creates tombstone receipt)
    func delete(id: UUID) async throws {
        // TODO: Create tombstone receipt for proper deletion
        // For now, just soft delete from local_receipts

        try db.write { db in
            try db.execute(
                sql: "DELETE FROM local_receipts WHERE uuid = ?",
                arguments: [id.uuidString]
            )
        }
    }

    // MARK: - Images

    /// Add images to a memory (up to 3 total)
    func addImages(to memoryId: UUID, images: [Data]) async throws {
        print("🗄️ MemoryRepo: addImages called with \(images.count) images for memory \(memoryId)")

        try await db.writeAsync { db in
            // Load current image CIDs
            let currentCIDsJSON = try String.fetchOne(
                db,
                sql: "SELECT image_cids FROM local_receipts WHERE uuid = ?",
                arguments: [memoryId.uuidString]
            ) ?? "[]"

            print("🗄️ MemoryRepo: Current CIDs JSON: \(currentCIDsJSON)")
            var imageCIDs = try JSONDecoder().decode([String].self, from: currentCIDsJSON.data(using: .utf8)!)
            print("🗄️ MemoryRepo: Current CIDs array count: \(imageCIDs.count)")

            // Add new images (enforce 3 max)
            for (index, imageData) in images.enumerated() {
                if imageCIDs.count >= 3 {
                    print("🗄️ MemoryRepo: Max 3 images reached, stopping at \(imageCIDs.count)")
                    break
                }

                print("🗄️ MemoryRepo: Processing image \(index + 1)/\(images.count), size: \(imageData.count) bytes")

                // Generate CID for image
                let cid = try self.generateImageCID(data: imageData)
                print("🗄️ MemoryRepo: Generated CID: \(cid)")

                // Store in blobs table
                try db.execute(
                    sql: """
                        INSERT OR REPLACE INTO blobs (cid, data, mime_type, size_bytes, created_at)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [cid, imageData, "image/jpeg", imageData.count, Date().timeIntervalSince1970]
                )
                print("🗄️ MemoryRepo: Inserted blob for CID: \(cid)")

                imageCIDs.append(cid)
            }

            // Update local_receipts with new CIDs
            let updatedJSON = String(data: try JSONEncoder().encode(imageCIDs), encoding: .utf8)!
            print("🗄️ MemoryRepo: Updating image_cids to: \(updatedJSON)")

            try db.execute(
                sql: "UPDATE local_receipts SET image_cids = ?, updated_at = ? WHERE uuid = ?",
                arguments: [updatedJSON, Date().timeIntervalSince1970, memoryId.uuidString]
            )

            print("🗄️ MemoryRepo: Successfully stored \(imageCIDs.count) images")
        }
    }

    /// Remove image from memory by index
    func removeImage(from memoryId: UUID, at index: Int) async throws {
        try await db.writeAsync { db in
            let currentCIDsJSON = try String.fetchOne(
                db,
                sql: "SELECT image_cids FROM local_receipts WHERE uuid = ?",
                arguments: [memoryId.uuidString]
            ) ?? "[]"

            var imageCIDs = try JSONDecoder().decode([String].self, from: currentCIDsJSON.data(using: .utf8)!)

            guard index < imageCIDs.count else { return }

            let removedCID = imageCIDs.remove(at: index)

            // Delete from blobs table
            try db.execute(sql: "DELETE FROM blobs WHERE cid = ?", arguments: [removedCID])

            // Update local_receipts
            let updatedJSON = String(data: try JSONEncoder().encode(imageCIDs), encoding: .utf8)!
            try db.execute(
                sql: "UPDATE local_receipts SET image_cids = ?, updated_at = ? WHERE uuid = ?",
                arguments: [updatedJSON, Date().timeIntervalSince1970, memoryId.uuidString]
            )
        }
    }

    // MARK: - Shared Memories (Phase 7)

    /// Check if a relay message has already been processed (idempotency protection)
    func isMessageProcessed(relayMessageId: String) async throws -> Bool {
        try await db.readAsync { db in
            let count = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM received_memories WHERE relay_message_id = ?",
                arguments: [relayMessageId]
            ) ?? 0
            return count > 0
        }
    }

    /// Store a shared receipt from a Circle member (with raw CBOR from decryption)
    func storeSharedReceipt(receiptCID: String, rawCBOR: Data, signature: String, senderDID: String, senderDeviceId: String, relayMessageId: String) async throws {
        try await db.writeAsync { db in
            // First check if this receipt already exists (might be our own shared receipt)
            let exists = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM ucr_headers WHERE cid = ?",
                arguments: [receiptCID]
            ) ?? 0

            if exists == 0 {
                print("🗄️  [MemoryRepo] Decoding CBOR receipt...")

                // Decode CBOR to extract all fields
                let receipt = try ReceiptCanonicalizer.decodeReceipt(from: rawCBOR)
                print("🗄️  [MemoryRepo] Receipt decoded - type: \(receipt.receiptType)")

                let payload = try ReceiptCanonicalizer.decodeSessionPayload(from: receipt.payloadCBOR)
                print("🗄️  [MemoryRepo] Payload decoded - product: \(payload.productName)")

                // Encode payload to JSON for querying
                let encoder = JSONEncoder()
                encoder.keyEncodingStrategy = .convertToSnakeCase
                let payloadJSON = try String(data: encoder.encode(payload), encoding: .utf8) ?? "{}"

                // Insert into ucr_headers with full data
                try db.execute(
                    sql: """
                        INSERT INTO ucr_headers (
                            cid, did, device_id, parent_cid, root_cid, receipt_type,
                            payload_json, signature, raw_cbor, received_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        receiptCID,
                        senderDID,
                        senderDeviceId,
                        receipt.parentCID,
                        receipt.rootCID,
                        receipt.receiptType,
                        payloadJSON,
                        signature,
                        rawCBOR,
                        Date().timeIntervalSince1970
                    ]
                )
                print("🗄️  [MemoryRepo] Inserted into ucr_headers")

                // Create local_receipts entry for this shared receipt
                let uuid = UUID()
                let now = Date().timeIntervalSince1970
                try db.execute(
                    sql: """
                        INSERT INTO local_receipts (
                            uuid, header_cid, is_favorited, tags_json, local_notes,
                            image_cids, jar_id, sender_did, created_at, updated_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [uuid.uuidString, receiptCID, false, nil, nil, "[]", "solo", senderDID, now, now]
                )
                print("🗄️  [MemoryRepo] Inserted into local_receipts")
            }

            // Create received_memories entry
            try db.execute(
                sql: """
                    INSERT INTO received_memories (
                        id, memory_cid, sender_did, header_cid, permissions,
                        shared_at, received_at, relay_message_id
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(relay_message_id) DO NOTHING
                    """,
                arguments: [
                    UUID().uuidString,
                    receiptCID,
                    senderDID,
                    receiptCID,
                    "view", // Default permission
                    Date().timeIntervalSince1970,
                    Date().timeIntervalSince1970,
                    relayMessageId
                ]
            )

            print("✅ Stored shared receipt \(receiptCID) from \(senderDID)")
        }
    }

    // MARK: - Helpers

    private func parseMemory(from row: Row, db: GRDB.Database) throws -> Memory? {
        let payloadJSON = row["payload_json"] as String
        guard let payloadData = payloadJSON.data(using: .utf8) else { return nil }

        let payload = try JSONDecoder().decode(SessionPayload.self, from: payloadData)

        // Load images from blobs table
        let imageCIDsJSON = (row["image_cids"] as? String) ?? "[]"
        print("🗄️ MemoryRepo: Loading memory, image_cids JSON: \(imageCIDsJSON)")

        let imageCIDs = try JSONDecoder().decode([String].self, from: imageCIDsJSON.data(using: .utf8)!)
        print("🗄️ MemoryRepo: Parsed \(imageCIDs.count) CIDs: \(imageCIDs)")

        // Fetch image data for each CID
        var imageData: [Data] = []
        for (index, cid) in imageCIDs.enumerated() {
            print("🗄️ MemoryRepo: Fetching blob for CID \(index + 1)/\(imageCIDs.count): \(cid)")
            if let data = try Data.fetchOne(
                db,
                sql: "SELECT data FROM blobs WHERE cid = ?",
                arguments: [cid]
            ) {
                print("🗄️ MemoryRepo: Found blob data: \(data.count) bytes")
                imageData.append(data)
            } else {
                print("❌ MemoryRepo: No blob found for CID: \(cid)")
            }
        }

        print("🗄️ MemoryRepo: Loaded \(imageData.count) images for memory")

        // Check if this is a received memory (shared from Circle)
        let senderDID = row["sender_did"] as? String
        let jarID = (row["jar_id"] as? String) ?? "solo"  // Default to solo if missing

        return Memory(
            id: UUID(uuidString: row["uuid"])!,
            receiptCID: row["cid"],
            strainName: payload.productName,
            productType: ProductType(rawValue: payload.productType) ?? .other,
            rating: payload.rating,
            notes: payload.notes,
            brand: payload.brand,
            thcPercent: payload.thcPercent,
            cbdPercent: payload.cbdPercent,
            amountGrams: payload.amountGrams,
            effects: payload.effects,
            consumptionMethod: payload.consumptionMethod.flatMap { ConsumptionMethod(rawValue: $0) },
            createdAt: Date(timeIntervalSince1970: row["received_at"]),
            claimedTimeMs: payload.claimedTimeMs,
            hasLocation: payload.locationCID != nil,
            locationName: nil,  // TODO: Join with locations table
            isFavorited: (row["is_favorited"] as Int) == 1,
            isShared: senderDID != nil,  // Shared if received from someone
            imageData: imageData,
            jarID: jarID,
            senderDID: senderDID
        )
    }

    private func generateImageCID(data: Data) throws -> String {
        // Simple CID generation using SHA256 hash
        // Format: "bafyrei" + base32(sha256(data))
        let hash = SHA256.hash(data: data)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        return "bafyrei\(hashString.prefix(32))"
    }
}

import CryptoKit
