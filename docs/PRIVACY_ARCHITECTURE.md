# Buds Privacy Architecture

**Last Updated:** December 20, 2025
**Version:** v0.1 (Phase 5: Circle Privacy Model Complete)
**Principle:** Privacy by Default, Consent Before Collection

---

## Overview

Buds is designed with **privacy-first** principles, ensuring user control over sensitive data:
- **Location**: OFF by default, with fuzzing and delayed sharing
- **Share state**: Explicit opt-in for every memory shared to Circle
- **Revocability**: Unshare removes future access (honest but limited)
- **Local-first**: Data stays on device unless explicitly shared

## Privacy Invariants (Non-Negotiable)

These guardrails must never be violated:

1. **Location OFF by default** - No GPS access unless user explicitly enables
2. **No precise location shared unless explicit per-memory consent** - Fuzzy (~500m grid) is default for Circle sharing
3. **Receipts contain no phone/email/name** - DIDs are cryptographic identifiers only
4. **Relay never sees plaintext** - E2EE for all Circle shares (relay sees only ciphertext + pseudonymous metadata)
5. **Unshare is best-effort, not retroactive delete** - Cannot force deletion on already-synced peer devices
6. **Circle roster is local-only** - Friend list never leaves your device (relay never sees who's in your Circle)
7. **Phone numbers hashed client-side** - Relay never sees plaintext phone numbers (SHA-256 hash only)
8. **Display names are local nicknames** - No global username namespace (privacy-preserving)

---

## Location Privacy

### Problem Statement

**Risk:** Cannabis consumption is federally illegal in the US and illegal in many jurisdictions. Precise location data could be used for:
- Law enforcement (illegal in some states/countries)
- Employer discrimination
- Insurance profiling
- Social stigma

**Goal:** Enable useful location features (map, "where did I smoke this strain?") while protecting users from unwanted exposure.

---

### Location Modes

#### Mode 1: Location OFF (Default)

**What it does:**
- No location data captured
- No GPS access requested
- User can manually add place name (text only)

**UX:**
```swift
// Create memory screen
[ ] Enable Location (OFF)

Place name (optional): [Home_________________]
```

**Stored in DB:**
```sql
-- locations table
location_type: "named"
place_name: "Home"
latitude: NULL
longitude: NULL
```

---

#### Mode 2: Precise Location (Private)

**What it does:**
- Capture precise GPS coordinates
- Store locally only
- Never shared unless user explicitly enables "Share Precise Location"

**UX:**
```swift
[✓] Enable Location (ON)

📍 Captured: 37.7749°N, 122.4194°W (±10m)

Share with Circle:
( ) Don't share location
( ) Share fuzzy location (within 500m)
( ) Share precise location [⚠️ Warning]
```

**Stored in DB:**
```sql
location_type: "precise"
latitude: 37.7749
longitude: -122.4194
accuracy: 10.5
fuzzy_lat: NULL  -- Only computed if shared
fuzzy_lon: NULL
```

**Sharing behavior:**
- Default: Location not shared (null in `EncryptedMessage`)
- Explicit opt-in required for fuzzy or precise

---

#### Mode 3: Fuzzy Location (Circle Sharing)

**What it does:**
- Snaps coordinates to 500m grid (default, user may choose tighter granularity later)
- Adds noise (random offset within cell)
- Optionally delays visibility (share after 2 hours)

**Algorithm:**

```swift
func fuzzyLocation(
    _ precise: CLLocationCoordinate2D,
    gridSize: Double = 0.005  // ~500m at mid-latitudes
) -> CLLocationCoordinate2D {
    // Snap to grid
    let gridLat = floor(precise.latitude / gridSize) * gridSize
    let gridLon = floor(precise.longitude / gridSize) * gridSize

    // Add random offset within cell
    let offsetLat = Double.random(in: 0..<gridSize)
    let offsetLon = Double.random(in: 0..<gridSize)

    return CLLocationCoordinate2D(
        latitude: gridLat + offsetLat,
        longitude: gridLon + offsetLon
    )
}
```

**Example:**
```
Precise:  37.774929, -122.419416 (Golden Gate Park)
Fuzzy:    37.775000, -122.420000 (~250m offset)
```

**Stored in DB:**
```sql
location_type: "fuzzy"
latitude: 37.774929       -- Private (not shared)
longitude: -122.419416
fuzzy_lat: 37.775000      -- Shared with Circle
fuzzy_lon: -122.420000
fuzzy_radius: 500
delay_share_until_ms: 1704851200000  -- Share after 2 hours (Unix milliseconds)
```

---

### Location Consent Flow

**Step 1: First-time location request**

```swift
// Shown when user taps "Enable Location" for first time
AlertView {
    title: "Enable Location?"
    message: """
    Buds can remember where you enjoyed different strains.

    Your location is:
    • Stored locally on your device
    • Never shared by default
    • Optional fuzzing for Circle sharing

    You control what's shared.
    """
    actions: [
        "Enable Location",
        "Not Now"
    ]
}
```

**Step 2: Per-memory sharing consent**

```swift
// Shown when user taps "Share to Circle" on a memory with location
AlertView {
    title: "Share Location with Circle?"
    message: """
    This memory has location data.

    Choose what to share:
    """
    options: [
        "Don't share location" (default),
        "Share fuzzy location (~500m)",
        "Share precise location (⚠️ Exact address)"
    ]
}
```

**Step 3: Delayed sharing (optional)**

```swift
Toggle("Delay share by 2 hours", isOn: $delayShare)

InfoText: """
Location will appear on Circle map 2 hours after you created this memory.
Helps protect real-time location privacy.
"""
```

---

### Map Privacy

**Personal Map (private)**

```swift
// Only shows YOUR memories with location enabled
// Pins = precise location (you see your exact spots)
```

**Circle Map (shared)**

```swift
// Shows memories shared by Circle members
// Pins = fuzzy location (snapped to grid)
// Tap pin → shows memory preview (if permissions allow)

MapAnnotation {
    coordinate: fuzzyLocation
    color: memberColor
    subtitle: "Alice • 2 hours ago"
}
```

**Privacy protection on Circle Map:**
1. **Fuzzing**: Coordinates snapped to 500m grid
2. **Clustering**: Multiple memories at same location shown as cluster
3. **Delayed visibility**: Optional 2-hour delay before appearing
4. **Revocable**: Unsharing removes from map

---

## Share State Management

### Problem: What Does "Unshare" Actually Do?

**Honest answer:**
- ✅ Removes memory from Circle feed/map
- ✅ Stops future device decryption (if keys revoked)
- ❌ Can't delete already-decrypted data from their device
- ❌ Can't prevent screenshots or copying

### Share State Model

**States:**
1. **Private** (default): Only you can see
2. **Shared to Circle**: All active Circle members can decrypt
3. **Unshared**: Removed from Circle (but not deleted from devices)

**Implementation (see DATABASE_SCHEMA.md for canonical table):**

```sql
-- Simplified representation (actual table has E2EE fields)
CREATE TABLE shared_memories (
    id TEXT PRIMARY KEY NOT NULL,           -- UUID
    memory_cid TEXT NOT NULL,               -- CID of session receipt
    shared_with TEXT NOT NULL,              -- JSON array of DIDs or "circle"
    permissions TEXT NOT NULL,              -- 'view' | 'view_location' | 'full'
    encrypted_payload BLOB,                 -- E2EE ciphertext (raw CBOR)
    wrapped_keys_json TEXT,                 -- JSON: {device_id: wrapped_key}
    nonce TEXT,                             -- Base64 AES-GCM nonce (DEPRECATED - use sealed.combined)
    message TEXT,                           -- Optional share message
    shared_at REAL NOT NULL,
    unshared_at REAL,                       -- NULL = still shared
    FOREIGN KEY (memory_cid) REFERENCES ucr_headers(cid) ON DELETE CASCADE
);
```

**Note:** See DATABASE_SCHEMA.md for the canonical definition with all E2EE fields. The `encrypted_payload` contains `sealed.combined` (nonce || ciphertext || tag), not separate fields.

**Query for "currently shared" memories:**

```sql
SELECT *
FROM shared_memories
WHERE unshared_at IS NULL;
```

---

### Permissions Levels

| Permission | Can See |
|------------|---------|
| `view` | Product, strain, notes, effects, rating |
| `view_location` | Same as `view` + fuzzy location |
| `full` | Same as `view_location` + precise location + photos |

**Example:**

```swift
// Share with view-only (no location)
shareMemory(cid, to: .circle, permissions: .view)

// Share with fuzzy location
shareMemory(cid, to: .circle, permissions: .viewLocation)
```

**Enforcement:**

```swift
func encryptMemoryPayload(
    _ receipt: UCRHeader,
    permissions: SharePermissions
) throws -> Data {
    // CRITICAL: Encrypt the raw canonical CBOR, not JSON
    let rawCBOR = receipt.raw_cbor

    // For redacted shares, create a redacted receipt (new CID)
    // and encrypt that receipt's raw CBOR instead
    let shareableReceipt: UCRHeader

    switch permissions {
    case .view:
        shareableReceipt = try createRedactedReceipt(
            from: receipt,
            redact: [.location, .photos, .privateNotes]
        )
    case .viewLocation:
        shareableReceipt = try createRedactedReceipt(
            from: receipt,
            redact: [.photos, .privateNotes],
            fuzzyLocation: true  // Replace precise with fuzzy
        )
    case .full:
        shareableReceipt = receipt  // No redactions
    }

    return shareableReceipt.raw_cbor  // Always encrypt canonical CBOR
}
```

**Redaction matrix:**

| Permission | product_name | strain | effects | notes | rating | location_cid | photo_cids | local_notes |
|------------|-------------|--------|---------|-------|--------|--------------|------------|-------------|
| `view` | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| `view_location` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ (fuzzy) | ❌ | ❌ |
| `full` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ (precise) | ✅ | ❌ |

**Note:** `local_notes` are NEVER shared (always device-only).

---

## Circle Privacy Model (Phase 5+)

### Local-Only Friend Rosters

Buds implements a **zero-knowledge social graph** architecture:

**What the relay server CANNOT see:**
- Your Circle roster (who your friends are)
- Friend display names (local nicknames only)
- Who you're sharing with (only encrypted messages + device IDs, no DID→name mapping)

**What the relay server CAN see (metadata leakage):**
- Hashed phone numbers during lookups (SHA-256, one-way)
- Device IDs that message each other (pseudonymous social graph)
- Message frequency between devices (traffic analysis)
- IP addresses (temporarily, for abuse prevention)

**Architecture comparison:**

| Privacy Property | Buds (Local Roster) | Centralized Platform (Server Roster) |
|------------------|---------------------|-------------------------------------|
| **Friend list** | Stored on device only | Stored on server |
| **Display names** | Local nicknames | Global usernames |
| **Social graph** | Server sees message metadata only | Server sees full friend graph |
| **Discovery** | Phone hash lookup (one-way) | Server-side search |
| **Privacy level** | **Pseudonymous metadata** | Full social graph visible |

**Important distinction:** This is **NOT anonymous** (relay sees pseudonymous device/DID identifiers), but it's **privacy-preserving** (relay doesn't know real-world identities or your friend list).

