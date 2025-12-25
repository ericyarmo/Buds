# Phase 8: Database Migration + Jar Architecture

**Status**: Ready to Execute
**Date**: December 25, 2025
**Estimated Time**: 3-4 hours
**Difficulty**: High (Core architecture change)
**Risk**: Medium (backward compatibility critical)

---

## Overview

**Goal**: Transform from single Circle (implicit) to multiple Jars (explicit containers)

**What's Changing**:
- `circles` table → `jars` + `jar_members` tables (N:M relationship)
- Memories (buds) scoped to jars (`jar_id` column added)
- UI terminology: Circle → Jar, Memory → Bud

**What's NOT Changing** (Core Physics):
- ✅ E2EE encryption (X25519 + AES-256-GCM)
- ✅ Receipt verification (CID + Ed25519 signatures)
- ✅ Device management
- ✅ Relay communication
- ✅ UCR kernel (receipts, CBOR encoding)

**Key Insight**: E2EE encryption logic stays identical. We just change WHO we encrypt for (jar members instead of all Circle members).

---

## Current Architecture (Phase 7)

### Database Schema

```sql
-- circles table (stores Circle members)
CREATE TABLE circles (
  id TEXT PRIMARY KEY,
  did TEXT NOT NULL,
  display_name TEXT NOT NULL,
  phone_number TEXT,
  avatar_cid TEXT,
  pubkey_x25519 TEXT NOT NULL,
  status TEXT NOT NULL,  -- 'pending', 'active', 'removed'
  joined_at REAL,
  invited_at REAL,
  removed_at REAL,
  created_at REAL NOT NULL,
  updated_at REAL NOT NULL
);

CREATE INDEX idx_circles_did ON circles(did);
CREATE INDEX idx_circles_status ON circles(status);

-- local_receipts (memories)
CREATE TABLE local_receipts (
  uuid TEXT PRIMARY KEY NOT NULL,
  header_cid TEXT NOT NULL UNIQUE,
  is_favorited INTEGER NOT NULL DEFAULT 0,
  tags_json TEXT,
  local_notes TEXT,
  image_cids TEXT,  -- JSON array (Phase 3)
  created_at REAL NOT NULL,
  updated_at REAL NOT NULL,
  FOREIGN KEY (header_cid) REFERENCES ucr_headers(cid) ON DELETE CASCADE
);
```

### Problem with Current Design

1. **No Jar Entity**: "Circle" is implicit (all active members = your Circle)
2. **Global Memories**: All memories are global (not scoped to any Circle/Jar)
3. **Single Sharing Context**: Share memory → All Circle members get it
4. **Can't Have Multiple Jars**: No way to have "Friends" jar separate from "Tahoe Trip" jar

---

## New Architecture (Phase 8)

### Database Schema

```sql
-- jars table (the container itself)
CREATE TABLE jars (
  id TEXT PRIMARY KEY NOT NULL,  -- UUID v4
  name TEXT NOT NULL,  -- "Solo", "Friends", "Tahoe Trip"
  description TEXT,  -- Optional
  owner_did TEXT NOT NULL,  -- Creator's DID
  created_at REAL NOT NULL,
  updated_at REAL NOT NULL
);

CREATE INDEX idx_jars_owner_did ON jars(owner_did);

-- jar_members table (N:M relationship: jars ↔ people)
CREATE TABLE jar_members (
  jar_id TEXT NOT NULL,
  member_did TEXT NOT NULL,
  display_name TEXT NOT NULL,
  phone_number TEXT,
  avatar_cid TEXT,
  pubkey_x25519 TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'member',  -- 'owner' or 'member'
  status TEXT NOT NULL DEFAULT 'active',  -- 'pending', 'active', 'removed'
  joined_at REAL,
  invited_at REAL,
  removed_at REAL,
  created_at REAL NOT NULL,
  updated_at REAL NOT NULL,
  PRIMARY KEY (jar_id, member_did),
  FOREIGN KEY (jar_id) REFERENCES jars(id) ON DELETE CASCADE
);

CREATE INDEX idx_jar_members_jar_id ON jar_members(jar_id);
CREATE INDEX idx_jar_members_member_did ON jar_members(member_did);
CREATE INDEX idx_jar_members_status ON jar_members(jar_id, status);

-- local_receipts (buds) - ADD jar_id column
ALTER TABLE local_receipts ADD COLUMN jar_id TEXT NOT NULL DEFAULT 'solo';
ALTER TABLE local_receipts ADD COLUMN sender_did TEXT;  -- For received buds

CREATE INDEX idx_local_receipts_jar_id ON local_receipts(jar_id);

-- Add foreign key constraint AFTER migration data
-- (can't add constraint before jar exists)
```

