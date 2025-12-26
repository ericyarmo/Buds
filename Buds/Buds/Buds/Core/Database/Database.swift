//
//  Database.swift
//  Buds
//
//  Core GRDB database manager
//

import GRDB
import Foundation
import Combine

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

        // Migration v4: Received memories (Phase 7)
        migrator.registerMigration("v4_received_memories") { db in
            try migrateToReceivedMemories(db)
        }

        // Migration v5: Jar architecture (Phase 8)
        migrator.registerMigration("v5_jars") { db in
            try migrateToJars(db)
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

// MARK: - Migration v4 (Phase 7)

private func migrateToReceivedMemories(_ db: GRDB.Database) throws {
    print("📦 Running migration v4: Received memories")

    // Create received_memories table
    try db.execute(sql: """
        CREATE TABLE received_memories (
            id TEXT PRIMARY KEY NOT NULL,
            memory_cid TEXT NOT NULL,
            sender_did TEXT NOT NULL,
            header_cid TEXT NOT NULL,
            permissions TEXT NOT NULL,
            shared_at REAL NOT NULL,
            received_at REAL NOT NULL,
            relay_message_id TEXT NOT NULL UNIQUE,
            FOREIGN KEY (header_cid) REFERENCES ucr_headers(cid) ON DELETE CASCADE
        )
    """)

    // Create indexes for received_memories
    try db.execute(sql: """
        CREATE INDEX idx_received_memories_sender ON received_memories(sender_did)
    """)
    try db.execute(sql: """
        CREATE INDEX idx_received_memories_received ON received_memories(received_at DESC)
    """)
    try db.execute(sql: """
        CREATE INDEX idx_received_memories_relay_msg ON received_memories(relay_message_id)
    """)

    print("✅ Migration v4 complete: Received memories table created")
}

// MARK: - Migration v5: Jar Architecture (Phase 8)

private func migrateToJars(_ db: GRDB.Database) throws {
    let now = Date().timeIntervalSince1970

    print("🔧 [MIGRATION v5] Starting jar architecture migration...")

    // STEP 1: Create jars table
    try db.execute(sql: """
        CREATE TABLE IF NOT EXISTS jars (
          id TEXT PRIMARY KEY NOT NULL,
          name TEXT NOT NULL,
          description TEXT,
          owner_did TEXT NOT NULL,
          created_at REAL NOT NULL,
          updated_at REAL NOT NULL
        );
    """)

    try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_jars_owner_did ON jars(owner_did);
    """)

    print("✅ [MIGRATION v5] Created jars table")

    // STEP 2: Create jar_members table
    try db.execute(sql: """
        CREATE TABLE IF NOT EXISTS jar_members (
          jar_id TEXT NOT NULL,
          member_did TEXT NOT NULL,
          display_name TEXT NOT NULL,
          phone_number TEXT,
          avatar_cid TEXT,
          pubkey_x25519 TEXT NOT NULL,
          role TEXT NOT NULL DEFAULT 'member',
          status TEXT NOT NULL DEFAULT 'active',
          joined_at REAL,
          invited_at REAL,
          removed_at REAL,
          created_at REAL NOT NULL,
          updated_at REAL NOT NULL,
          PRIMARY KEY (jar_id, member_did),
          FOREIGN KEY (jar_id) REFERENCES jars(id) ON DELETE CASCADE
        );
    """)

    try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_jar_members_jar_id ON jar_members(jar_id);
        CREATE INDEX IF NOT EXISTS idx_jar_members_member_did ON jar_members(member_did);
        CREATE INDEX IF NOT EXISTS idx_jar_members_status ON jar_members(jar_id, status);
    """)

    print("✅ [MIGRATION v5] Created jar_members table")

    // STEP 3: Add jar_id and sender_did columns to local_receipts (MUST happen even on fresh install)
    let jarIDColumnExists = try Bool.fetchOne(db, sql: """
        SELECT COUNT(*) > 0 FROM pragma_table_info('local_receipts')
        WHERE name='jar_id'
    """) ?? false

    if !jarIDColumnExists {
        try db.execute(sql: """
            ALTER TABLE local_receipts ADD COLUMN jar_id TEXT NOT NULL DEFAULT 'solo'
        """)
        print("✅ [MIGRATION v5] Added jar_id column to local_receipts")
    }

    let senderDIDColumnExists = try Bool.fetchOne(db, sql: """
        SELECT COUNT(*) > 0 FROM pragma_table_info('local_receipts')
        WHERE name='sender_did'
    """) ?? false

    if !senderDIDColumnExists {
        try db.execute(sql: """
            ALTER TABLE local_receipts ADD COLUMN sender_did TEXT
        """)
        print("✅ [MIGRATION v5] Added sender_did column to local_receipts")
    }

    // Create indexes
    try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_local_receipts_jar_id ON local_receipts(jar_id)
    """)

    // STEP 4: Get current user's DID (from active device)
    let currentUserDID = try String.fetchOne(db, sql: """
        SELECT owner_did FROM devices WHERE status = 'active' LIMIT 1
    """)

    // If no device exists yet (fresh install), skip Solo jar creation
    // It will be created when user first logs in
    guard let ownerDID = currentUserDID else {
        print("⚠️  [MIGRATION v5] No active device found - skipping Solo jar creation (will create on first login)")
        print("🎉 [MIGRATION v5] Migration complete (tables created, Solo jar deferred)")
        return
    }

    print("🔧 [MIGRATION v5] Current user DID: \(ownerDID)")

    // STEP 4: Create "Solo" jar
    let soloJarExists = try Bool.fetchOne(db, sql: """
        SELECT COUNT(*) > 0 FROM jars WHERE id = 'solo'
    """) ?? false

    if !soloJarExists {
        try db.execute(sql: """
            INSERT INTO jars (id, name, description, owner_did, created_at, updated_at)
            VALUES ('solo', 'Solo', 'Your private buds', ?, ?, ?)
        """, arguments: [ownerDID, now, now])

        print("✅ [MIGRATION v5] Created Solo jar")
    }

    // STEP 5: Add current user as owner of Solo jar
    try db.execute(sql: """
        INSERT OR IGNORE INTO jar_members (
          jar_id, member_did, display_name, phone_number, avatar_cid,
          pubkey_x25519, role, status, created_at, updated_at
        )
        SELECT
          'solo' AS jar_id,
          d.owner_did AS member_did,
          'You' AS display_name,
          NULL AS phone_number,
          NULL AS avatar_cid,
          d.pubkey_x25519,
          'owner' AS role,
          'active' AS status,
          ? AS created_at,
          ? AS updated_at
        FROM devices d
        WHERE d.status = 'active'
        LIMIT 1
    """, arguments: [now, now])

    print("✅ [MIGRATION v5] Added current user as owner of Solo jar")

    // STEP 6: Migrate Circle members to jar_members (if circles table exists)
    let circlesTableExists = try Bool.fetchOne(db, sql: """
        SELECT COUNT(*) > 0 FROM sqlite_master
        WHERE type='table' AND name='circles'
    """) ?? false

    if circlesTableExists {
        let circleCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM circles") ?? 0
        print("🔧 [MIGRATION v5] Migrating \(circleCount) Circle members to Solo jar...")

        try db.execute(sql: """
            INSERT OR IGNORE INTO jar_members (
              jar_id, member_did, display_name, phone_number, avatar_cid,
              pubkey_x25519, role, status, joined_at, invited_at, removed_at,
              created_at, updated_at
            )
            SELECT
              'solo' AS jar_id,
              c.did AS member_did,
              c.display_name,
              c.phone_number,
              c.avatar_cid,
              c.pubkey_x25519,
              'member' AS role,
              c.status,
              c.joined_at,
              c.invited_at,
              c.removed_at,
              c.created_at,
              c.updated_at
            FROM circles c
        """)

        // VERIFICATION: Check migration succeeded
        let jarMemberCount = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM jar_members WHERE jar_id = 'solo'
        """) ?? 0

        // Subtract 1 for current user (already added as owner)
        let migratedCount = jarMemberCount - 1

        print("🔧 [MIGRATION v5] Migrated \(migratedCount) Circle members (expected \(circleCount))")

        // Drop circles table
        try db.execute(sql: "DROP TABLE IF EXISTS circles")
        print("✅ [MIGRATION v5] Dropped old circles table")
    } else {
        print("⚠️  [MIGRATION v5] No circles table found, skipping Circle member migration")
    }

    // STEP 7: Update all existing memories to belong to Solo jar (explicitly set)
    try db.execute(sql: """
        UPDATE local_receipts SET jar_id = 'solo'
        WHERE jar_id IS NULL OR jar_id = ''
    """)

    let memoryCount = try Int.fetchOne(db, sql: """
        SELECT COUNT(*) FROM local_receipts WHERE jar_id = 'solo'
    """) ?? 0

    print("✅ [MIGRATION v5] Migrated \(memoryCount) buds to Solo jar")
    print("🎉 [MIGRATION v5] Migration complete!")
}

struct DatabaseError: Error {
    let message: String
}