---

### Phone Number Privacy

**Problem:** How to find friends by phone number without giving the relay everyone's phone numbers?

**Solution:** Client-side hashing + one-way lookup table

**Flow:**

```swift
// Adding a friend
User enters: "+14155551234"
  ↓
Client hashes: SHA-256("+14155551234") = "a7b3c4d5e6f7..."
  ↓
Client queries: POST /api/lookup/did { phoneHash: "a7b3c4d5e6f7..." }
  ↓
Relay responds: { did: "did:buds:abc123" }
  ↓
Client stores: CircleMember(did="did:buds:abc123", displayName="Alice", phoneNumber="+14155551234")
  ↓
Phone number lives ONLY on your device (never sent to relay, never in receipts)
```

**Privacy guarantees:**

✅ **Relay never sees plaintext phone numbers** (SHA-256 hash only)
✅ **Phone numbers never in receipts** (only DIDs)
✅ **Phone numbers stored locally only** (optional display field)
❌ **Phone hash is queryable** (anyone who knows a phone number can hash it and query the relay)

**Attack vector:** Rainbow table attack

- Attacker could precompute SHA-256 hashes for all US phone numbers (~400M hashes)
- Query relay for each hash → build a "who's using Buds" database
- **Mitigation:** Rate limiting (20 lookups/minute) makes bulk scraping impractical
- **Trade-off:** We prioritize UX (easy friend discovery) over perfect anonymity

