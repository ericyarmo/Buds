# Buds Database Schema (GRDB)

**Last Updated:** December 20, 2025
**Database:** SQLite via GRDB
**Version:** v0.1 (Migration v3)

---

## Overview

Buds uses GRDB for local-first storage with the following design principles:

1. **Two-layer architecture**: Protocol layer (ucr_headers) + App layer (local_receipts, circles, etc.)
2. **Content-addressed**: Receipts identified by CID
3. **Normalized**: Separate tables for blobs, locations, circles
4. **Indexed**: Strategic indexes for common queries
5. **Migratable**: Version-controlled schema migrations

---

## Table of Contents

1. [Core Tables](#core-tables)
2. [Circle Tables](#circle-tables)
3. [Location Tables](#location-tables)
4. [Blob Tables](#blob-tables)
5. [Cache & Index Tables](#cache--index-tables)
6. [Indexes](#indexes)
7. [Migrations](#migrations)
8. [Queries](#common-queries)

---

## Core Tables

### `ucr_headers` (Protocol Layer)

**Immutable receipts** — canonical CBOR + signature (causality-first architecture)

```sql
CREATE TABLE ucr_headers (
    cid TEXT PRIMARY KEY NOT NULL,              -- CIDv1 (bafyrei...)
    did TEXT NOT NULL,                          -- Author DID
    device_id TEXT,                             -- Device identifier
    parent_cid TEXT,                            -- Edit chain parent (causal ordering)
    root_cid TEXT NOT NULL,                     -- First version in chain
    receipt_type TEXT NOT NULL,                 -- app.buds.session.created/v1
    payload_json TEXT NOT NULL,                 -- JSON payload (contains claimed_time_ms)
    signature TEXT NOT NULL,                    -- Base64 Ed25519 signature
    raw_cbor BLOB NOT NULL,                     -- Original CBOR bytes
    received_at REAL NOT NULL,                  -- When we received this receipt (local truth)
    FOREIGN KEY (parent_cid) REFERENCES ucr_headers(cid) ON DELETE SET NULL
);

CREATE INDEX idx_ucr_headers_root ON ucr_headers(root_cid);
CREATE INDEX idx_ucr_headers_type ON ucr_headers(receipt_type);
CREATE INDEX idx_ucr_headers_received ON ucr_headers(received_at DESC);
CREATE INDEX idx_ucr_headers_did ON ucr_headers(did);
-- Optional: Index on claimed_time_ms for secondary sorting
-- Can use json_extract (shown) or add a dedicated INTEGER column for better performance
CREATE INDEX idx_ucr_headers_claimed_time ON ucr_headers(
    json_extract(payload_json, '$.claimed_time_ms') DESC
);

-- Alternative (better performance): Add dedicated column (optional optimization)
-- ALTER TABLE ucr_headers ADD COLUMN claimed_time_ms INTEGER;
-- CREATE INDEX idx_ucr_headers_claimed_time ON ucr_headers(claimed_time_ms DESC);
```

**Notes**:
- **Causality-first**: `parent_cid` is the truth (verifiable), not timestamps
- **No timestamp column**: Time moved to `payload_json` as `claimed_time_ms` (author's claim)
- **received_at**: When local DB first saw this receipt (local ordering, not shared)
- `cid` is primary key (content-addressed)
- `raw_cbor` stored for verification and re-export
- **`payload_json` is a derived projection** for queryability, generated from decoding `raw_cbor` (or from the typed payload at insert). It is NEVER used to recompute CID or verify signature. `raw_cbor` is the canonical source of truth.
- `payload_json` contains `claimed_time_ms` for query indexing
- `parent_cid` creates verifiable edit chains
- **Tombstones**: Deletions are represented by special receipt types (e.g., `app.buds.memory.deleted/v1`). Original receipts remain in the database; timeline queries filter out tombstoned items unless "show deleted" is enabled.

---

### `local_receipts` (App Layer)

**Mutable metadata** — favorites, tags, local notes

```sql
CREATE TABLE local_receipts (
    uuid TEXT PRIMARY KEY NOT NULL,             -- App-local UUID
    header_cid TEXT NOT NULL UNIQUE,            -- FK to ucr_headers.cid (1:1 relationship)
    is_favorited INTEGER NOT NULL DEFAULT 0,    -- Boolean (0/1)
    tags_json TEXT,                             -- JSON array: ["night", "social"]
    local_notes TEXT,                           -- Private notes (not in receipt)
    image_cids TEXT,                            -- JSON array of CIDs: ["bafyrei...", "bafyrei..."] (up to 3)
    created_at REAL NOT NULL,                   -- Local insert time
    updated_at REAL NOT NULL,                   -- Last local update
    FOREIGN KEY (header_cid) REFERENCES ucr_headers(cid) ON DELETE CASCADE
);

CREATE INDEX idx_local_receipts_header ON local_receipts(header_cid);
CREATE INDEX idx_local_receipts_favorited ON local_receipts(is_favorited);
CREATE INDEX idx_local_receipts_created ON local_receipts(created_at DESC);
```

**Notes**:
- `uuid` is app-local (not shared)
- **1:1 relationship**: Each `header_cid` appears exactly once (enforced by UNIQUE constraint)
- Your own authored receipts and Circle-received receipts both get entries here
- **`image_cids`**: JSON array of blob CIDs for up to 3 photos per memory (Phase 3: multi-image support)

---

## Circle Tables

### `circles` (Your Circle Members)

**Track your 12-person Circle**

```sql
CREATE TABLE circles (
    id TEXT PRIMARY KEY NOT NULL,               -- UUID
    did TEXT NOT NULL UNIQUE,                   -- Member DID
    display_name TEXT NOT NULL,                 -- Local nickname (privacy-preserving)
    phone_number TEXT,                          -- Optional, for display only (never in receipts)
    avatar_cid TEXT,                            -- Profile photo CID
    pubkey_x25519 TEXT NOT NULL,                -- Base64 public key for E2EE
    status TEXT NOT NULL,                       -- 'pending' | 'active' | 'removed'
    joined_at REAL,                             -- When they accepted invite
    invited_at REAL,                            -- When you sent invite
    removed_at REAL,                            -- When removed (if applicable)
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL,
    FOREIGN KEY (avatar_cid) REFERENCES blobs(cid) ON DELETE SET NULL
);

CREATE INDEX idx_circles_did ON circles(did);
CREATE INDEX idx_circles_status ON circles(status);
```

**Notes**:
- Max 12 active members (enforced in app layer)
- `status`: `pending` (invited, not accepted), `active`, `removed`
- `pubkey_x25519` used for E2EE key wrapping (one per member, Phase 5)
- **Phase 6**: Will query relay for all devices per DID and wrap keys for each device
- **Privacy**: `phone_number` stored locally for display only, never sent to relay (hashed with SHA-256 for lookups)
- **Privacy**: `display_name` is local-only nickname, not shared globally

---

### `devices` (Multi-Device Support)

**Track devices for E2EE key distribution**

```sql
CREATE TABLE devices (
    device_id TEXT PRIMARY KEY NOT NULL,        -- UUID (generated on device registration)
    owner_did TEXT NOT NULL,                    -- DID of device owner
    device_name TEXT NOT NULL,                  -- "Alice's iPhone", "Alice's iPad"
    pubkey_x25519 TEXT NOT NULL,                -- Device-specific X25519 pubkey (base64)
    pubkey_ed25519 TEXT NOT NULL,               -- Device-specific Ed25519 pubkey (base64)
    status TEXT NOT NULL,                       -- 'active' | 'revoked'
    registered_at REAL NOT NULL,                -- When device registered with relay
    last_seen_at REAL                           -- Last time device polled inbox
);

CREATE INDEX idx_devices_owner ON devices(owner_did);
CREATE INDEX idx_devices_status ON devices(status);
```

**Notes**:
- **Multi-device E2EE**: Each device gets unique X25519 keypair for key wrapping
- **Device-based encryption**: When sharing, wrap AES key for each recipient device (not just per DID)
- **Example**: Alice has iPhone + iPad → both devices get wrapped keys
- **Phase 5**: Table schema created but unused (placeholder DIDs only)
- **Phase 6**: Devices registered with Cloudflare relay on first launch, queried for E2EE sharing
- **Security**: `status = 'revoked'` allows device removal without affecting other devices

---

### `circle_invites` (Invites You've Created)

**Track outgoing invites**

```sql
CREATE TABLE circle_invites (
    id TEXT PRIMARY KEY NOT NULL,               -- UUID
    invite_code TEXT NOT NULL UNIQUE,           -- "BUDS-A7F3-92B1"
    invitee_did TEXT,                           -- Set when accepted
    expires_at REAL,                            -- Optional expiration
    max_uses INTEGER NOT NULL DEFAULT 1,        -- Usually 1
    use_count INTEGER NOT NULL DEFAULT 0,       -- Times used
    status TEXT NOT NULL,                       -- 'pending' | 'accepted' | 'expired'
    message TEXT,                               -- Optional invite message
    created_at REAL NOT NULL,
    accepted_at REAL
);

CREATE INDEX idx_circle_invites_code ON circle_invites(invite_code);
CREATE INDEX idx_circle_invites_status ON circle_invites(status);
```

---

### `shared_memories` (Memories Shared to Circle)

**Track what you've shared and with whom**

```sql
CREATE TABLE shared_memories (
    id TEXT PRIMARY KEY NOT NULL,               -- UUID
    memory_cid TEXT NOT NULL,                   -- CID of session receipt
    shared_with TEXT NOT NULL,                  -- JSON array of DIDs or "circle"
    permissions TEXT NOT NULL,                  -- 'view' | 'view_location' | 'full'
    encrypted_payload BLOB,                     -- Encrypted memory (if Circle share)
    wrapped_keys_json TEXT,                     -- JSON: {did: wrapped_key_base64}
    nonce TEXT,                                 -- Base64 AES-GCM nonce
    message TEXT,                               -- Optional share message
    shared_at REAL NOT NULL,
    unshared_at REAL,                           -- If revoked
    FOREIGN KEY (memory_cid) REFERENCES ucr_headers(cid) ON DELETE CASCADE
);

CREATE INDEX idx_shared_memories_cid ON shared_memories(memory_cid);
CREATE INDEX idx_shared_memories_shared_at ON shared_memories(shared_at DESC);
```

**Notes**:
- `shared_with`: JSON array like `["did:buds:abc", "did:buds:xyz"]` or `"circle"`
- `encrypted_payload`: The actual encrypted session data
- **`wrapped_keys_json`**: Map of recipient `device_id` → wrapped AES key (device-based E2EE, not DID-based, to support multi-device)

---

### `received_memories` (Memories Shared With You)

**Store decrypted memories from Circle members**

```sql
CREATE TABLE received_memories (
    id TEXT PRIMARY KEY NOT NULL,               -- UUID
    memory_cid TEXT NOT NULL,                   -- CID of original receipt
    sender_did TEXT NOT NULL,                   -- Who shared it
    header_cid TEXT NOT NULL,                   -- Decrypted header CID
    permissions TEXT NOT NULL,                  -- What you can see
    shared_at REAL NOT NULL,
    received_at REAL NOT NULL,                  -- When you decrypted it
    FOREIGN KEY (header_cid) REFERENCES ucr_headers(cid) ON DELETE CASCADE,
    FOREIGN KEY (sender_did) REFERENCES circles(did) ON DELETE CASCADE
);

CREATE INDEX idx_received_memories_sender ON received_memories(sender_did);
CREATE INDEX idx_received_memories_received ON received_memories(received_at DESC);
```

**Notes**:
- After decrypting a shared memory, insert its UCRHeader into `ucr_headers`
- Then create `received_memories` entry linking to it
- Can create read-only `local_receipts` entry for display

---

## Location Tables

### `locations` (Location Data)

**Privacy-protected location storage**

```sql
CREATE TABLE locations (
    cid TEXT PRIMARY KEY NOT NULL,              -- CID of location blob
    receipt_cid TEXT,                           -- Associated session (optional)
    location_type TEXT NOT NULL,                -- 'precise' | 'fuzzy' | 'named'

    -- Precise location (private)
    latitude REAL,
    longitude REAL,
    altitude REAL,
    accuracy REAL,

    -- Fuzzy location (for sharing)
    fuzzy_lat REAL,
    fuzzy_lon REAL,
    fuzzy_radius INTEGER,                       -- Meters

    -- Named location
    place_name TEXT,                            -- "Golden Gate Park"
    place_category TEXT,                        -- 'park' | 'home' | 'dispensary'

    -- Metadata
    captured_at REAL NOT NULL,
    delay_share_until REAL,                     -- Optional delayed visibility
    created_at REAL NOT NULL,

    FOREIGN KEY (receipt_cid) REFERENCES ucr_headers(cid) ON DELETE CASCADE
);

CREATE INDEX idx_locations_receipt ON locations(receipt_cid);
CREATE INDEX idx_locations_type ON locations(location_type);
CREATE INDEX idx_locations_captured ON locations(captured_at DESC);
```

**Notes**:
- **Privacy by default**: Precise fields (`latitude`, `longitude`, `altitude`, `accuracy`) are local-only
- **Sharing uses fuzzy**: Circle sharing ONLY uses `fuzzy_*` fields unless user explicitly opts in to share precise location
- **Never export precise** unless user explicitly grants permission per-share
- Fuzzy location snapped to ~500m grid for Circle sharing
- `delay_share_until`: Don't show on map until this time (delayed sharing for privacy)

---

## Dispensary Deals Tables (vNext / Future - NOT in v0.1)

**NOTE:** The following tables are reserved for future functionality (v0.2+). They introduce a dispensary-facing product surface with privacy promises (n≥75 aggregation). Not implemented in v0.1.

### `deals` (Dispensary Promotions)

**Deals posted by dispensaries that users can attach buds to**

```sql
CREATE TABLE deals (
    id TEXT PRIMARY KEY NOT NULL,               -- UUID
    dispensary_name TEXT NOT NULL,              -- "Cookies SF"
    dispensary_id TEXT,                         -- Future: standardized dispo IDs
    title TEXT NOT NULL,                        -- "20% off Blue Dream"
    description TEXT,                           -- Full deal details
    product_name TEXT,                          -- "Blue Dream" (optional)
    discount_type TEXT,                         -- 'percentage' | 'fixed' | 'bogo'
    discount_value REAL,                        -- 20 (for 20% off) or 10 (for $10 off)

    -- Location
    latitude REAL NOT NULL,
    longitude REAL NOT NULL,
    address TEXT,

    -- Validity
    starts_at REAL NOT NULL,
    expires_at REAL NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',      -- 'active' | 'expired' | 'removed'

    -- Metadata
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL
);

CREATE INDEX idx_deals_dispensary ON deals(dispensary_name);
CREATE INDEX idx_deals_expires ON deals(expires_at);
CREATE INDEX idx_deals_status ON deals(status);
CREATE INDEX idx_deals_location ON deals(latitude, longitude);
```

**Notes**:
- Dispensaries post deals (via web dashboard or API)
- Deals show as highlighted pins on map
- Users attach buds to deals when they use them
- Aggregate feedback helps dispensaries see deal performance

---

### `deal_buds` (Buds Attached to Deals)

**Links buds (memories) to the deals they used**

```sql
CREATE TABLE deal_buds (
    id TEXT PRIMARY KEY NOT NULL,               -- UUID
    deal_id TEXT NOT NULL,                      -- FK to deals.id
    bud_cid TEXT NOT NULL,                      -- FK to ucr_headers.cid (the bud)
    user_did TEXT NOT NULL,                     -- Who attached it
    opted_in_analytics INTEGER NOT NULL DEFAULT 0,  -- User opted in to share with dispo
    created_at REAL NOT NULL,
    FOREIGN KEY (deal_id) REFERENCES deals(id) ON DELETE CASCADE,
    FOREIGN KEY (bud_cid) REFERENCES ucr_headers(cid) ON DELETE CASCADE
);

CREATE INDEX idx_deal_buds_deal ON deal_buds(deal_id);
CREATE INDEX idx_deal_buds_bud ON deal_buds(bud_cid);
CREATE INDEX idx_deal_buds_user ON deal_buds(user_did);
CREATE INDEX idx_deal_buds_opted_in ON deal_buds(opted_in_analytics);
```

**Notes**:
- When user creates bud after using a deal, they can link it
- Optional opt-in to share with dispensary (for analytics)
- Privacy: Only aggregate data if n ≥ 75 opted-in users

---

## Blob Tables

### `blobs` (Photos, Videos, Files)

**Content-addressed blob storage**

```sql
CREATE TABLE blobs (
    cid TEXT PRIMARY KEY NOT NULL,              -- CID of blob content
    mime_type TEXT NOT NULL,                    -- "image/jpeg", "video/mp4"
    size INTEGER NOT NULL,                      -- Bytes
    local_path TEXT,                            -- File path on device
    encrypted INTEGER NOT NULL DEFAULT 0,       -- Boolean: is encrypted?
    thumbnail_cid TEXT,                         -- CID of thumbnail (if image/video)
    created_at REAL NOT NULL,
    FOREIGN KEY (thumbnail_cid) REFERENCES blobs(cid) ON DELETE SET NULL
);

CREATE INDEX idx_blobs_mime ON blobs(mime_type);
CREATE INDEX idx_blobs_created ON blobs(created_at DESC);
```

---

### `receipt_blobs` (Junction Table)

**Link receipts to their blobs (photos, etc.)**

```sql
CREATE TABLE receipt_blobs (
    receipt_cid TEXT NOT NULL,                  -- FK to ucr_headers.cid
    blob_cid TEXT NOT NULL,                     -- FK to blobs.cid
    position INTEGER NOT NULL DEFAULT 0,        -- Display order
    PRIMARY KEY (receipt_cid, blob_cid),
    FOREIGN KEY (receipt_cid) REFERENCES ucr_headers(cid) ON DELETE CASCADE,
    FOREIGN KEY (blob_cid) REFERENCES blobs(cid) ON DELETE CASCADE
);

CREATE INDEX idx_receipt_blobs_receipt ON receipt_blobs(receipt_cid);
CREATE INDEX idx_receipt_blobs_blob ON receipt_blobs(blob_cid);
```

---

## Cache & Index Tables

### `fts_memories` (Full-Text Search)

**Virtual table for fast text search**

```sql
CREATE VIRTUAL TABLE fts_memories USING fts5(
    cid UNINDEXED,                              -- Receipt CID (for joins)
    product_name,                               -- Searchable
    strain_name,                                -- Searchable
    notes,                                      -- Searchable
    place_name,                                 -- Searchable (from locations table)
    tokenize = 'porter unicode61'              -- Better tokenization
);
```

**Maintained by triggers**:

```sql
-- Insert trigger
CREATE TRIGGER fts_memories_insert AFTER INSERT ON ucr_headers
WHEN NEW.receipt_type LIKE 'app.buds.session.%'
BEGIN
    INSERT INTO fts_memories(cid, product_name, strain_name, notes, place_name)
    SELECT
        NEW.cid,
        json_extract(NEW.payload_json, '$.product_name'),
        json_extract(NEW.payload_json, '$.strain_name'),
        json_extract(NEW.payload_json, '$.notes'),
        (SELECT place_name FROM locations WHERE receipt_cid = NEW.cid LIMIT 1);
END;

-- Update trigger
CREATE TRIGGER fts_memories_update AFTER UPDATE ON ucr_headers
WHEN NEW.receipt_type LIKE 'app.buds.session.%'
BEGIN
    UPDATE fts_memories
    SET product_name = json_extract(NEW.payload_json, '$.product_name'),
        strain_name = json_extract(NEW.payload_json, '$.strain_name'),
        notes = json_extract(NEW.payload_json, '$.notes'),
        place_name = (SELECT place_name FROM locations WHERE receipt_cid = NEW.cid LIMIT 1)
    WHERE cid = NEW.cid;
END;

-- Delete trigger
CREATE TRIGGER fts_memories_delete AFTER DELETE ON ucr_headers
BEGIN
    DELETE FROM fts_memories WHERE cid = OLD.cid;
END;
```

---

### `daily_summaries` (Pre-computed Stats)

**Cached aggregates for Agent queries**

```sql
CREATE TABLE daily_summaries (
    date TEXT PRIMARY KEY NOT NULL,             -- "2024-12-16"
    session_count INTEGER NOT NULL DEFAULT 0,
    total_amount_grams REAL,
    unique_strains_json TEXT,                   -- JSON array
    dominant_effects_json TEXT,                 -- JSON array
    avg_rating REAL,
    locations_visited_json TEXT,                -- JSON array
    computed_at REAL NOT NULL
);

CREATE INDEX idx_daily_summaries_date ON daily_summaries(date DESC);
```

**Notes**:
- Generated nightly or on-demand
- Speeds up Agent queries for date ranges
- Used for "Your Year in Buds" style features

---

## Indexes

### Query Optimization

**Timeline queries** (most common):
```sql
CREATE INDEX idx_timeline ON local_receipts(created_at DESC, is_favorited);
```

**Circle feed queries**:
```sql
CREATE INDEX idx_circle_feed ON received_memories(received_at DESC, sender_did);
```

**Map queries** (bounding box):
```sql
CREATE INDEX idx_map_locations ON locations(latitude, longitude)
WHERE location_type IN ('precise', 'fuzzy');
```

**Strain search**:
```sql
CREATE INDEX idx_strain_search ON ucr_headers(receipt_type, json_extract(payload_json, '$.strain_name'));
```

---

## Migrations

### Migration System

Using GRDB's `DatabaseMigrator`:

```swift
var migrator = DatabaseMigrator()

// v1: Initial schema (Phase 0-2)
migrator.registerMigration("v1") { db in
    // Create ucr_headers, local_receipts, locations, blobs, receipt_blobs
    // See Database.swift for full schema
}

// v2: Multi-image support (Phase 3)
migrator.registerMigration("v2") { db in
    // Rename image_cid → image_cids (JSON array)
    try db.alter(table: "local_receipts") { t in
        t.add(column: "image_cids_temp", .text)
    }

    // Migrate data: convert single CID to JSON array
    try db.execute(sql: """
        UPDATE local_receipts
        SET image_cids_temp = json_array(image_cid)
        WHERE image_cid IS NOT NULL
    """)

    // Drop old column, rename new
    try db.alter(table: "local_receipts") { t in
        t.drop(column: "image_cid")
    }
    try db.execute(sql: "ALTER TABLE local_receipts RENAME COLUMN image_cids_temp TO image_cids")
}

// v3: Circle mechanics (Phase 5)
migrator.registerMigration("v3") { db in
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

    try db.execute(sql: "CREATE INDEX idx_circles_did ON circles(did)")
    try db.execute(sql: "CREATE INDEX idx_circles_status ON circles(status)")

    // Drop and recreate devices table with new schema
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

    try db.execute(sql: "CREATE INDEX idx_devices_owner ON devices(owner_did)")
    try db.execute(sql: "CREATE INDEX idx_devices_status ON devices(status)")
}
```

**Migration History**:
- **v1** (Phase 0-2): Base schema with ucr_headers, local_receipts, locations, blobs
- **v2** (Phase 3): Multi-image support - `image_cid` → `image_cids` (JSON array, up to 3 photos)
- **v3** (Phase 5): Circle mechanics - `circles` table + updated `devices` table for multi-device E2EE

---

## Common Queries

### 1. Timeline (Most Recent Memories)

```sql
SELECT
    lr.uuid,
    lr.is_favorited,
    lr.image_cids,  -- JSON array of CIDs (up to 3)
    h.cid,
    h.receipt_type,
    h.payload_json,
    json_extract(h.payload_json, '$.claimed_time_ms') AS claimed_time_ms,
    h.received_at
FROM local_receipts lr
JOIN ucr_headers h ON lr.header_cid = h.cid
WHERE h.receipt_type LIKE 'app.buds.session.%'
ORDER BY h.received_at DESC  -- Primary: when we received it (consistent across sync)
LIMIT 50;
```

**Note on ordering**: Timeline sorts by `received_at` (when the local DB first saw the receipt) for consistency across sync. `created_at` in `local_receipts` is just local metadata. `claimed_time_ms` is the author's time claim (unverifiable) and can be displayed in UI but shouldn't be the primary sort key.

### 2. Search Memories (Full-Text)

```sql
SELECT
    fts.cid,
    h.payload_json,
    json_extract(h.payload_json, '$.claimed_time_ms') AS claimed_time_ms,
    h.received_at,
    rank
FROM fts_memories fts
JOIN ucr_headers h ON fts.cid = h.cid
WHERE fts_memories MATCH 'blue dream'
ORDER BY rank
LIMIT 20;
```

### 3. Map Markers (Bounding Box)

```sql
SELECT
    l.cid,
    l.fuzzy_lat,
    l.fuzzy_lon,
    l.place_name,
    lr.uuid,
    h.payload_json
FROM locations l
JOIN ucr_headers h ON l.receipt_cid = h.cid
JOIN local_receipts lr ON lr.header_cid = h.cid
WHERE l.fuzzy_lat BETWEEN :min_lat AND :max_lat
  AND l.fuzzy_lon BETWEEN :min_lon AND :max_lon
  AND l.location_type IN ('fuzzy', 'precise')
LIMIT 200;
```

### 4. Circle Feed (Recent Shares)

```sql
SELECT
    rm.id,
    rm.sender_did,
    c.display_name AS sender_name,
    h.cid,
    h.payload_json,
    json_extract(h.payload_json, '$.claimed_time_ms') AS claimed_time_ms,
    rm.received_at
FROM received_memories rm
JOIN circles c ON rm.sender_did = c.did
JOIN ucr_headers h ON rm.header_cid = h.cid
WHERE c.status = 'active'
ORDER BY rm.received_at DESC  -- When we received the share
LIMIT 50;
```

### 5. Strain History

```sql
SELECT
    json_extract(h.payload_json, '$.strain_name') AS strain,
    COUNT(*) AS session_count,
    AVG(CAST(json_extract(h.payload_json, '$.rating') AS REAL)) AS avg_rating,
    MAX(json_extract(h.payload_json, '$.claimed_time_ms')) AS last_used_claimed
FROM ucr_headers h
WHERE h.receipt_type = 'app.buds.session.created/v1'
  AND json_extract(h.payload_json, '$.strain_name') IS NOT NULL
GROUP BY strain
ORDER BY session_count DESC;
```

### 6. Agent Context (Recent Sessions)

```sql
SELECT
    h.cid,
    h.payload_json,
    json_extract(h.payload_json, '$.claimed_time_ms') AS claimed_time_ms,
    h.received_at,
    l.place_name
FROM ucr_headers h
LEFT JOIN locations l ON l.receipt_cid = h.cid
WHERE h.receipt_type LIKE 'app.buds.session.%'
  AND json_extract(h.payload_json, '$.claimed_time_ms') >= :since_claimed_time_ms
ORDER BY h.received_at DESC  -- Primary ordering by when we saw it
LIMIT 100;
```

---

## Database Size Estimation

**For 1,000 memories** (1 year, ~3 per day):

| Table | Row Size | Count | Total |
|-------|----------|-------|-------|
| ucr_headers | ~2 KB | 1,000 | 2 MB |
| local_receipts | ~0.5 KB | 1,000 | 0.5 MB |
| locations | ~0.3 KB | 500 | 0.15 MB |
| blobs (meta only) | ~0.2 KB | 3,000 | 0.6 MB |
| circles | ~0.3 KB | 12 | 0.004 MB |
| devices | ~0.3 KB | 24 | 0.007 MB |
| fts_memories | ~1 KB | 1,000 | 1 MB |
| **Total (metadata)** | | | **~4.3 MB** |
| **Photos** (2 MB each) | | 3,000 | **6 GB** |

**Total: ~6 GB for 1 year of heavy use** (assuming ~3 photos per memory average)

**Notes**:
- Phase 3 added multi-image support (up to 3 photos per memory)
- Photo count estimate: 1,000 memories × 3 photos = 3,000 photos
- Devices: Assumes 12 Circle members × 2 devices each = 24 devices tracked

---

## Cleanup & Maintenance

### Vacuum (Periodic)

```sql
VACUUM;  -- Reclaim deleted space
ANALYZE; -- Update query planner stats
```

**Run**: Monthly or when DB grows > 50% of initial size

### Orphan Blob Cleanup

```sql
DELETE FROM blobs
WHERE cid NOT IN (
    SELECT blob_cid FROM receipt_blobs
    UNION
    -- Extract all CIDs from image_cids JSON array
    SELECT value FROM local_receipts, json_each(image_cids) WHERE image_cids IS NOT NULL
    UNION
    SELECT avatar_cid FROM circles WHERE avatar_cid IS NOT NULL
);
```

### Soft Delete Old Receipts

Instead of deleting, mark as archived:

```sql
ALTER TABLE local_receipts ADD COLUMN archived INTEGER DEFAULT 0;
CREATE INDEX idx_local_receipts_archived ON local_receipts(archived);

-- Archive old receipts
UPDATE local_receipts
SET archived = 1
WHERE created_at < (unixepoch('now') - 31536000); -- 1 year ago
```

---

## Performance Tuning

### PRAGMA Settings

```sql
PRAGMA journal_mode = WAL;              -- Write-ahead logging (better concurrency)
PRAGMA synchronous = NORMAL;            -- Good balance of safety/speed
PRAGMA cache_size = -64000;             -- 64 MB cache
PRAGMA temp_store = MEMORY;             -- Temp tables in RAM
PRAGMA mmap_size = 268435456;           -- 256 MB memory-mapped I/O
```

### Query Optimization Tips

1. **Use prepared statements** (GRDB does this automatically)
2. **Limit result sets** (always use LIMIT for lists)
3. **Index foreign keys** (already done above)
4. **Avoid SELECT \*** (specify columns)
5. **Use covering indexes** (include all queried columns in index)

---

## Backup Strategy

### Local Backups

```swift
// Export entire database
func exportDatabase() throws -> Data {
    let dbURL = try Database.shared.dbQueue.path
    return try Data(contentsOf: URL(fileURLWithPath: dbURL))
}
```

### Selective Export (Privacy-Preserving)

```swift
// Export only receipts (no local metadata)
func exportReceipts() throws -> [UCRHeader] {
    return try Database.shared.dbQueue.read { db in
        return try UCRHeaderRecord.fetchAll(db).map { try $0.toHeader() }
    }
}
```

---

## Schema Invariants

This schema establishes the following critical invariants:

1. **`raw_cbor` is mandatory and is the verification source-of-truth**
   - Stored in `ucr_headers.raw_cbor` column
   - Used for signature verification and CID recomputation
   - Never modify or delete this column

2. **`payload_json` is query/cache only, never truth**
   - Derived projection for queryability (generated from `raw_cbor` or typed payload at insert)
   - NEVER used to recompute CID or verify signatures
   - Can be regenerated from `raw_cbor` if corrupted

3. **`received_at` is local ordering; causal ordering comes from `parent_cid` chain**
   - `received_at` is when the local DB first saw the receipt (local time, not shared)
   - Causality is determined by `parent_cid` → `root_cid` chains (verifiable)
   - Timeline queries sort by `received_at` for consistency across sync

4. **`claimed_time_ms` is in payload, not header**
   - Time is an unverifiable claim by the author
   - Lives in `payload_json` (not a protocol primitive)
   - Can be indexed via `json_extract()` or dedicated column for performance

5. **Tombstones preserve history (append-only)**
   - Deletions create tombstone receipts (e.g., `app.buds.memory.deleted/v1`)
   - Original receipts remain in database for audit/sync
   - UI filters out tombstoned items

6. **Location privacy: precise fields are local-only**
   - `latitude`, `longitude`, `altitude`, `accuracy` never leave device unless explicit opt-in
   - Circle sharing uses only `fuzzy_*` fields (~500m grid)
   - Enforced at application layer (not DB constraints)

7. **E2EE is device-based, not DID-based**
   - `wrapped_keys_json` maps `device_id` → wrapped AES key
   - Supports multi-device per user
   - See E2EE_DESIGN.md for details

---

**Next**: See [E2EE_DESIGN.md](./E2EE_DESIGN.md) for encryption details.
