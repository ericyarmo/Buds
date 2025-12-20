//
//  Database.swift
//  Buds
//
//  Core GRDB database manager
//

import GRDB
import Foundation

final class Database {
    static let shared = Database()

    private let dbQueue: DatabaseQueue

    private init() {
        let fileManager = FileManager.default
        let appSupport = try! fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dbPath = appSupport.appendingPathComponent("buds.sqlite").path

        do {
            dbQueue = try DatabaseQueue(path: dbPath)

            #if DEBUG
            // Enable SQL logging in debug
            var config = Configuration()
            config.prepareDatabase { db in
                db.trace { print("📊 SQL: \($0)") }
            }
            #endif

            try migrator.migrate(dbQueue)
            print("✅ Database initialized at: \(dbPath)")
        } catch {
            fatalError("❌ Database initialization failed: \(error)")
        }
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        // In development, erase DB on schema changes for easy iteration
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        // Register migrations
        migrator.registerMigration("v1") { db in
            try createTablesV1(db)
        }

        // Migration v2: Support multiple images per memory
        migrator.registerMigration("v2") { db in
            try migrateToMultipleImages(db)
        }

        // Migration v3: Circle mechanics
        migrator.registerMigration("v3_circles") { db in
            try migrateToCircles(db)
        }

        return migrator
    }

    // MARK: - Public API

    func read<T>(_ block: (GRDB.Database) throws -> T) throws -> T {
        try dbQueue.read(block)
    }

    func write<T>(_ block: (GRDB.Database) throws -> T) throws -> T {
        try dbQueue.write(block)
    }