**Why not use a keyed hash (HMAC)?**
- HMAC requires a secret key shared between all clients
- If key leaks, entire system breaks
- SHA-256 is simple, transparent, and doesn't rely on secret key security

---

### Display Names: Local Nicknames, Not Global Usernames

**Privacy principle:** No global username namespace

**Implementation:**

```swift
// Alice adds Bob to her Circle
Alice's device stores:
  CircleMember(did="did:buds:bob123", displayName="Bobby")

// Bob adds Alice to his Circle
Bob's device stores:
  CircleMember(did="did:buds:alice456", displayName="Mom")

// Relay server NEVER sees "Bobby" or "Mom"
// Each user chooses their own nicknames for friends
```

**Privacy benefits:**

✅ **No username enumeration** (can't scrape a user directory)
✅ **Flexibility** (call your friend "Mom" instead of their legal name)
✅ **Offline functionality** (no server lookup to display names)
✅ **Privacy-preserving** (relay can't build a real-name → DID mapping)

**Trade-off:** Circle members don't control how you refer to them in your app

---

### Circle Metadata Leakage

**What the relay CAN infer from encrypted messages:**

1. **Device communication graph**
   - Device A messages Device B, C, D
   - Frequency: A messages B 5x/day
   - Inference: A and B likely in each other's Circle

2. **Timing patterns**
   - Messages sent at 4:20pm consistently
   - Inference: Possible usage pattern (cannabis culture reference)

3. **Message sizes**
   - Encrypted payload 5KB → likely text-only
   - Encrypted payload 500KB → likely includes photo
   - Inference: Photo-heavy shares vs text-only

4. **IP address clustering**
   - Devices X, Y, Z all connect from same IP range
   - Inference: Possible geographic proximity

**Mitigations (current):**
- Rate limiting (prevents bulk scraping)
- Short retention (7 days max)
- No long-term analytics

**Future enhancements (post-v0.1, non-committed):**
- Padding messages to uniform size (hides photo vs text)
- Random delay injection (hides timing patterns)
- Onion routing (hides IP addresses)

---

### 12-Member Limit: Privacy-Enhancing Constraint

**Design decision:** Enforce max 12 Circle members

**Privacy rationale:**

1. **Trust model**: Small group = easier to trust (less attack surface)
2. **Key distribution**: Fewer devices = simpler E2EE key management
3. **Metadata minimization**: Smaller social graph = less metadata leakage
4. **UX**: Intimate friend group (not a social network)

**Alternative rejected:** Unlimited Circle members
- Would create large social graphs (more metadata)
- Higher risk of malicious member (harder to vet 100 people)
- Complex key distribution (O(n²) device pairs)

---

## Identity & Pseudonymity

### DID Structure

**Format:** `did:buds:<base58(ed25519_pubkey_first_20_bytes)>`

**Example:** `did:buds:5dGHK7P9mNqR8vZw3T`

**Generation:**
```swift
// DID is ALWAYS derived from Ed25519 signing public key
let ed25519Keypair = try IdentityManager.shared.getEd25519Keypair()
let pubkeyBytes = ed25519Keypair.publicKey.rawRepresentation
let did = "did:buds:" + Base58.encode(pubkeyBytes.prefix(20))
```

**Key principle:** DID is a stable, cryptographic identifier derived from the user's signing keypair. It is NOT tied to any platform (Firebase, phone number, etc.).

### Pseudonymity Guarantees

**What's NOT linked to real identity:**
- DIDs are pseudonymous (no name, email, phone in DID)
- DIDs are derived from cryptographic keys only
- Receipts don't contain PII
- **Important:** Relay still sees pseudonymous metadata (DIDs, device IDs, timestamps, connection IPs)

**What IS linkable (mapping layer only):**
- **Firebase Auth**: Phone number → Firebase UID mapping (for phone verification only, Firebase server-side)
- **Relay server**: Hashed phone → DID mapping (SHA-256, one-way, for friend discovery)
- **Circle members**: Display names are local-only (each user chooses their own nicknames, never shared with relay)
- **Network layer**: IP addresses may be in relay logs temporarily (abuse prevention, auto-deleted after 7 days)

**Privacy note:** "Pseudonymous" ≠ "anonymous". The relay can build a social graph (DID A messages DIDs B, C, D) but cannot read message contents or definitively link DIDs to real identities without external data sources.

### Auth Migration: Anonymous → Authenticated

**v0.1 approach: Single stable DID (no migration)**

```swift
// User's DID is derived from their Ed25519 keypair (generated once on first launch)
let did = "did:buds:5dGHK7P9mNqR8vZw3T"  // Stable forever

// When user signs in with Firebase:
// - Firebase UID → DID mapping stored on relay (for device discovery)
// - DID itself never changes (no receipt re-signing needed)
// - Phone number lives only in Firebase Auth layer (never in receipts)
```

**Database handling:**

```sql
-- All receipts signed with same stable DID
SELECT * FROM ucr_headers WHERE did = 'did:buds:5dGHK7P9mNqR8vZw3T';

-- Firebase UID mapping (relay server only, not in app DB)
-- Stored as: firebase_uid='abc123' → did='did:buds:5dGHK7P9mNqR8vZw3T'
```

---

## Data Minimization

### What We Collect (On-Device Only)

**Always collected:**
- Session payload (strain, effects, notes, rating)
- Timestamps (device time)
- Device ID (for sync)

**Optional (user control):**
- Location (OFF by default)
- Photos (user chooses to attach)
- Dispensary name (user fills in)

### What We DON'T Collect (or Collect Minimally)

❌ Real name (unless user sets as display name for Circle - stored locally only)
❌ Email address
❌ Phone number (Firebase Auth layer only, never in receipts or local DB)
⚠️ IP addresses (relay may log temporarily for abuse prevention, not used for profiling, auto-deleted after 7 days)
❌ Browsing history
❌ Ad tracking
❌ Device fingerprinting (beyond basic device_id for sync)

---

## Data Retention

### Local Storage

**User-controlled:**
- Memories stored indefinitely (until user deletes)
- Export/import supported (own your data)

**Auto-cleanup:**
- Old blob thumbnails (after 90 days if original deleted)

### Relay Server

**Messages:**
- Stored encrypted for max 7 days
- Auto-deleted after first fetch (configurable)
- No message history retained

**Devices:**
- Active device metadata retained indefinitely
- Revoked device metadata retained for 90 days (audit)

**Rate limits:**
- Counters expire after window (1 hour)
- No long-term history

---

## Compliance & Legal

### Jurisdictional Challenges

**Cannabis legal status varies:**
- Federal (US): Schedule I (illegal)
- State-level: Legal in 24 states (medical/recreational)
- International: Illegal in most countries

**Buds' approach:**
- No sales facilitation (no marketplace)
- No medical claims (we're a memory tool, not health advice)
- User age gating (21+ where applicable)
- Location privacy to mitigate legal risk

### GDPR / CCPA Compliance (Designed For, Not Guaranteed)

**Note:** Buds is designed with GDPR/CCPA principles in mind, but full compliance requires legal review. The distributed nature of E2EE creates limitations.

**User rights (what we can do):**

| Right | Buds Implementation | Limitations |
|-------|---------------------|-------------|
| Access | Export all local receipts (CBOR + JSON) | ✅ Full access to your device data |
| Rectification | Edit receipts (creates new version via parentCID chain) | ⚠️ Original receipt remains in chain (append-only) |
| Erasure | Delete local data + stop relay delivery | ⚠️ **Cannot force deletion on peer devices** (E2EE means we can't access their data) |
| Portability | Export receipts + blobs in standard formats | ✅ You own your data |
| Object to processing | Opt-out of Agent, dispensary insights, Circle sharing | ✅ Granular controls |

**Important limitation:** "Erasure" in a local-first, E2EE system means:
- ✅ Delete data from YOUR devices
- ✅ Remove from relay (stops future delivery)
- ✅ Revoke Circle share (removes from their feed/map)
- ❌ **Cannot delete data already synced to peer devices** (this is a fundamental property of E2EE)

**Data processing:**
- Primary: On-device (you control)
- Secondary: Relay server (ciphertext only, ephemeral, 7-day retention)
- Third-party: Firebase Auth (phone verification only), LLM APIs (if Agent enabled)

---

## Privacy UI Patterns

### 1. Privacy Indicators

**Show privacy status clearly:**

```swift
// Memory card in timeline
MemoryCard {
    title: "Blue Dream"
    location: "📍 Home" or "📍 San Francisco (~500m)" or "🔒 Private"
    shareStatus: "🌍 Shared with Circle" or "🔐 Private"
}
```

### 2. Consent Prompts

**Always explain before collecting:**

```swift
// Before enabling location
"Your location helps you remember where you enjoyed strains.
It stays on your device unless you choose to share with Circle."

// Before sharing memory
"Circle members will be able to see this memory, including
fuzzy location and effects. You can unshare anytime."
```

### 3. Privacy Dashboard

**Settings → Privacy:**

```swift
VStack {
    Section("Location") {
        Toggle("Enable Location Capture", isOn: $locationEnabled)
        Picker("Default Share Mode", selection: $defaultShareMode) {
            Text("Never share location")
            Text("Fuzzy (500m)")
            Text("Precise (exact)")
        }
        Toggle("Delay location share by 2 hours", isOn: $delayShare)
    }

    Section("Circle Sharing") {
        Text("Shared memories: \(sharedCount)")
        Button("Review shared memories") { }
    }

    Section("Data Export") {
        Button("Export all data") { exportData() }
        Button("Delete account") { deleteAccount() }
    }
}
```

---

## Threat Scenarios & Mitigations

### Scenario 1: Law Enforcement Subpoena

**Attack:** Police subpoena user's device

**What they can see:**
- All local receipts (if device unlocked)
- Plaintext notes, locations, photos
- All decrypted Circle shares

**Mitigations (v0.1):**
- **iOS device encryption**: Data encrypted at rest when device locked (iOS Data Protection)
- **Passcode/FaceID/TouchID**: Standard iOS lock screen protection
- **Biometric re-auth** (optional): Require FaceID to open sensitive screens (Settings → Privacy)
- **User education**: "Buds stores data locally. Keep your device locked and use a strong passcode."
- **Legal**: No centralized database to subpoena (relay only has encrypted blobs for 7 days max)

**Future enhancements (post-v0.1, non-committed):**
- App-level encryption (additional passcode on top of iOS encryption)
- Decoy mode (fake receipts if coerced to unlock)
- Secure enclave storage for keys

---

### Scenario 2: Employer / Insurance Snooping

**Attack:** Employer sees you use Buds and assumes you consume cannabis

**Mitigations:**
- App icon/name doesn't scream "weed" (user choice)
- No social media integration (no "I just smoked on Facebook")
- Private by default (no public profile)

---

### Scenario 3: Jealous Partner / Friend

**Attack:** Someone with device access reads your memories

**Mitigations:**
- Biometric re-auth for sensitive screens (optional)
- "Private notes" field (hidden from Circle shares)
- Delete individual memories easily

---

### Scenario 4: Relay Server Seizure

**Attack:** Government seizes Cloudflare servers

**What they can see:**
- Encrypted messages (ciphertext only)
- Device IDs, DIDs (pseudonymous)
- Timestamps

**What they can't see:**
- Plaintext messages
- User identities (unless they also subpoena Firebase)
- AES keys (only recipients have them)

**Mitigation:** E2EE ensures relay server is untrusted.

---

## Future Privacy Enhancements (Post-v0.1, Non-Committed Research Ideas)

**IMPORTANT:** The following are exploratory ideas, NOT commitments. They may or may not be implemented based on user demand, technical feasibility, and legal considerations.

### Possible Future Features

1. **Local database encryption** (app-level passcode on top of iOS encryption)
   - Additional layer: requires passcode to decrypt GRDB even if device unlocked
   - Trade-off: UX friction vs enhanced security

2. **Decoy mode** (fake receipts if coerced to unlock)
   - Controversial: May be illegal in some jurisdictions (obstruction)
   - Research only

3. **Self-destructing messages** (auto-delete after N days)
   - Requires peer cooperation (can't force deletion)
   - Best-effort only

4. **Anonymous Circle invites** (invite without revealing DID until accepted)
   - Complexity: How to wrap keys before knowing recipient DID?
   - May require additional crypto (blind signatures, etc.)

5. **Onion routing** (Tor-style relay for metadata privacy)
   - Hides IP addresses from relay
   - Performance trade-off
   - May conflict with abuse prevention

---

**Next:** See [AGENT_INTEGRATION.md](./AGENT_INTEGRATION.md) for cannabis expert AI design.