### Key Changes

1. **Jars are explicit entities** (not implicit like Circle)
2. **N:M relationship**: Jars ↔ People (via jar_members)
3. **Buds scoped to jars**: Each bud belongs to exactly one jar
4. **Multiple jars per user**: Can have "Solo", "Friends", "Tahoe Trip", etc.
5. **Role-based access**: Owner vs Member (future: permissions)

---

## Migration Strategy

### Step 1: Create New Tables (Safe - No Data Loss)

```sql
-- Migration v5: Jar architecture

-- 1. Create jars table
CREATE TABLE IF NOT EXISTS jars (
  id TEXT PRIMARY KEY NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  owner_did TEXT NOT NULL,
  created_at REAL NOT NULL,
  updated_at REAL NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_jars_owner_did ON jars(owner_did);

-- 2. Create jar_members table
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

CREATE INDEX IF NOT EXISTS idx_jar_members_jar_id ON jar_members(jar_id);
CREATE INDEX IF NOT EXISTS idx_jar_members_member_did ON jar_members(member_did);
CREATE INDEX IF NOT EXISTS idx_jar_members_status ON jar_members(jar_id, status);
```

---

### Step 2: Create Default "Solo" Jar

**Logic**:
- Every user gets a "Solo" jar by default
- Solo jar = private (just you)
- All existing memories migrate to Solo jar

```sql
-- 3. Insert "Solo" jar for current user
INSERT INTO jars (id, name, description, owner_did, created_at, updated_at)
SELECT
  'solo' AS id,
  'Solo' AS name,
  'Your private buds' AS description,
  (SELECT did FROM devices WHERE status = 'active' LIMIT 1) AS owner_did,
  ? AS created_at,
  ? AS updated_at
WHERE NOT EXISTS (SELECT 1 FROM jars WHERE id = 'solo');

-- 4. Add current user as owner of Solo jar
INSERT INTO jar_members (jar_id, member_did, display_name, phone_number, avatar_cid, pubkey_x25519, role, status, created_at, updated_at)
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
ON CONFLICT (jar_id, member_did) DO NOTHING;
```

**CRITICAL**: We need to get the current user's DID from the `devices` table (WHERE status = 'active' is the current device).

---

### Step 3: Migrate Existing Circle Members to Solo Jar

**Logic**:
- All Circle members become members of Solo jar
- Preserve their display names, phone numbers, pubkeys
- Status maps directly (pending → pending, active → active)

```sql
-- 5. Migrate Circle members to jar_members (Solo jar)
INSERT INTO jar_members (
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
  'member' AS role,  -- Circle members become regular members (not owners)
  c.status,
  c.joined_at,
  c.invited_at,
  c.removed_at,
  c.created_at,
  c.updated_at
FROM circles c
ON CONFLICT (jar_id, member_did) DO NOTHING;  -- Skip if already exists (e.g., current user)
```

**Result**: All Circle members now in jar_members table, scoped to 'solo' jar.

---

### Step 4: Add jar_id Column to local_receipts

**Logic**:
- Add jar_id column (defaults to 'solo')
- All existing memories scoped to Solo jar
- Add sender_did for received memories (Phase 7)

```sql
-- 6. Add jar_id column to local_receipts
ALTER TABLE local_receipts ADD COLUMN jar_id TEXT NOT NULL DEFAULT 'solo';

-- 7. Add sender_did column (for received buds from jar members)
ALTER TABLE local_receipts ADD COLUMN sender_did TEXT;

-- 8. Create index for jar_id lookups
CREATE INDEX IF NOT EXISTS idx_local_receipts_jar_id ON local_receipts(jar_id);

-- 9. Update all existing memories to belong to Solo jar (explicitly)
UPDATE local_receipts SET jar_id = 'solo' WHERE jar_id IS NULL OR jar_id = '';
```

