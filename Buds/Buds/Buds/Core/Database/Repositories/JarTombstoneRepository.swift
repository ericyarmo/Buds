/**
 * JarTombstoneRepository (Phase 10.3 Module 3)
 *
 * Manages tombstones for deleted jars.
 *
 * Purpose: Prevent processing late-arriving receipts for locally-deleted jars
 *
 * Tombstone Creation:
 * - When user deletes jar → create tombstone + jar.deleted receipt
 * - When jar.deleted receipt received → create tombstone + delete local jar
 *
 * Tombstone Checking:
 * - Before processing any jar receipt → check if jar is tombstoned
 * - If tombstoned → skip receipt (jar no longer exists)
 *
 * Schema (from migration v8):
 * CREATE TABLE jar_tombstones (
 *     jar_id TEXT PRIMARY KEY,
 *     jar_name TEXT NOT NULL,
 *     deleted_at REAL NOT NULL,
 *     deleted_by_did TEXT NOT NULL
 * )
 */

import Foundation
import GRDB

class JarTombstoneRepository {
    static let shared = JarTombstoneRepository()

    private let db: Database

    private init() {
        self.db = Database.shared
    }

    // MARK: - Create Tombstone

    /**
     * Create tombstone for deleted jar
     *
     * Called when:
     * 1. User locally deletes jar (JarManager.deleteJar)
     * 2. jar.deleted receipt received (JarSyncManager.applyJarDeleted)
     */
    func create(jarID: String, jarName: String, deletedByDID: String) async throws {
        try await db.writeAsync { db in
            try db.execute(sql: """
                INSERT OR IGNORE INTO jar_tombstones (jar_id, jar_name, deleted_at, deleted_by_did)
                VALUES (?, ?, ?, ?)
            """, arguments: [jarID, jarName, Date().timeIntervalSince1970, deletedByDID])
        }

        print("🪦 Created tombstone for jar: \(jarName) (\(jarID))")
    }

    // MARK: - Check Tombstone

    /**
     * Check if jar is tombstoned (deleted)
     *
     * Used by JarSyncManager to skip receipts for deleted jars
     */
    func isTombstoned(_ jarID: String) async throws -> Bool {
        try await db.readAsync { db in
            let count = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM jar_tombstones WHERE jar_id = ?",
                arguments: [jarID]
            ) ?? 0
            return count > 0
        }
    }

    /**
     * Get tombstone details (for debugging)
     */
    func getTombstone(_ jarID: String) async throws -> JarTombstone? {
        try await db.readAsync { db in
            try JarTombstone.fetchOne(
                db,
                sql: "SELECT * FROM jar_tombstones WHERE jar_id = ?",
                arguments: [jarID]
            )
        }
    }

    // MARK: - Delete Tombstone (Rare)

    /**
     * Delete tombstone (rare - only for testing or cleanup)
     *
     * NOT typically used in production (tombstones are permanent)
     */
    func deleteTombstone(_ jarID: String) async throws {
        try await db.writeAsync { db in
            try db.execute(sql: "DELETE FROM jar_tombstones WHERE jar_id = ?", arguments: [jarID])
        }
    }
}

// MARK: - Model

struct JarTombstone: Codable, FetchableRecord {
    let jarID: String
    let jarName: String
    let deletedAt: TimeInterval
    let deletedByDID: String

    enum CodingKeys: String, CodingKey {
        case jarID = "jar_id"
        case jarName = "jar_name"
        case deletedAt = "deleted_at"
        case deletedByDID = "deleted_by_did"
    }
}
