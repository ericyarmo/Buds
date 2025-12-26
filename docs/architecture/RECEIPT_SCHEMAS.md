# Buds Receipt Schemas

**Last Updated:** December 16, 2025
**Version:** v0.1

---

## Overview

This document defines all receipt types and their canonical payload schemas for Buds. Every receipt follows the UCRHeader pattern with deterministic CBOR encoding.

---

## Receipt Type Naming Convention

```
app.buds.<domain>.<action>/<version>
```

Examples:
- `app.buds.session.created/v1`
- `app.buds.circle.invite.accepted/v1`
- `app.buds.memory.shared/v1`

---

## Core Receipt Types

### 1. Session Receipts

#### 1.1 `app.buds.session.created/v1`

**Purpose**: Record a new smoke session

**Payload Schema**:

```swift
{
    // REQUIRED: Time claim (author's assertion of when this happened)
    "claimed_time_ms": Int64,         // Unix milliseconds

    // Product info (all optional)
    "product_name": String?,          // "Blue Dream"
    "product_brand": String?,         // "Cookies"
    "product_type": String?,          // "flower" | "vape" | "edible" | "concentrate"
    "strain_name": String?,           // "Blue Dream"
    "strain_type": String?,           // "hybrid" | "sativa" | "indica"
    "thc_percent": Double?,           // 23.5
    "cbd_percent": Double?,           // 0.8

    // Dispensary info (optional)
    "dispensary_name": String?,       // "Cookies SF"
    "dispensary_id": String?,         // Future: standardized dispo IDs

    // Experience
    "notes": String?,                 // Freeform text
    "rating": Int?,                   // 1-5
    "effects": [String],              // ["relaxed", "creative", "hungry"]
    "mood_before": [String],          // ["anxious", "tired"]
    "mood_after": [String],           // ["calm", "energized"]

    // Context
    "location_cid": String?,          // CID of location receipt (if enabled)
    "photo_cids": [String],           // Array of photo blob CIDs
    "friends_present": [String],      // DIDs of friends (if they consent)

    // Metadata
    "session_duration_mins": Int?,    // 45
    "method": String?,                // "joint" | "bong" | "vape" | "edible"
    "amount_grams": Double?,          // 0.5
}
```

**Example**:

```json
{
    "claimed_time_ms": 1704844800000,
    "product_name": "Blue Dream",
    "product_brand": "Cookies",
    "product_type": "flower",
    "strain_name": "Blue Dream",
    "strain_type": "hybrid",
    "thc_percent": 23.5,
    "cbd_percent": 0.8,
    "dispensary_name": "Cookies SF",
    "notes": "Perfect for creative work. Felt super focused but relaxed.",
    "rating": 5,
    "effects": ["relaxed", "creative", "focused"],
    "mood_before": ["stressed", "tired"],
    "mood_after": ["calm", "energized"],
    "method": "joint",
    "amount_grams": 0.5
}
```

#### 1.2 `app.buds.session.updated/v1`

**Purpose**: Edit an existing session (creates new receipt with `parentCID`)

**Payload Schema**: Same as `session.created/v1`

**Notes**:
- Sets `parentCID` to previous version
- `rootCID` stays the same (points to first version)
- Creates edit chain: root → v2 → v3 → ...

---

### 2. Circle Management Receipts

#### 2.1 `app.buds.circle.invite.created/v1`

**Purpose**: Generate an invite link for a friend

**Payload Schema**:

```swift
{
    "claimed_time_ms": Int64,         // When invite was created
    "invite_code": String,            // UUID or short code
    "inviter_did": String,            // Your DID (no name - stored locally only)
    "expires_at": Int64?,             // Unix milliseconds (optional)
    "max_uses": Int?,                 // Default 1
    "message": String?,               // Optional note
}
```

**Note**: Display names are stored locally in the `circles` table, not in receipts (no PII in receipts).

**Example**:

```json
{
    "claimed_time_ms": 1704844800000,
    "invite_code": "BUDS-A7F3-92B1",
    "inviter_did": "did:buds:local-ABC123",
    "expires_at": 1704931200000,
    "max_uses": 1,
    "message": "Let's track our smoke sessions together!"
}
```

#### 2.2 `app.buds.circle.invite.accepted/v1`

**Purpose**: Record accepting an invite

**Payload Schema**:

