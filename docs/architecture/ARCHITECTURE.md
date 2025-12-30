# Buds v0.1 — System Architecture

**Last Updated:** December 30, 2025
**Status:** Phase 10.1 In Progress (Beta Preparation) — Modules 1.4, 1.5, 2.3 Complete
**Target:** TestFlight Beta with Multi-User Reactions & Jar Management

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [System Overview](#system-overview)
3. [Core Principles](#core-principles)
4. [Architecture Layers](#architecture-layers)
5. [Jar Architecture](#jar-architecture)
6. [Circle Architecture](#circle-architecture)
7. [Multi-Device E2EE Architecture](#multi-device-e2ee-architecture)
8. [Technology Stack](#technology-stack)
9. [Data Flow](#data-flow)
10. [Security Model](#security-model)
11. [Performance Requirements](#performance-requirements)
12. [Related Documentation](#related-documentation)

---

## Executive Summary

Buds is a **privacy-first memory system** for cannabis experiences, built on the ChaingeOS receipt/bud pattern. It enables users and up to 12 close friends to privately capture, share, and query memories with explicit consent and strong encryption.

### Key Architectural Decisions

1. **Receipt-First Truth**: Every meaningful event is a signed receipt using deterministic CBOR + CIDv1 + Ed25519
2. **Local-First Storage**: GRDB (SQLite) as primary data store with optimistic sync
3. **Thin Relay Server**: Cloudflare Workers + D1 for E2EE message relay (no plaintext storage)
4. **Firebase Auth**: Phone number authentication for identity + device registration
5. **Privacy by Default**: Location OFF by default, share is explicit, E2EE for Circle (max 12)
6. **Agent Integration**: Read-only queries with citations over local receipts

---

## System Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        iOS App (Swift)                       │
├─────────────────────────────────────────────────────────────┤
│  SwiftUI Views   │   ViewModels   │   Coordinators          │
├─────────────────────────────────────────────────────────────┤
│             ChaingeKernel Framework                          │
│  ┌───────────┬──────────────┬─────────────┬─────────────┐  │
│  │ Receipt   │  Identity    │  Crypto     │  Sync       │  │
│  │ Manager   │  Manager     │  Manager    │  Manager    │  │
│  └───────────┴──────────────┴─────────────┴─────────────┘  │
├─────────────────────────────────────────────────────────────┤
│              GRDB (Local SQLite Storage)                     │
│  ┌───────────┬──────────────┬─────────────┬─────────────┐  │
│  │ ucr       │  local       │  circles    │  blobs      │  │
│  │ _headers  │  _receipts   │             │             │  │
│  └───────────┴──────────────┴─────────────┴─────────────┘  │
└─────────────────────────────────────────────────────────────┘
                          ↕ HTTPS + E2EE
┌─────────────────────────────────────────────────────────────┐
│           Cloudflare Workers (Relay Server)                  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  POST /v1/messages (encrypted)                        │  │
│  │  GET  /v1/messages?device_id=<id> (encrypted)         │  │
│  │  POST /v1/devices                                     │  │
│  └───────────────────────────────────────────────────────┘  │
│              Cloudflare D1 (Metadata Only)                   │
└─────────────────────────────────────────────────────────────┘
                          ↕
┌─────────────────────────────────────────────────────────────┐
│                  Firebase Auth (Identity)                    │
│              Phone Number + Device Tokens                    │
└─────────────────────────────────────────────────────────────┘
```

---

## Core Principles

### 1. Receipt-First Architecture (Append-Only + Tombstoning)

Every event creates a **Universal Content Receipt (UCR)**:

- **Immutable Header**: Canonical CBOR + CIDv1 + Ed25519 signature
- **Mutable Metadata**: Local app-specific data (favorites, local notes)
- **Append-Only**: Edits create new receipts with `parentCID` link
- **Content-Addressed**: CID enables deduplication and verification

**CRITICAL: Append-Only Everywhere**

Nothing is ever deleted or mutated. Instead:

| User Action | Implementation |
|-------------|----------------|
| Edit memory | Create new receipt with `parentCID` → old version |
| Delete memory | Create `app.buds.memory.deleted/v1` receipt (tombstone) |
| Unshare memory | Create `app.buds.memory.unshared/v1` receipt (tombstone) |
| Remove friend | Create `app.buds.circle.member.removed/v1` receipt |
| Revoke device | Create `app.buds.device.revoked/v1` receipt |

**All deletions are tombstones**. The UI filters out tombstoned items, but the receipt history is permanently preserved for audit/sync.

**Privacy Note:** Tombstones stop future sharing and hide items in the UI, but **cannot guarantee deletion on other devices** once a receipt has been shared and received. This is an important limitation of E2EE sharing—you cannot remotely delete data from someone else's device.

### 2. Local-First, Sync Second

- **Primary Truth**: Local GRDB database
- **Optimistic Updates**: UI updates immediately, sync happens asynchronously
- **Offline-First**: Full functionality without network
- **Conflict Resolution**: Last-write-wins for metadata, receipt chain for content

### 3. Privacy by Default

- **No Public Feed**: Unlike Streams, Buds has no public visibility
- **Explicit Sharing**: Every share requires user action
- **E2EE Circle**: Messages encrypted with X25519 key agreement
- **Location Protection**: OFF by default, fuzzing optional, delay optional

### 4. Band-First Identity (12-person Circle)

- **Small Groups**: Max 12 friends (Dunbar-adjacent, manageable E2EE)
- **Mutual Trust**: Invite + accept required (no discovery)
- **Revocable**: Can unshare/remove from Circle
- **Portable**: Identity based on DID, not platform

---

## Architecture Layers

### Layer 1: Protocol Layer (UCRHeader)

**Canonical, immutable, signed receipts (causality-first architecture)**

```swift
struct UCRHeader: Codable {
    let cid: String                    // CIDv1 (dag-cbor, sha2-256)
    let did: String                    // did:buds:<base58(Ed25519_pubkey)> - derived from signing key
    let deviceId: String?              // Device identifier
    let parentCID: String?             // Edit chain parent (causal ordering - TRUTH)
    let rootCID: String                // First version (for edits)
    let receiptType: String            // app.buds.session/v1, etc.
    let payload: ReceiptPayload        // Strongly-typed (contains claimed_time_ms)
    let blobs: [BlobReference]         // Media references
    let signature: String              // Ed25519 signature (base64)
    // NO timestamp! Time is in payload as claimed_time_ms (author's claim, not truth)
}
```

**DID vs Firebase Auth:**
- **DID**: Derived from Ed25519 public key (`did:buds:<base58(pubkey)>`). This is the author identifier in receipts.
- **Firebase Auth**: Only used for phone verification and device registration. Firebase UID is NOT used as the author DID in receipts.
- **Identity is portable**: DIDs are based on cryptographic keys, not platform accounts.

**Receipt Types**:
- `app.buds.session.created/v1` - New smoke session
- `app.buds.session.updated/v1` - Edit session (creates new receipt with parentCID)
- `app.buds.memory.shared/v1` - Share to Circle
- `app.buds.memory.unshared/v1` - Revoke share
- `app.buds.memory.deleted/v1` - Tombstone receipt for deleted memory
- `app.buds.memory.reaction.created/v1` - Add reaction to memory (Phase 10.1)
- `app.buds.memory.reaction.removed/v1` - Remove reaction from memory (Phase 10.1)
- `app.buds.circle.invite.created/v1` - Create invite
- `app.buds.circle.invite.accepted/v1` - Accept invite
- `app.buds.circle.member.removed/v1` - Remove from Circle

### Layer 2: App Layer (LocalReceipt + Buds)

**Mutable, app-specific metadata**

```swift
struct LocalReceipt: Identifiable {
    let id: UUID                       // App-local identifier
    let headerCID: String              // FK to UCRHeader
    var isFavorited: Bool              // Local state
    var tags: [String]                 // User tags
    var thumbnailCID: String?          // Local thumbnail blob (not signed)
    var createdAt: Date
    var updatedAt: Date
}
```

**Note:** Full images are stored as signed blobs (referenced in UCRHeader.blobs). LocalReceipt can store a thumbnail CID for UI performance.

```swift
// Projected view (compiled from receipts)
struct MemoryBud {
    let cid: String                    // Latest version CID
    let rootCID: String                // First version
    let ownerDID: String
    var content: MemoryContent         // Current state
    var metadata: MemoryMetadata       // Local metadata
    var shareState: ShareState         // Who can see this
    var editHistory: [String]          // CID chain
}
```

### Layer 3: Circle & Sync Layer

**E2EE sharing with key wrapping**

```swift
struct CircleMember {
    let did: String                    // User DID
    let displayName: String            // Local nickname (NOT in receipts, device-only metadata)
    let publicKey: Data                // X25519 public key
    var joinedAt: Date
    var status: MemberStatus           // active, pending, removed
}
```

**Note:** `displayName` is local-only metadata (stored per-device, not in signed receipts). This avoids PII leakage.

```swift
struct EncryptedMessage {
    let messageCID: String             // CID of plaintext
    let encryptedPayload: Data         // Encrypted receipt payload
    let wrappedKeys: [String: Data]    // deviceId -> wrapped AES key
    let nonce: Data                    // Encryption nonce
    let senderDID: String
    let sentAt: Date                   // Relay metadata (not causal truth - use receipt's parentCID for ordering)
}
```

**Note:** `sentAt` is relay metadata for delivery ordering, not used for causal truth. Receipt ordering uses `parentCID` chains.

### Layer 4: Agent Layer (Optional)

**Read-only queries with citations**

```swift
struct AgentQuery {
    let prompt: String                 // User question
    let context: QueryContext          // Filters, date range, etc.
}

struct AgentResponse {
    let answer: String                 // Natural language answer
    let citations: [Citation]          // Receipt references
    let confidence: Float              // 0-1
}

struct Citation {
    let receiptCID: String             // Source receipt
    let snippet: String                // Relevant excerpt
    let claimedTime: Date              // From receipt's claimed_time_ms
}
```

---

## Jar Architecture (Phase 10)

### Local-First Memory Organization

Buds implements a **jar-based memory organization system** where users can create multiple jars to organize their memories. Each jar can be private (solo) or shared with Circle members.

#### Jar Model

```swift
struct Jar: Identifiable {
    let id: String                         // UUID or "solo" for default jar
    var name: String                       // User-defined name
    var emoji: String                      // Visual identifier
    var createdAt: Date
    var updatedAt: Date
    var memberCount: Int                   // Number of members with access
    var budCount: Int                      // Number of memories in jar
}
```

#### Default "Solo" Jar

- Every user has a default `solo` jar (ID: "solo")
- Private to the user (not shared with Circle)
- Cannot be deleted
- All memories default to solo jar unless explicitly added to a shared jar

#### Shared Jars

- User can create additional jars to share with Circle members
- Max 12 members per jar (same as Circle limit)
- Members are added via jar invites (similar to Circle invites)
- Memories in shared jars are visible to all members
- Reactions to memories in shared jars are E2EE across all jar members

#### Move Between Jars

- Memories can be moved from one jar to another
- Moving creates an `app.buds.memory.moved/v1` receipt
- UI shows "Move to Jar" option in memory detail view
- Solo jar ↔ Shared jar moves respect privacy (user confirmation required)

## Circle Architecture

### Privacy-First Friend Groups (Max 12 Members)

Buds implements a **local-first Circle roster** where your friend list never leaves your device. Only encrypted messages are sent through the relay server, creating a zero-knowledge architecture for social graphs.

#### Circle Member Model

```swift
struct CircleMember: Identifiable {
    let id: UUID                           // Local UUID
    let did: String                        // Member DID (did:buds:<base58(pubkey)>)
    var displayName: String                // Local nickname (privacy-preserving)
    var phoneNumber: String?               // Optional, for display only
    var avatarCID: String?                 // Profile photo blob CID
    let pubkeyX25519: String               // X25519 public key for E2EE
    var status: CircleStatus               // pending | active | removed
    var joinedAt: Date?
    var invitedAt: Date?
    var removedAt: Date?
}

enum CircleStatus: String {
    case pending  // Invited, not yet accepted (placeholder DID)
    case active   // DID lookup succeeded, can share
    case removed  // Removed from Circle
}
```

#### Privacy Model

**Local-Only Roster**:
- Friend list stored only in local GRDB (`circles` table)
- Relay server NEVER sees your social graph
- Display names are local nicknames (not global usernames)

**Phone Number Handling**:
- User enters phone number to add friend
- Client hashes phone with SHA-256 before sending to relay
- Relay looks up DID from hashed phone (one-way mapping)
- Phone number stored locally for display only
- **Never sent to relay in plaintext**
- **Never stored in receipts**

**DID Lookup Flow** (Phase 6):
```
User adds friend by phone: "+14155551234"
  ↓
1. Hash phone: SHA-256("+14155551234") = "a7b3c..."
2. POST /api/lookup/did { phoneHash: "a7b3c..." }
3. Relay queries: SELECT did FROM phone_to_did WHERE phone_hash = "a7b3c..."
4. Returns: { did: "did:buds:abc123..." }
5. Client stores CircleMember with real DID, status = active
```

**No Global Username Namespace**:
- Display names are local-only (you choose what to call each friend)
- No public profile pages
- No friend discovery/search
- Invite-only (requires phone number)

#### 12-Member Limit Rationale

**Privacy**: Small, trusted group (intimate friend circle, not social network)
**Key Distribution**: Manageable E2EE key wrapping for each device
**UX**: Dunbar-adjacent number (meaningful relationships)
**Performance**: No O(n²) scaling issues (12² = 144 device pairs max)

---

## Multi-Device E2EE Architecture

### Device-Based Key Distribution

Buds supports **multiple devices per user** (e.g., Alice has iPhone + iPad). Each device gets its own keypair and must be able to decrypt shared memories independently.

#### Device Model

```swift
struct Device {
    let deviceId: UUID                     // Unique device identifier
    let ownerDID: String                   // DID of device owner
    var deviceName: String                 // "Alice's iPhone", "Alice's iPad"
    let pubkeyX25519: String               // Device-specific X25519 pubkey
    let pubkeyEd25519: String              // Device-specific Ed25519 pubkey
    var status: DeviceStatus               // active | revoked
    var registeredAt: Date
    var lastSeenAt: Date?
}
```

#### Device Registration Flow (Phase 6)

```
App First Launch:
  ↓
1. Generate device_id (UUID)
2. Generate X25519 keypair (for E2EE)
3. Generate Ed25519 keypair (for signing)
4. Store in Keychain (kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
5. POST /api/devices/register {
     deviceId: "uuid",
     deviceName: "Alice's iPhone",
     pubkeyX25519: "base64...",
     pubkeyEd25519: "base64...",
     ownerDID: "did:buds:abc123"
   }
6. Relay stores device in devices table
```

#### Multi-Device Key Wrapping

When Alice (2 devices) shares a memory with Bob (2 devices):

```
1. Alice's iPhone generates ephemeral AES-256 key (K_msg)
2. Encrypts memory: C = AES-GCM(K_msg, memory_payload)
3. Query relay for all devices:
   - Alice: [iPhone, iPad]
   - Bob: [iPhone, iPad]
   Total: 4 devices

4. For each device, wrap K_msg:
   - K_wrap_alice_iphone = X25519_wrap(alice_iphone_pubkey, K_msg)
   - K_wrap_alice_ipad = X25519_wrap(alice_ipad_pubkey, K_msg)
   - K_wrap_bob_iphone = X25519_wrap(bob_iphone_pubkey, K_msg)
   - K_wrap_bob_ipad = X25519_wrap(bob_ipad_pubkey, K_msg)

5. POST /api/messages/send {
     encryptedPayload: "base64(C)",
     nonce: "base64...",
     wrappedKeys: {
       "alice-iphone-uuid": "base64(K_wrap_alice_iphone)",
       "alice-ipad-uuid": "base64(K_wrap_alice_ipad)",
       "bob-iphone-uuid": "base64(K_wrap_bob_iphone)",
       "bob-ipad-uuid": "base64(K_wrap_bob_ipad)"
     }
   }

6. Each device polls inbox, finds wrapped key for its device_id, unwraps, decrypts
```

#### Device Revocation

**Problem**: Alice loses her iPad, needs to revoke it without affecting her iPhone.

**Solution**:
```
1. Alice uses iPhone to POST /api/devices/revoke { deviceId: "ipad-uuid" }
2. Relay marks device status = "revoked"
3. Future shares skip revoked devices (no wrapped key generated)
4. Alice's iPad can no longer decrypt new messages
5. Alice's iPhone continues working normally
```

**Note**: Revocation does NOT delete old messages already received on the iPad. This is a fundamental limitation of E2EE—you cannot remotely delete data from someone else's device.

#### Key Rotation Strategy

**Current (Phase 6)**: No automatic key rotation
**Future (Phase 7+)**: Periodic device re-registration with new keypairs

**Rotation Flow**:
1. Generate new X25519 keypair
2. POST /api/devices/rotate-key { deviceId, newPubkey }
3. Relay updates device record
4. Old wrapped keys remain valid (backward compatibility)
5. New shares use new pubkey

---

## Technology Stack

### iOS App

| Component | Technology | Why |
|-----------|-----------|-----|
| UI Framework | SwiftUI | Modern, declarative, native performance |
| Language | Swift 6 | Latest features, concurrency, safety |
| Database | GRDB | Production-ready SQLite wrapper, migrations |
| Crypto | CryptoKit | Apple's native crypto (Ed25519, X25519, AES-GCM) |
| Auth | Firebase Auth | Phone verification, device management |
| Maps | MapKit | Native maps, privacy-preserving |
| Networking | URLSession | Native HTTP client |

### Backend (Relay Server)

| Component | Technology | Why |
|-----------|-----------|-----|
| Runtime | Cloudflare Workers | Edge compute, low latency, free tier |
| Database | Cloudflare D1 | SQLite at the edge, metadata only |
| Storage | R2 (future) | Encrypted blob storage if needed |
| CDN | Cloudflare | Global distribution |

### Development Tools

| Tool | Purpose |
|------|---------|
| Xcode 15+ | iOS development |
| Wrangler | Cloudflare Workers CLI |
| GRDB Studio | SQLite inspection |
| Postman | API testing |

---

## Data Flow

### Flow 1: Create Memory (Local Only)

```
User → CaptureView → ReceiptManager.create()
  ↓
1. Build UCRHeader payload
2. Sign with IdentityManager (Ed25519)
3. Compute CID (CBOR → SHA256 → CIDv1)
4. Save to GRDB (ucr_headers + local_receipts)
5. Update UI optimistically
```

### Flow 2: Share Memory to Circle

```
User → MemoryDetailView → ShareToCircleButton
  ↓
1. Load Circle members from DB
2. Generate ephemeral AES-256 key
3. Encrypt memory payload with AES-GCM
4. Wrap AES key for each member (X25519 key agreement)
5. Create EncryptedMessage with wrappedKeys
6. Post to relay server (/v1/messages)
7. Relay stores encrypted message in D1
8. Push notification to recipients
```

### Flow 3: Receive Shared Memory

```
Push Notification → App Wake → SyncManager.fetchMessages()
  ↓
1. GET /v1/messages?device_id=<id> (returns encrypted blobs)
2. For each message:
   a. Unwrap AES key using device private key (X25519)
   b. Decrypt payload with AES-GCM
   c. Verify signature on UCRHeader
   d. Save to GRDB as shared receipt
3. Update UI (new memory appears in Circle view)
```

### Flow 4: Agent Query

```
User → "Ask Buds" → Input prompt
  ↓
1. Parse query intent (strain search, location, effects, etc.)
2. Query GRDB for relevant receipts
3. Build context window with receipts
4. Call LLM provider API with prompt + context (see AGENT_INTEGRATION.md)
5. Parse response + extract citations
6. Render answer with clickable receipt links
```

---

## Security Model

### Threat Model

**In Scope:**
- Relay server compromise (should see only encrypted data)
- Device theft (protected by iOS encryption + biometrics)
- Network interception (HTTPS + E2EE)
- Malicious Circle member (can screenshot, but can't impersonate)

**Out of Scope (v0.1):**
- Nation-state adversaries (no forward secrecy, no Signal-level guarantees)
- Supply chain attacks
- Social engineering for physical device access

### Cryptographic Primitives

| Use Case | Algorithm | Key Size |
|----------|-----------|----------|
| Identity keypair | Ed25519 | 256-bit |
| Signing receipts | Ed25519 | 256-bit |
| Key agreement (Circle) | X25519 | 256-bit |
| Symmetric encryption | AES-GCM | 256-bit |
| Content addressing | SHA2-256 | 256-bit |

### Key Management

1. **Device Keypair** (Ed25519):
   - Generated on first launch
   - Stored in iOS Keychain (kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
   - Used for signing receipts
   - Public key → DID

2. **Encryption Keypair** (X25519):
   - Generated on first launch
   - Stored in iOS Keychain
   - Used for E2EE key wrapping
   - Public key shared with Circle members

3. **Ephemeral Keys** (AES-256):
   - Generated per-message
   - Wrapped for each recipient
   - Deleted after encryption

### Encryption Scheme (Circle Messages)

```
1. Sender generates random K_msg (AES-256)
2. Encrypts payload: C = AES-GCM(K_msg, payload, AAD=header)
3. For each recipient device i:
   - Compute shared secret: S_i = X25519(sender_private, recipient_device_i_public)
   - Derive wrapping key: K_wrap_i = HKDF(S_i, "buds.wrap.v1")
   - Wrap: W_i = AES-GCM(K_wrap_i, K_msg)
4. Post {C, nonce, {deviceId_i: W_i}, header} to relay

Recipient:
1. Fetch encrypted message
2. Extract W_self using own deviceId
3. Compute shared secret: S = X25519(self_device_private, sender_device_public)
4. Derive: K_wrap = HKDF(S, "buds.wrap.v1")
5. Unwrap: K_msg = AES-GCM-decrypt(K_wrap, W_self)
6. Decrypt: payload = AES-GCM-decrypt(K_msg, C)
```

**Note:** Keys are wrapped per-device (not per-DID) to support multi-device scenarios.

---

## Performance Requirements

### App Launch (SLOs)

- **Cold Start**: < 3s to timeline visible
- **Warm Start**: < 1.5s to timeline visible
- **Memory Save**: < 150ms local write (excluding photo processing)
- **Map Load**: < 1s after permissions granted
- **Search Query**: < 300ms for full-text search

### Sync Performance

- **Message Fetch**: < 500ms to download encrypted messages
- **Decrypt Message**: < 100ms per message (includes key unwrap + AES decrypt)
- **Push to Receive**: < 2s from send to recipient notification

### Database Constraints

- **Local Storage**: < 100MB for 1,000 memories (excluding photos)
- **Photo Storage**: Compressed to < 2MB per photo
- **Query Performance**: All queries < 100ms (with proper indexes)

### Network Usage

- **Typical Session**: < 500KB (metadata only, no photos)
- **Photo Upload**: < 5MB per photo (compressed)
- **Background Sync**: < 100KB per check

---

## Related Documentation

- [RECEIPT_SCHEMAS.md](./RECEIPT_SCHEMAS.md) - Receipt types and payload formats
- [DATABASE_SCHEMA.md](./DATABASE_SCHEMA.md) - GRDB schema design
- [E2EE_DESIGN.md](./E2EE_DESIGN.md) - End-to-end encryption details
- [RELAY_SERVER.md](./RELAY_SERVER.md) - Cloudflare Workers API
- [PRIVACY_ARCHITECTURE.md](./PRIVACY_ARCHITECTURE.md) - Location privacy & data protection
- [AGENT_INTEGRATION.md](./AGENT_INTEGRATION.md) - Agent query architecture
- [DISPENSARY_INSIGHTS.md](./DISPENSARY_INSIGHTS.md) - Aggregate insights for B2B
- [UX_FLOWS.md](./UX_FLOWS.md) - User experience flows
- [DEVELOPMENT_ROADMAP.md](./DEVELOPMENT_ROADMAP.md) - Phased development plan

---

## Design Decisions Log

### Why GRDB over SwiftData?

- **Maturity**: Production-proven, stable API
- **Control**: Direct SQL access for complex queries
- **Migrations**: Explicit migration system
- **Performance**: Optimized for our receipt pattern
- **Compatibility**: Works with iOS 14+ (wider reach)

### Why Cloudflare Workers over Firebase Functions?

- **Edge Compute**: Lower latency (runs at CDN edge)
- **Cost**: Free tier handles v0.1 scale (100K req/day)
- **Simplicity**: Stateless handlers, D1 for persistence
- **Privacy**: No vendor lock-in, easy to self-host later

### Why X25519 key agreement over RSA?

- **Performance**: Faster key agreement (< 1ms vs 10ms+)
- **Size**: Smaller keys (32 bytes vs 256+ bytes)
- **Security**: Modern, audited, CryptoKit native
- **Forward Secrecy**: Can add ephemeral keys later

### Why Max 12 Circle Members?

- **UX**: Manageable group size (Dunbar-adjacent)
- **Crypto**: Simple key wrapping (12 keys < 1KB overhead)
- **Privacy**: Easier to trust small group
- **Performance**: No O(n²) scaling issues

---

**Next Steps**: Review this architecture, then proceed to detailed design docs.