**Result**: All existing memories now scoped to Solo jar (jar_id = 'solo').

---

### Step 5: Drop Old circles Table

**CRITICAL**: Only drop after verifying migration succeeded.

```sql
-- 10. Drop old circles table (replaced by jar_members)
-- SAFETY CHECK: Verify jar_members has same number of rows as circles
-- If counts don't match, ROLLBACK migration

-- Count check (in Swift, not SQL):
-- let circleCount = try db.scalar("SELECT COUNT(*) FROM circles") ?? 0
-- let jarMemberCount = try db.scalar("SELECT COUNT(*) FROM jar_members WHERE jar_id = 'solo'") ?? 0
-- guard circleCount == jarMemberCount else { throw MigrationError.dataMismatch }

DROP TABLE IF EXISTS circles;
```

**IMPORTANT**: Execute DROP only if data verification passes.

---

## Swift Implementation

### File Structure

```
Buds/Core/
├── Models/
│   ├── Jar.swift (NEW)
│   ├── JarMember.swift (NEW)
│   ├── Memory.swift (MODIFY: add jarID)
│   └── ...
├── Database/
│   ├── Database.swift (MODIFY: add migration v5)
│   └── Repositories/
│       ├── JarRepository.swift (NEW)
│       └── MemoryRepository.swift (MODIFY: filter by jar)
└── JarManager.swift (RENAME from CircleManager)
```

---

### 1. Create Jar.swift (NEW)

**Location**: `Buds/Core/Models/Jar.swift`

```swift
//
//  Jar.swift
//  Buds
//
//  Shared, encrypted space (max 12 people, unlimited buds)
//

import Foundation
import GRDB

struct Jar: Identifiable, Codable, FetchableRecord, PersistableRecord {
    var id: String  // UUID
    var name: String  // "Solo", "Friends", "Tahoe Trip"
    var description: String?
    var ownerDID: String
    var createdAt: Date
    var updatedAt: Date

    // MARK: - Database

    static let databaseTableName = "jars"

    enum Columns {
        static let id = Column("id")
        static let name = Column("name")
        static let description = Column("description")
        static let ownerDID = Column("owner_did")
        static let createdAt = Column("created_at")
        static let updatedAt = Column("updated_at")
    }

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case ownerDID = "owner_did"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Relationships

extension Jar {
    // Get members of this jar
    static let members = hasMany(JarMember.self, using: ForeignKey(["jar_id"]))
}

// MARK: - Computed Properties

extension Jar {
    var isSolo: Bool {
        return id == "solo"
    }
}
```

---

### 2. Create JarMember.swift (NEW)

**Location**: `Buds/Core/Models/JarMember.swift`

```swift
//
//  JarMember.swift
//  Buds
//
//  A person in a jar (N:M relationship)
//

import Foundation
import GRDB

struct JarMember: Codable, FetchableRecord, PersistableRecord {
    var jarID: String
    var memberDID: String
    var displayName: String
    var phoneNumber: String?
    var avatarCID: String?
    var pubkeyX25519: String
    var role: Role
    var status: Status
    var joinedAt: Date?
    var invitedAt: Date?
    var removedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    enum Role: String, Codable {
        case owner = "owner"
        case member = "member"
    }

    enum Status: String, Codable {
        case pending = "pending"
        case active = "active"
        case removed = "removed"
    }

    // MARK: - Database

    static let databaseTableName = "jar_members"

    enum Columns {
        static let jarID = Column("jar_id")
        static let memberDID = Column("member_did")
        static let displayName = Column("display_name")
        static let phoneNumber = Column("phone_number")
        static let avatarCID = Column("avatar_cid")
        static let pubkeyX25519 = Column("pubkey_x25519")
        static let role = Column("role")
        static let status = Column("status")
        static let joinedAt = Column("joined_at")
        static let invitedAt = Column("invited_at")
        static let removedAt = Column("removed_at")
        static let createdAt = Column("created_at")
        static let updatedAt = Column("updated_at")
    }

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case jarID = "jar_id"
        case memberDID = "member_did"
        case displayName = "display_name"
        case phoneNumber = "phone_number"
        case avatarCID = "avatar_cid"
        case pubkeyX25519 = "pubkey_x25519"
        case role
        case status
        case joinedAt = "joined_at"
        case invitedAt = "invited_at"
        case removedAt = "removed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Identifiable (for SwiftUI)

extension JarMember: Identifiable {
    var id: String { "\(jarID)-\(memberDID)" }  // Composite key
}

// MARK: - Relationships

extension JarMember {
    static let jar = belongsTo(Jar.self, using: ForeignKey(["jar_id"]))
}
```