    // Async versions for use with async/await
    func readAsync<T>(_ block: @escaping (GRDB.Database) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let result = try dbQueue.read(block)
                continuation.resume(returning: result)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func writeAsync<T>(_ block: @escaping (GRDB.Database) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let result = try dbQueue.write(block)
                continuation.resume(returning: result)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - Migration v1

private func createTablesV1(_ db: GRDB.Database) throws {
    // ucr_headers - Universal Content Receipts
    try db.execute(sql: """
        CREATE TABLE ucr_headers (
            cid TEXT PRIMARY KEY NOT NULL,
            did TEXT NOT NULL,
            device_id TEXT NOT NULL,
            parent_cid TEXT,
            root_cid TEXT NOT NULL,
            receipt_type TEXT NOT NULL,
            signature TEXT NOT NULL,
            raw_cbor BLOB NOT NULL,
            payload_json TEXT NOT NULL,
            received_at REAL NOT NULL,
            FOREIGN KEY (parent_cid) REFERENCES ucr_headers(cid) ON DELETE SET NULL
        );

        CREATE INDEX idx_ucr_headers_did ON ucr_headers(did);
        CREATE INDEX idx_ucr_headers_type ON ucr_headers(receipt_type);
        CREATE INDEX idx_ucr_headers_received ON ucr_headers(received_at DESC);
    """)

    // local_receipts - User's local metadata
    try db.execute(sql: """
        CREATE TABLE local_receipts (
            uuid TEXT PRIMARY KEY NOT NULL,
            header_cid TEXT NOT NULL UNIQUE,
            is_favorited INTEGER NOT NULL DEFAULT 0,
            tags_json TEXT,
            local_notes TEXT,
            image_cid TEXT,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            FOREIGN KEY (header_cid) REFERENCES ucr_headers(cid) ON DELETE CASCADE
        );

        CREATE INDEX idx_local_receipts_favorited ON local_receipts(is_favorited);
    """)

    // locations - Fuzzy and precise location data
    try db.execute(sql: """
        CREATE TABLE locations (
            cid TEXT PRIMARY KEY NOT NULL,
            precise_lat REAL NOT NULL,
            precise_lon REAL NOT NULL,
            fuzzy_lat REAL NOT NULL,
            fuzzy_lon REAL NOT NULL,
            location_name TEXT,
            created_at REAL NOT NULL
        );

        CREATE INDEX idx_locations_fuzzy ON locations(fuzzy_lat, fuzzy_lon);
    """)

    // blobs - Photos and attachments
    try db.execute(sql: """
        CREATE TABLE blobs (
            cid TEXT PRIMARY KEY NOT NULL,
            data BLOB NOT NULL,
            mime_type TEXT NOT NULL,
            size_bytes INTEGER NOT NULL,
            created_at REAL NOT NULL
        );
    """)

    // devices - For E2EE multi-device
    try db.execute(sql: """
        CREATE TABLE devices (
            device_id TEXT PRIMARY KEY NOT NULL,
            owner_did TEXT NOT NULL,
            device_name TEXT NOT NULL,
            pubkey_x25519 TEXT NOT NULL,
            pubkey_ed25519 TEXT NOT NULL,
            is_current_device INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            last_synced_at REAL
        );

        CREATE INDEX idx_devices_owner ON devices(owner_did);
    """)

    // circle_members - Friend list
    try db.execute(sql: """
        CREATE TABLE circle_members (
            did TEXT PRIMARY KEY NOT NULL,
            display_name TEXT NOT NULL,
            invite_code TEXT,
            accepted_at REAL,
            added_at REAL NOT NULL,
            removed_at REAL
        );
    """)

    // shared_memories - Track which receipts are shared
    try db.execute(sql: """
        CREATE TABLE shared_memories (
            uuid TEXT PRIMARY KEY NOT NULL,
            header_cid TEXT NOT NULL,
            shared_at REAL NOT NULL,
            recipient_dids_json TEXT NOT NULL,
            FOREIGN KEY (header_cid) REFERENCES ucr_headers(cid) ON DELETE CASCADE
        );

        CREATE INDEX idx_shared_memories_cid ON shared_memories(header_cid);
    """)

    print("✅ Database schema v1 created")
}

// MARK: - Migration v2

private func migrateToMultipleImages(_ db: GRDB.Database) throws {
    // 1. Create new column for multiple image CIDs
    try db.execute(sql: """
        ALTER TABLE local_receipts
        ADD COLUMN image_cids TEXT
    """)

    // 2. Migrate existing single image_cid to image_cids array
    try db.execute(sql: """
        UPDATE local_receipts
        SET image_cids = CASE
            WHEN image_cid IS NOT NULL AND image_cid != ''
            THEN json_array(image_cid)
            ELSE json_array()
        END
    """)

    // 3. Drop old image_cid column (SQLite limitation: recreate table)
    try db.execute(sql: """
        CREATE TABLE local_receipts_new (
            uuid TEXT PRIMARY KEY NOT NULL,
            header_cid TEXT NOT NULL UNIQUE,
            is_favorited INTEGER NOT NULL DEFAULT 0,
            tags_json TEXT,
            local_notes TEXT,
            image_cids TEXT,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            FOREIGN KEY (header_cid) REFERENCES ucr_headers(cid) ON DELETE CASCADE
        )
    """)

    try db.execute(sql: """
        INSERT INTO local_receipts_new
        SELECT uuid, header_cid, is_favorited, tags_json, local_notes, image_cids, created_at, updated_at
        FROM local_receipts
    """)

    try db.execute(sql: "DROP TABLE local_receipts")
    try db.execute(sql: "ALTER TABLE local_receipts_new RENAME TO local_receipts")

    // 4. Recreate index
    try db.execute(sql: """
        CREATE INDEX idx_local_receipts_favorited ON local_receipts(is_favorited)
    """)

    print("✅ Database migrated to v2 (multiple images support)")
}

// MARK: - Migration v3

private func migrateToCircles(_ db: GRDB.Database) throws {
    print("📦 Running migration v3: Circle tables")

    // Create circles table
    try db.execute(sql: """
        CREATE TABLE circles (
            id TEXT PRIMARY KEY NOT NULL,
            did TEXT NOT NULL UNIQUE,
            display_name TEXT NOT NULL,
            phone_number TEXT,
            avatar_cid TEXT,
            pubkey_x25519 TEXT NOT NULL,
            status TEXT NOT NULL,
            joined_at REAL,
            invited_at REAL,
            removed_at REAL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        )
    """)

    // Create indexes for circles
    try db.execute(sql: """
        CREATE INDEX idx_circles_did ON circles(did)
    """)
    try db.execute(sql: """
        CREATE INDEX idx_circles_status ON circles(status)
    """)

    // Update devices table to match new schema
    // Drop and recreate with updated schema
    try db.execute(sql: "DROP TABLE IF EXISTS devices")

    try db.execute(sql: """
        CREATE TABLE devices (
            device_id TEXT PRIMARY KEY NOT NULL,
            owner_did TEXT NOT NULL,
            device_name TEXT NOT NULL,
            pubkey_x25519 TEXT NOT NULL,
            pubkey_ed25519 TEXT NOT NULL,
            status TEXT NOT NULL,
            registered_at REAL NOT NULL,
            last_seen_at REAL
        )
    """)

    try db.execute(sql: """
        CREATE INDEX idx_devices_owner ON devices(owner_did)
    """)
    try db.execute(sql: """
        CREATE INDEX idx_devices_status ON devices(status)
    """)

    print("✅ Migration v3 complete: Circle tables created")
}