```swift
{
    "claimed_time_ms": Int64,         // When invite was accepted
    "invite_code": String,            // The code that was used
    "inviter_did": String,            // Inviter's DID
    "invitee_did": String,            // Your DID (no name - stored locally only)
    "invitee_pubkey_x25519": String,  // Base64 X25519 public key for E2EE
}
```

**Note**: Display names are stored locally in the `circles` table, not in receipts (no PII in receipts).

**Example**:

```json
{
    "claimed_time_ms": 1704844900000,
    "invite_code": "BUDS-A7F3-92B1",
    "inviter_did": "did:buds:local-ABC123",
    "invitee_did": "did:buds:local-XYZ789",
    "invitee_pubkey_x25519": "Wy0xMjM0NTY3ODkwMTIzNDU2Nzg5MDEyMzQ1Njc4OTA="
}
```

#### 2.3 `app.buds.circle.member.removed/v1`

**Purpose**: Remove someone from your Circle (or leave a Circle)

**Payload Schema**:

```swift
{
    "claimed_time_ms": Int64,         // When removal occurred
    "removed_did": String,            // Who was removed
    "removed_by_did": String,         // Who removed them
    "reason": String?,                // Optional reason
}
```

**Example**:

```json
{
    "claimed_time_ms": 1704850000000,
    "removed_did": "did:buds:local-XYZ789",
    "removed_by_did": "did:buds:local-ABC123",
    "reason": "voluntary_leave"
}
```

---

### 3. Sharing Receipts

#### 3.1 `app.buds.memory.shared/v1`

**Purpose**: Share a memory to Circle or specific friends

**Payload Schema**:

```swift
{
    "claimed_time_ms": Int64,         // When share action occurred
    "memory_cid": String,             // CID of the session receipt being shared
    "shared_with": [String],          // Array of DIDs (or "circle" for all)
    "permissions": String,            // "view" | "view_location" | "full"
    "message": String?,               // Optional context
}
```

**Example**:

```json
{
    "claimed_time_ms": 1704855000000,
    "memory_cid": "bafyreiabc123...",
    "shared_with": ["circle"],
    "permissions": "view",
    "message": "Check out this strain, it was fire"
}
```

#### 3.2 `app.buds.memory.unshared/v1`

**Purpose**: Revoke share (remove from Circle view)

**Payload Schema**:

```swift
{
    "claimed_time_ms": Int64,         // When unshare occurred
    "memory_cid": String,             // CID of the session receipt
    "unshared_from": [String],        // DIDs to revoke from (or "circle")
}
```

**Example**:

```json
{
    "claimed_time_ms": 1704856000000,
    "memory_cid": "bafyreiabc123...",
    "unshared_from": ["circle"]
}
```

---

### 4. Location Receipts (Privacy-Protected)

#### 4.1 `app.buds.location/v1`

**Purpose**: Store location data separately (can be shared with different granularity)

**Payload Schema**:

```swift
{
    "claimed_time_ms": Int64,         // When location was captured
    "location_type": String,          // "precise" | "fuzzy" | "named"

    // Precise location (only stored locally unless explicitly shared)
    "latitude": Double?,              // 37.7749
    "longitude": Double?,             // -122.4194
    "altitude": Double?,              // Meters
    "accuracy": Double?,              // Meters

    // Fuzzy location (for Circle sharing)
    "fuzzy_lat": Double?,             // Snapped to 500m grid
    "fuzzy_lon": Double?,             // Snapped to 500m grid
    "fuzzy_radius": Int?,             // 500 (meters)

    // Named location
    "place_name": String?,            // "Golden Gate Park"
    "place_category": String?,        // "park" | "home" | "dispensary" | "other"

    // Metadata
    "delay_share_until": Int64?,      // Optional delayed visibility (milliseconds)
}
```

**Example (Precise)**:

```json
{
    "claimed_time_ms": 1704844800000,
    "location_type": "precise",
    "latitude": 37.7749,
    "longitude": -122.4194,
    "accuracy": 10.5,
    "place_name": "Golden Gate Park"
}
```

**Example (Fuzzy for Circle)**:

```json
{
    "claimed_time_ms": 1704844800000,
    "location_type": "fuzzy",
    "fuzzy_lat": 37.775,
    "fuzzy_lon": -122.420,
    "fuzzy_radius": 500,
    "place_name": "SF",
    "delay_share_until": 1704851200000
}
```

---

### 5. Preference & Profile Receipts

#### 5.1 `app.buds.preferences.updated/v1`

**Purpose**: Record user preferences (private, not shared)

**Payload Schema**:

```swift
{
    "claimed_time_ms": Int64,              // When preferences were updated
    "default_location_sharing": String,    // "off" | "fuzzy" | "precise"
    "default_share_visibility": String,    // "private" | "circle"
    "favorite_strains": [String],          // Array of strain names
    "avoid_effects": [String],             // Effects to warn about
    "preferred_dispos": [String],          // Favorite dispensaries
}
```

#### 5.2 `app.buds.profile.updated/v1` (DEPRECATED - Use Local Storage)

**Purpose**: ~~Update display profile (shared with Circle)~~ **DEPRECATED**

**Note**: Profile information (display_name, avatar, bio) should be stored locally in the `circles` table, NOT as receipts. This receipt type is reserved for future use if Circle-only profile sharing is implemented with explicit consent. For v0.1, profiles are local-only metadata.

---

### 6. Deletion & Tombstone Receipts (Append-Only Pattern)

**CRITICAL**: Buds uses an append-only architecture. Nothing is ever truly deleted or mutated. Instead, deletions create **tombstone receipts** that mark items as removed while preserving the complete history for audit/sync purposes.

The UI filters out tombstoned items, but the receipt chain is permanently preserved.

#### 6.1 `app.buds.memory.deleted/v1`

**Purpose**: Tombstone a memory (user deleted it)

**Payload Schema**:

```swift
{
    "claimed_time_ms": Int64,         // When deletion occurred
    "memory_cid": String,             // CID of the session receipt being deleted
    "reason": String?,                // Optional: "user_deleted" | "duplicate" | "mistake"
    "cascade_unshare": Bool,          // If true, also unshare from Circle
}
```

**Example**:

```json
{
    "claimed_time_ms": 1704860000000,
    "memory_cid": "bafyreiabc123...",
    "reason": "user_deleted",
    "cascade_unshare": true
}
```

**Notes**:
- Original receipt remains in database
- UI queries filter out receipts with deletion tombstones
- Sync propagates tombstone to all devices
- Circle members who received share also see tombstone

#### 6.2 `app.buds.device.revoked/v1`

**Purpose**: Revoke a device (lost phone, logout, security)

**Payload Schema**:

```swift
{
    "claimed_time_ms": Int64,         // When revocation occurred
    "revoked_device_id": String,      // Device ID being revoked
    "revoked_by_device_id": String,   // Device ID that performed revocation
    "reason": String?,                // "lost" | "stolen" | "logout" | "security"
}
```

**Example**:

```json
{
    "claimed_time_ms": 1704844800000,
    "revoked_device_id": "F3A7C2B1-8D4E-4F9A-B2C6-7E8F9A0B1C2D",
    "revoked_by_device_id": "A1B2C3D4-5E6F-7A8B-9C0D-1E2F3A4B5C6D",
    "reason": "lost"
}
```

**Notes**:
- Revoked device can no longer decrypt new Circle messages
- Existing messages remain encrypted with old key
- Relay server rejects messages from revoked devices
- User can re-register device (generates new device_id)

#### 6.3 `app.buds.circle.member.removed/v1`

**Already defined in Section 2.3** - Tombstones Circle membership

---

### 7. Daily Summary Receipts (for Agent)

#### 7.1 `app.buds.daily.summary/v1`

**Purpose**: Aggregate daily statistics (generated automatically)

**Payload Schema**:

```swift
{
    "claimed_time_ms": Int64,         // When summary was generated
    "date": String,                   // "2024-12-16" (ISO date)
    "session_count": Int,             // Number of sessions
    "total_amount_grams": Double?,    // Total consumed
    "unique_strains": [String],       // Strains used today
    "dominant_effects": [String],     // Most common effects
    "avg_rating": Double?,            // Average rating
    "locations_visited": [String],    // Named locations
}
```

**Example**:

```json
{
    "claimed_time_ms": 1704931200000,
    "date": "2024-12-16",
    "session_count": 3,
    "total_amount_grams": 1.5,
    "unique_strains": ["Blue Dream", "Gelato"],
    "dominant_effects": ["relaxed", "creative"],
    "avg_rating": 4.3,
    "locations_visited": ["Home", "Park"]
}
```

---

## Blob References

**For photos, videos, and other large media**

```swift
struct BlobReference {
    let cid: String                   // CID of blob content
    let mimeType: String              // "image/jpeg", "video/mp4"
    let size: Int                     // Bytes
    let encrypted: Bool               // Whether blob is encrypted
}
```