---

### 3. Update Memory.swift (MODIFY)

**Location**: `Buds/Core/Models/Memory.swift`

**Changes**: Add `jarID` and `senderDID` properties

```swift
// ADD these properties to Memory struct

struct Memory: Identifiable, Codable {
    let id: UUID
    let receiptCID: String

    // ... existing properties ...

    // NEW: Jar scoping
    var jarID: String  // Which jar this bud belongs to
    var senderDID: String?  // If received from jar member (nil if created by you)

    // ... rest of properties ...
}

// UPDATE CodingKeys enum

enum CodingKeys: String, CodingKey {
    // ... existing keys ...
    case jarID = "jar_id"
    case senderDID = "sender_did"
}
```

**CRITICAL**: Ensure `jarID` is NOT optional. Every bud must belong to exactly one jar.

---

### 4. Create Database Migration v5

**Location**: `Buds/Core/Database/Database.swift`

**Add to migrator**:

```swift
// In Database.swift private var migrator: DatabaseMigrator

// Migration v5: Jar architecture
migrator.registerMigration("v5_jars") { db in
    try migrateToJars(db)
}
```

**Create migration function**:

```swift
// MARK: - Migration v5: Jar Architecture

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

    // STEP 3: Get current user's DID (from active device)
    let currentUserDID = try String.fetchOne(db, sql: """
        SELECT owner_did FROM devices WHERE status = 'active' LIMIT 1
    """)

    guard let ownerDID = currentUserDID else {
        throw DatabaseError(message: "No active device found - cannot determine current user")
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

    // STEP 7: Add jar_id column to local_receipts
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

    // STEP 8: Add sender_did column to local_receipts (for received buds)
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

    // STEP 9: Create indexes
    try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_local_receipts_jar_id ON local_receipts(jar_id)
    """)

    // STEP 10: Update all existing memories to belong to Solo jar (explicitly set)
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
```

**CRITICAL CHECKS**:
1. Verify current user DID exists (active device)
2. Verify Circle member count matches jar_members count
3. Verify all memories have jar_id = 'solo'
4. Drop circles table ONLY after verification

---

### 5. Create JarRepository.swift (NEW)

**Location**: `Buds/Core/Database/Repositories/JarRepository.swift`

```swift
//
//  JarRepository.swift
//  Buds
//
//  CRUD operations for jars and jar members
//

import Foundation
import GRDB

final class JarRepository {
    static let shared = JarRepository()

    private init() {}

    // MARK: - Jar CRUD

    func getAllJars() async throws -> [Jar] {
        try await Database.shared.readAsync { db in
            try Jar.fetchAll(db)
        }
    }

    func getJar(id: String) async throws -> Jar? {
        try await Database.shared.readAsync { db in
            try Jar.fetchOne(db, key: id)
        }
    }

    func createJar(name: String, description: String?, ownerDID: String) async throws -> Jar {
        let jar = Jar(
            id: UUID().uuidString,
            name: name,
            description: description,
            ownerDID: ownerDID,
            createdAt: Date(),
            updatedAt: Date()
        )

        try await Database.shared.writeAsync { db in
            try jar.insert(db)

            // Add owner as first member
            let owner = JarMember(
                jarID: jar.id,
                memberDID: ownerDID,
                displayName: "You",
                phoneNumber: nil,
                avatarCID: nil,
                pubkeyX25519: try await DeviceManager.shared.getCurrentDevice().pubkeyX25519,
                role: .owner,
                status: .active,
                joinedAt: Date(),
                invitedAt: nil,
                removedAt: nil,
                createdAt: Date(),
                updatedAt: Date()
            )
            try owner.insert(db)
        }

        return jar
    }

    func deleteJar(id: String) async throws {
        try await Database.shared.writeAsync { db in
            try Jar.deleteOne(db, key: id)
        }
    }

    // MARK: - Jar Members CRUD

    func getMembers(jarID: String) async throws -> [JarMember] {
        try await Database.shared.readAsync { db in
            try JarMember
                .filter(Column("jar_id") == jarID)
                .filter(Column("status") == "active")
                .fetchAll(db)
        }
    }

    func addMember(
        jarID: String,
        memberDID: String,
        displayName: String,
        phoneNumber: String?,
        pubkeyX25519: String
    ) async throws {
        let member = JarMember(
            jarID: jarID,
            memberDID: memberDID,
            displayName: displayName,
            phoneNumber: phoneNumber,
            avatarCID: nil,
            pubkeyX25519: pubkeyX25519,
            role: .member,
            status: .active,
            joinedAt: Date(),
            invitedAt: Date(),
            removedAt: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        try await Database.shared.writeAsync { db in
            try member.insert(db)
        }
    }

    func removeMember(jarID: String, memberDID: String) async throws {
        try await Database.shared.writeAsync { db in
            try db.execute(
                sql: """
                    UPDATE jar_members
                    SET status = 'removed', removed_at = ?, updated_at = ?
                    WHERE jar_id = ? AND member_did = ?
                """,
                arguments: [Date().timeIntervalSince1970, Date().timeIntervalSince1970, jarID, memberDID]
            )
        }
    }

    // MARK: - Helper: Get jars where user is a member

    func getJarsForUser(did: String) async throws -> [Jar] {
        try await Database.shared.readAsync { db in
            try Jar
                .joining(required: Jar.members.filter(Column("member_did") == did && Column("status") == "active"))
                .fetchAll(db)
        }
    }
}
```

