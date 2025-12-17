//
//  MemoryRepository.swift
//  Buds
//
//  GRDB repository for memory CRUD operations
//

import Foundation
import GRDB

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
                    lr.image_cids
                FROM local_receipts lr
                JOIN ucr_headers h ON lr.header_cid = h.cid
                WHERE h.receipt_type = ?
                ORDER BY h.received_at DESC
                """

            let rows = try Row.fetchAll(db, sql: sql, arguments: [ReceiptType.sessionCreated])
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
                    lr.image_cids
                FROM local_receipts lr
                JOIN ucr_headers h ON lr.header_cid = h.cid
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
        locationCID: String? = nil
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
                        image_cids, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [uuid.uuidString, cid, false, nil, nil, "[]", now, now]
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
            imageData: []
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
        try await db.writeAsync { db in
            // Load current image CIDs
            let currentCIDsJSON = try String.fetchOne(
                db,
                sql: "SELECT image_cids FROM local_receipts WHERE uuid = ?",
                arguments: [memoryId.uuidString]
            ) ?? "[]"

            var imageCIDs = try JSONDecoder().decode([String].self, from: currentCIDsJSON.data(using: .utf8)!)

            // Add new images (enforce 3 max)
            for imageData in images {
                if imageCIDs.count >= 3 { break }

                // Generate CID for image
                let cid = try self.generateImageCID(data: imageData)

                // Store in blobs table
                try db.execute(
                    sql: """
                        INSERT OR REPLACE INTO blobs (cid, data, mime_type, size_bytes, created_at)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [cid, imageData, "image/jpeg", imageData.count, Date().timeIntervalSince1970]
                )

                imageCIDs.append(cid)
            }

            // Update local_receipts with new CIDs
            let updatedJSON = String(data: try JSONEncoder().encode(imageCIDs), encoding: .utf8)!
            try db.execute(
                sql: "UPDATE local_receipts SET image_cids = ?, updated_at = ? WHERE uuid = ?",
                arguments: [updatedJSON, Date().timeIntervalSince1970, memoryId.uuidString]
            )
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

    // MARK: - Helpers

    private func parseMemory(from row: Row, db: GRDB.Database) throws -> Memory? {
        let payloadJSON = row["payload_json"] as String
        guard let payloadData = payloadJSON.data(using: .utf8) else { return nil }

        let payload = try JSONDecoder().decode(SessionPayload.self, from: payloadData)

        // Load images from blobs table
        let imageCIDsJSON = (row["image_cids"] as? String) ?? "[]"
        let imageCIDs = try JSONDecoder().decode([String].self, from: imageCIDsJSON.data(using: .utf8)!)

        // Fetch image data for each CID
        var imageData: [Data] = []
        for cid in imageCIDs {
            if let data = try Data.fetchOne(
                db,
                sql: "SELECT data FROM blobs WHERE cid = ?",
                arguments: [cid]
            ) {
                imageData.append(data)
            }
        }

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
            isShared: false,  // TODO: Check shared_memories table
            imageData: imageData
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
