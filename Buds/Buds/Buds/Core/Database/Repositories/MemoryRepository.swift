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
                    lr.image_cid
                FROM local_receipts lr
                JOIN ucr_headers h ON lr.header_cid = h.cid
                WHERE h.receipt_type = ?
                ORDER BY h.received_at DESC
                """

            let rows = try Row.fetchAll(db, sql: sql, arguments: [ReceiptType.sessionCreated])
            return try rows.compactMap { row in
                try parseMemory(from: row)
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
                    lr.image_cid
                FROM local_receipts lr
                JOIN ucr_headers h ON lr.header_cid = h.cid
                WHERE lr.uuid = ?
                """

            guard let row = try Row.fetchOne(db, sql: sql, arguments: [id.uuidString]) else {
                return nil
            }

            return try parseMemory(from: row)
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
                        image_cid, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [uuid.uuidString, cid, false, nil, nil, nil, now, now]
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
            imageData: nil
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

    // MARK: - Helpers

    private func parseMemory(from row: Row) throws -> Memory? {
        let payloadJSON = row["payload_json"] as String
        guard let payloadData = payloadJSON.data(using: .utf8) else { return nil }

        let payload = try JSONDecoder().decode(SessionPayload.self, from: payloadData)

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
            imageData: nil  // TODO: Load from blobs if image_cid present
        )
    }
}