---

### 6. Update MemoryRepository.swift (MODIFY)

**Location**: `Buds/Core/Database/Repositories/MemoryRepository.swift`

**Add jar filtering**:

```swift
// ADD this method to MemoryRepository

func getMemories(jarID: String) async throws -> [Memory] {
    try await Database.shared.readAsync { db in
        // Get local_receipts for this jar
        let rows = try Row.fetchAll(db, sql: """
            SELECT
                lr.uuid,
                lr.header_cid,
                lr.jar_id,
                lr.sender_did,
                lr.is_favorited,
                lr.image_cids,
                lr.created_at,
                h.payload_json
            FROM local_receipts lr
            INNER JOIN ucr_headers h ON lr.header_cid = h.cid
            WHERE lr.jar_id = ?
            ORDER BY lr.created_at DESC
        """, arguments: [jarID])

        return try rows.map { row in
            try parseMemoryFromRow(row)
        }
    }
}

// UPDATE existing getMemories() to filter by jar (default: all jars)

func getMemories(limit: Int = 100) async throws -> [Memory] {
    try await Database.shared.readAsync { db in
        let rows = try Row.fetchAll(db, sql: """
            SELECT
                lr.uuid,
                lr.header_cid,
                lr.jar_id,
                lr.sender_did,
                lr.is_favorited,
                lr.image_cids,
                lr.created_at,
                h.payload_json
            FROM local_receipts lr
            INNER JOIN ucr_headers h ON lr.header_cid = h.cid
            ORDER BY lr.created_at DESC
            LIMIT ?
        """, arguments: [limit])

        return try rows.map { row in
            try parseMemoryFromRow(row)
        }
    }
}
```

**Update parseMemoryFromRow** to include jarID and senderDID:

```swift
private func parseMemoryFromRow(_ row: Row) throws -> Memory {
    // ... existing parsing ...

    return Memory(
        id: row["uuid"],
        receiptCID: row["header_cid"],
        // ... existing fields ...
        jarID: row["jar_id"],  // NEW
        senderDID: row["sender_did"],  // NEW
        // ... rest of fields ...
    )
}
```

---

### 7. Rename CircleManager → JarManager

**Location**: `Buds/Core/JarManager.swift` (renamed from CircleManager.swift)

**Key Changes**:

```swift
//
//  JarManager.swift
//  Buds
//
//  Manages jars and jar members (renamed from CircleManager)
//

import Foundation
import Combine

final class JarManager: ObservableObject {
    static let shared = JarManager()

    @Published var jars: [Jar] = []

    private init() {}

    // MARK: - Jar Operations

    func loadJars() async throws {
        let loadedJars = try await JarRepository.shared.getAllJars()
        await MainActor.run {
            self.jars = loadedJars
        }
    }

    func createJar(name: String, description: String? = nil) async throws -> Jar {
        guard let currentDID = IdentityManager.shared.currentDID else {
            throw JarError.noIdentity
        }

        let jar = try await JarRepository.shared.createJar(
            name: name,
            description: description,
            ownerDID: currentDID
        )

        await loadJars()  // Refresh
        return jar
    }

    func deleteJar(id: String) async throws {
        try await JarRepository.shared.deleteJar(id: id)
        await loadJars()
    }

    // MARK: - Member Operations

    func getMembers(jarID: String) async throws -> [JarMember] {
        try await JarRepository.shared.getMembers(jarID: jarID)
    }

    func addMember(
        jarID: String,
        phoneNumber: String,
        displayName: String
    ) async throws {
        // 1. Lookup DID from phone number (via relay)
        let lookupResult = try await RelayClient.shared.lookupDID(phoneHash: phoneNumber.sha256())

        guard let did = lookupResult.did else {
            throw JarError.userNotFound
        }

        // 2. Get devices for this DID (to get pubkey)
        let devices = try await RelayClient.shared.getDevices(dids: [did])
        guard let device = devices.first else {
            throw JarError.noDevices
        }

        // 3. Add member to jar
        try await JarRepository.shared.addMember(
            jarID: jarID,
            memberDID: did,
            displayName: displayName,
            phoneNumber: phoneNumber,
            pubkeyX25519: device.pubkeyX25519
        )
    }

    func removeMember(jarID: String, memberDID: String) async throws {
        try await JarRepository.shared.removeMember(jarID: jarID, memberDID: memberDID)
    }
}

enum JarError: Error {
    case noIdentity
    case userNotFound
    case noDevices
    case jarFull  // Max 12 members
}
```

**CRITICAL**: Update all references to `CircleManager` → `JarManager` across the codebase.

---

## Testing Strategy

### Pre-Migration Tests

**Run these BEFORE migration**:

1. **Export existing data**:
   ```swift
   let circles = try await Database.shared.readAsync { db in
       try Row.fetchAll(db, sql: "SELECT * FROM circles")
   }
   let memories = try await Database.shared.readAsync { db in
       try Row.fetchAll(db, sql: "SELECT * FROM local_receipts")
   }

   print("📊 Pre-migration: \(circles.count) Circle members, \(memories.count) memories")
   ```

2. **Backup database**:
   ```bash
   cp ~/Library/Application\ Support/buds.sqlite ~/Desktop/buds_backup_phase7.sqlite
   ```

---

### Post-Migration Verification

**Run these AFTER migration**:

1. **Verify Solo jar exists**:
   ```swift
   let soloJar = try await JarRepository.shared.getJar(id: "solo")
   assert(soloJar != nil, "Solo jar must exist")
   assert(soloJar?.name == "Solo", "Solo jar name must be 'Solo'")
   ```

2. **Verify jar members migrated**:
   ```swift
   let jarMembers = try await JarRepository.shared.getMembers(jarID: "solo")
   print("✅ \(jarMembers.count) members in Solo jar")

   // Should be: 1 (you) + N (old Circle members)
   ```

3. **Verify memories scoped to Solo jar**:
   ```swift
   let soloMemories = try await MemoryRepository.shared.getMemories(jarID: "solo")
   print("✅ \(soloMemories.count) buds in Solo jar")

   // Should match count from pre-migration
   ```

4. **Verify no orphaned records**:
   ```swift
   let orphanedMemories = try await Database.shared.readAsync { db in
       try Int.fetchOne(db, sql: """
           SELECT COUNT(*) FROM local_receipts
           WHERE jar_id NOT IN (SELECT id FROM jars)
       """) ?? 0
   }
   assert(orphanedMemories == 0, "No orphaned memories allowed")
   ```

---

### Manual Testing

**Test these flows manually**:

1. **Create new jar**:
   - Open app → Shelf → "+ Add Jar"
   - Enter name "Friends"
   - Verify jar appears in Shelf

2. **Add member to jar**:
   - Tap jar → Members → "+ Add Member"
   - Enter phone number + name
   - Verify member appears (status: pending)

3. **Create bud in jar**:
   - Tap jar → "+ Add Bud"
   - Select method → Save
   - Verify bud appears in jar feed (NOT in other jars)