Blobs are stored separately and referenced by CID in receipts.

---

## Effect Tag Taxonomy

**Standard effects** (can be extended by users):

### Positive Effects
- `relaxed` - Calm, stress-free
- `creative` - Artistic, ideas flowing
- `focused` - Concentrated, attentive
- `energized` - Active, motivated
- `happy` - Euphoric, uplifted
- `hungry` - Munchies
- `sleepy` - Ready for bed
- `social` - Talkative, outgoing
- `euphoric` - Intense happiness

### Negative Effects
- `anxious` - Worried, nervous
- `paranoid` - Distrustful, fearful
- `dizzy` - Lightheaded
- `tired` - Fatigued (not sleepy)
- `dry_mouth` - Cottonmouth
- `dry_eyes` - Red, irritated eyes
- `headache` - Pain, discomfort
- `nauseous` - Upset stomach

### Neutral/Context
- `body_high` - Physical sensation
- `head_high` - Cerebral sensation
- `couch_lock` - Unable to move
- `time_distortion` - Time feels different

---

## Validation Rules

### Field Constraints

| Field | Min | Max | Format |
|-------|-----|-----|--------|
| `notes` | 0 | 5000 chars | UTF-8 |
| `rating` | 1 | 5 | Integer |
| `thc_percent` | 0 | 100 | Double |
| `cbd_percent` | 0 | 100 | Double |
| `amount_grams` | 0 | 1000 | Double |
| `display_name` | 1 | 50 chars | UTF-8 |
| `bio` | 0 | 280 chars | UTF-8 |

### Timestamp Rules

- All timestamps are Unix time in **milliseconds** (not seconds) since epoch
- `claimed_time_ms` is an unverifiable claim by the author (offline-first design allows any value)
- `expires_at` must be in the future (validated at creation time)
- `delay_share_until` must be > `claimed_time_ms`

---

## Payload Evolution & Versioning

### Adding New Fields

**Safe (backward compatible)**:
- Add optional fields to existing schemas
- Parsers must ignore unknown fields
- Old clients can read new receipts (ignore new fields)

**Breaking (requires version bump)**:
- Remove required fields
- Change field types
- Change field semantics

Example:
```
app.buds.session.created/v1  →  app.buds.session.created/v2
```

### Schema Migration

When schema changes:
1. Bump version number (`/v2`)
2. Update `ReceiptManager` to support both versions
3. Write migration code to convert old receipts (if needed)
4. Document changes in CHANGELOG

---

## Receipt Size Limits

| Receipt Type | Max Payload Size |
|--------------|------------------|
| Session | 50 KB |
| Circle management | 10 KB |
| Sharing | 5 KB |
| Location | 5 KB |
| Preferences | 20 KB |
| Daily summary | 50 KB |

**Note**: Large media (photos, videos) are stored as blobs with CID references, not in the payload.

---

## Example: Full UCRHeader

```json
{
    "cid": "bafyreibwkqzkfjzfh7q3kx4k6p3nmhzchqkj5yzw4t6n7j5qzk3r5y7u4e",
    "did": "did:buds:local-5dGHK7P9mN",
    "deviceId": "F3A7C2B1-8D4E-4F9A-B2C6-7E8F9A0B1C2D",
    "parentCID": null,
    "rootCID": "bafyreibwkqzkfjzfh7q3kx4k6p3nmhzchqkj5yzw4t6n7j5qzk3r5y7u4e",
    "receiptType": "app.buds.session.created/v1",
    "payload": {
        "claimed_time_ms": 1704844800000,
        "product_name": "Blue Dream",
        "strain_type": "hybrid",
        "thc_percent": 23.5,
        "notes": "Perfect for creative work",
        "rating": 5,
        "effects": ["relaxed", "creative", "focused"],
        "method": "joint",
        "amount_grams": 0.5
    },
    "blobs": [],
    "signature": "Wy0xMjM0NTY3ODkwMTIzNDU2Nzg5MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MA=="
}
```

---

## Next Steps

- Implement `ReceiptManager.create()` for each receipt type
- Add validation layer
- Create unit tests for CBOR encoding/decoding
- Test payload size limits
- Document extension mechanism for custom fields

---

**See Also**:
- [ARCHITECTURE.md](./ARCHITECTURE.md) - Overall system design
- [DATABASE_SCHEMA.md](./DATABASE_SCHEMA.md) - Storage layer
- [E2EE_DESIGN.md](./E2EE_DESIGN.md) - Encryption for shared receipts