4. **Share bud to jar** (E2EE):
   - Create bud → Share to jar
   - Verify E2EE encryption works (check relay logs)
   - Verify recipient receives bud

---

## Rollback Plan

**If migration fails**:

1. **Restore backup**:
   ```bash
   cp ~/Desktop/buds_backup_phase7.sqlite ~/Library/Application\ Support/buds.sqlite
   ```

2. **Revert code**:
   ```bash
   git checkout HEAD~1  # Revert to Phase 7
   ```

3. **Debug migration**:
   - Check migration logs
   - Identify failing SQL statement
   - Fix migration function
   - Test migration on fresh install (no existing data)

---

## E2EE Key Management

### Current Sharing Flow (Phase 7)

```swift
// Share to all Circle members
let circleMembers = try await CircleManager.shared.getActiveMembers()
let devices = try await RelayClient.shared.getDevices(dids: circleMembers.map(\.did))
let wrappedKeys = try E2EEManager.shared.encryptForDevices(payload, devices)
try await RelayClient.shared.sendMessage(recipientDids: circleMembers.map(\.did), wrappedKeys)
```

### New Sharing Flow (Phase 8)

```swift
// Share to specific jar members only
func shareMemory(memory: Memory, toJar jar: Jar) async throws {
    // 1. Get members of THIS jar (not all jars)
    let jarMembers = try await JarRepository.shared.getMembers(jarID: jar.id)

    // 2. Get devices for jar members
    let devices = try await RelayClient.shared.getDevices(dids: jarMembers.map(\.memberDID))

    // 3. Encrypt for jar members ONLY (E2EE logic unchanged)
    let wrappedKeys = try E2EEManager.shared.encryptForDevices(payload, devices)

    // 4. Send to relay
    try await RelayClient.shared.sendMessage(
        recipientDids: jarMembers.map(\.memberDID),
        wrappedKeys: wrappedKeys
    )
}
```

**KEY INSIGHT**: E2EE encryption logic (X25519 + AES-256-GCM) **does not change**. We just change the recipient list (jar members instead of all Circle members).

---

## Success Criteria

**Migration succeeds if**:
- ✅ Solo jar created with current user as owner
- ✅ All Circle members migrated to Solo jar members
- ✅ All memories scoped to Solo jar (jar_id = 'solo')
- ✅ No data loss (counts match pre-migration)
- ✅ E2EE sharing works (can share bud to jar)
- ✅ No orphaned records
- ✅ App builds and runs without crashes

---

## Estimated Timeline

| Task | Time |
|------|------|
| Create Jar.swift, JarMember.swift | 30 min |
| Update Memory.swift (add jarID) | 15 min |
| Create migration v5 (SQL + Swift) | 1 hour |
| Create JarRepository.swift | 45 min |
| Update MemoryRepository.swift | 30 min |
| Rename CircleManager → JarManager | 30 min |
| Testing (pre/post migration) | 1 hour |
| **Total** | **4 hours** |

---

## Next Steps

**After Phase 8 completes**:
1. ✅ Database migrated successfully
2. ✅ Jar model created
3. ✅ All memories scoped to jars
4. ➡️  **Phase 9**: Build Shelf UI (home screen with jar grid)

---

## Execution Checklist

**Copy this checklist and check off as you go**:

- [ ] Create `Buds/Core/Models/Jar.swift`
- [ ] Create `Buds/Core/Models/JarMember.swift`
- [ ] Update `Buds/Core/Models/Memory.swift` (add jarID, senderDID)
- [ ] Create migration v5 in `Database.swift`
- [ ] Create `Buds/Core/Database/Repositories/JarRepository.swift`
- [ ] Update `MemoryRepository.swift` (add jar filtering)
- [ ] Rename `CircleManager.swift` → `JarManager.swift`
- [ ] Update all references to CircleManager
- [ ] Run migration locally (backup first!)
- [ ] Verify Solo jar exists
- [ ] Verify jar members migrated
- [ ] Verify memories scoped to Solo jar
- [ ] Test creating new jar
- [ ] Test adding member to jar
- [ ] Test creating bud in jar
- [ ] Test E2EE sharing to jar
- [ ] Commit changes: "Phase 8: Jar architecture migration"

**Good luck! 🫙**
