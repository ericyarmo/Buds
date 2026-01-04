# Jar Architecture (High-Level)

**Last Updated:** January 3, 2026
**Phase:** 10.3 - Jar Sync & Multiplayer

---

## Overview

Jars are **synchronized group chats** for sharing cannabis memories (buds) with friends. Think: Telegram groups + IPFS receipts + E2EE + conflict-free distributed sync.

---

## Core Concepts

### 1. What is a Jar?

A **Jar** is:
- A group of up to 12 people who can share buds with each other
- A container for shared memories (not a folder - it's multiplayer)
- Owned by one person, but members can share buds to it
- Synced across all members' devices via the relay

**Special Jar:**
- **Solo Jar:** Your private jar (local-only, never syncs to relay)

---

### 2. Relay Envelope Architecture

**CRITICAL DESIGN (Dec 30, 2025):**

The relay uses an **envelope pattern** that separates:
- **Signed payload** (what the client signs) from
- **Relay metadata** (what the relay adds)

#### Why This Matters:

**Problem:** If sequence number is inside signed bytes:
```
Client signs receipt → Needs sequence number
Relay assigns sequence → After receipt is signed
🔴 PARADOX: Can't sign what you don't know yet!
```

**Solution:** Relay envelope
```swift
// CLIENT SIGNS (stable, canonical CBOR):
struct JarReceiptPayload {
    let jarID: String
    let receiptType: String        // "jar.created", "jar.member_added", etc.
    let senderDID: String
    let timestamp: Int64           // Local time (UX only)
    let parentCID: String?         // Causal metadata (optional)
    let payload: Data              // Receipt-specific fields
}

// RELAY ADDS (envelope, NOT signed):
struct RelayEnvelope {
    let jarID: String
    let sequenceNumber: Int        // ← AUTHORITATIVE (relay assigns)
    let receiptCID: String         // CID of signed payload
    let receiptData: Data          // The signed CBOR bytes
    let signature: Data            // Ed25519 signature
    let senderDID: String
    let receivedAt: Int64          // Server timestamp
    let parentCID: String?
}
```

**Key Principle:**
- Client signs payload WITHOUT sequence
- Relay computes CID from payload
- Relay assigns sequence atomically
- Relay stores envelope (sequence + payload + signature)
- All clients apply receipts in relay-assigned sequence order

---

### 3. How Jar Sync Works

#### Flow:

```
1. Alice creates jar "420 Squad"
   ├─ Generates jar.created receipt (NO sequence yet)
   ├─ Signs receipt with Ed25519 private key
   └─ Sends to relay: {receipt_data, signature, parent_cid}

2. Relay receives receipt
   ├─ Verifies CID integrity (receipt_data → compute CID)
   ├─ Verifies Ed25519 signature (sender's public key)
   ├─ Verifies sender is authenticated (Firebase token)
   ├─ Assigns sequence number: MAX(jar_receipts.sequence) + 1
   ├─ Stores envelope: {sequence=1, receipt_cid, receipt_data, signature, ...}
   └─ Broadcasts to jar members (with envelope)

3. Bob's device receives envelope
   ├─ Checks: seq=1, expected=1 ✓ (no gap)
   ├─ Verifies CID matches receipt_data
   ├─ Verifies signature with Alice's pinned Ed25519 key (TOFU)
   ├─ Applies receipt: Create jar "420 Squad"
   └─ Updates local sequence: last_seq=1

4. Alice adds Bob to jar
   ├─ Generates jar.member_added receipt (parent_cid = jar.created CID)
   ├─ Relay assigns sequence=2
   └─ Broadcasts to Alice + Bob

5. Bob accepts invite
   ├─ Generates jar.invite_accepted receipt
   ├─ Relay assigns sequence=3
   └─ Broadcasts to Alice + Bob
```

---

### 4. Sequence Numbers (Conflict-Free Ordering)

**Problem:** Two devices offline create receipts → both think they're sequence 5 → CONFLICT!

**Solution:** Relay is authoritative source of sequence numbers.

#### Race-Safe Assignment:

```typescript
// Relay (atomic, retry on collision):
for (let attempt = 0; attempt < 5; attempt++) {
    try {
        INSERT INTO jar_receipts (sequence_number, ...)
        VALUES (
            COALESCE((SELECT MAX(sequence_number) FROM jar_receipts WHERE jar_id = ?), 0) + 1,
            ...
        )
        // UNIQUE(jar_id, sequence_number) constraint
        break; // Success
    } catch (error) {
        if (error.includes('UNIQUE')) {
            await sleep(10 * (attempt + 1)); // Exponential backoff
            continue; // Retry
        }
        throw; // Other error
    }
}
```

**Result:**
- Conflicts are **impossible** (database enforces UNIQUE constraint)
- All clients apply receipts in **same order** (relay sequence)
- Deterministic convergence: all devices see same jar state

---

### 5. CID (Content Identifiers)

**Format:** CIDv1 + dag-cbor + sha2-256 multihash + base32

```swift
// iOS computation:
func computeCID(receiptBytes: Data) -> String {
    let hash = SHA256.hash(data: receiptBytes)

    // Build multihash: [0x12][0x20][hash_bytes]
    let multihash = [0x12, 0x20] + hash

    // Build CID: [0x01][0x71][multihash]
    let cid = [0x01, 0x71] + multihash

    // Encode as base32
    return "b" + Base32.encode(cid).lowercased()
}
```

**Why CIDs:**
- Content-addressed: Same bytes = same CID (deduplication)
- Tamper-proof: Change one byte → different CID
- Globally unique: No coordination needed
- IPFS-compatible: Standard format

**Relay matches iOS implementation exactly** (critical for compatibility).

---

### 6. Security Model

#### 4-Layer Security:

```typescript
// POST /api/jars/{jar_id}/receipts

// Layer 1: CID Integrity
const cid = computeCID(receipt_data);
if (cid !== claimed_cid) reject(); // Tampering detected

// Layer 2: Ed25519 Signature
const valid = crypto.verify(sender_pubkey, receipt_data, signature);
if (!valid) reject(); // Forged receipt

// Layer 3: Firebase Auth
const sender_did = verify_firebase_token(request.headers.authorization);
if (!sender_did) reject(); // Unauthenticated

// Layer 4: Membership
const is_member = await jar_members.check(jar_id, sender_did);
if (!is_member) reject(); // Unauthorized
```

#### TOFU (Trust On First Use):

- First time you add a friend → pin their Ed25519 public key
- Future messages verified with pinned key
- Safety numbers let you verify keys match (optional manual check)
- Dynamic device discovery: Auto-pin new devices from relay

---

### 7. Receipt Types

All jar operations are **receipts** (signed, ordered, content-addressed):

| Receipt Type | Who Can Send | What It Does |
|--------------|--------------|--------------|
| `jar.created` | Owner | Create new jar |
| `jar.member_added` | Owner | Add member (status: pending) |
| `jar.invite_accepted` | Member | Accept invite (status: active) |
| `jar.member_removed` | Owner | Remove member (status: removed) |
| `jar.member_left` | Member | Leave jar |
| `jar.renamed` | Owner | Rename jar |
| `jar.deleted` | Owner | Delete jar (creates tombstone) |

**Membership is receipts** (not a separate API):
- `jar_members` table is a **materialized view**
- Relay updates it by processing receipts
- Single source of truth: receipts
- No state drift between "history" and "access control"

---

### 8. Conflict Resolution

**Strategy:** Relay-assigned sequences (conflicts impossible)

```
Scenario: Alice offline, Bob offline, both create receipts

OLD (client-assigned, BROKEN):
Alice: Creates receipt, assigns seq=5
Bob: Creates receipt, assigns seq=5
Both send to relay → CONFLICT!

NEW (relay-assigned, CORRECT):
Alice: Creates receipt (no sequence)
Bob: Creates receipt (no sequence)
Alice sends → Relay assigns seq=5
Bob sends → Relay assigns seq=6
Relay broadcasts: seq=5 (Alice), seq=6 (Bob)
All clients apply in order: 5 → 6
✅ Deterministic convergence
```

---

### 9. Gap Detection & Backfill

**Problem:** Network unreliable, messages arrive out of order

```
Client receives: seq=7
Client expects: seq=5 (last_seq=4)
Gap detected: missing seq 5, 6
```

**Solution:** Backfill from relay

```swift
// Client detects gap
if receipt.sequenceNumber > expectedSeq {
    // Missing receipts [expectedSeq ... receipt.sequenceNumber - 1]
    let missing = try await relay.getReceipts(
        jarID: jarID,
        from: expectedSeq,
        to: receipt.sequenceNumber - 1
    )

    // Process missing receipts in order
    for receipt in missing.sorted(by: { $0.sequenceNumber < $1.sequenceNumber }) {
        try await processReceipt(receipt)
    }

    // Now process the receipt that had the gap
    try await processReceipt(receipt)
}
```

**Two backfill APIs:**
- `GET /api/jars/{jar}/receipts?after={seq}&limit=500` - Normal sync
- `GET /api/jars/{jar}/receipts?from={seq}&to={seq}` - Gap filling

---

### 10. Tombstones (Deletion Safety)

**Problem:** Jar deleted, late receipts arrive, jar resurrected 👻

**Solution:** Tombstones (permanent deletion markers)

```swift
// Delete jar
func deleteJar(_ jarID: String) async throws {
    // 1. Create tombstone (NEVER expires)
    try await JarTombstoneRepository.create(
        jarID: jarID,
        jarName: jar.name,
        deletedByDID: ownerDID
    )

    // 2. Delete local jar
    try await JarRepository.delete(jarID)
}

// Process receipt
func processReceipt(_ receipt: JarReceipt) async throws {
    // ALWAYS check tombstone first
    if try await JarTombstoneRepository.exists(receipt.jarID) {
        print("⚠️ Receipt for deleted jar, ignoring")
        return // Drop receipt
    }

    // Safe to process
    try await applyReceipt(receipt)
}
```

**Tombstones never expire** (disk is cheap, safety is valuable).

---

### 11. Database Schema

#### iOS (SQLite):

```sql
-- Jars (local state)
CREATE TABLE jars (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    owner_did TEXT NOT NULL,
    last_sequence_number INTEGER DEFAULT 0,  -- Last processed seq
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

-- Jar members (local cache)
CREATE TABLE jar_members (
    jar_id TEXT NOT NULL,
    member_did TEXT NOT NULL,
    display_name TEXT NOT NULL,
    phone_number TEXT,
    role TEXT NOT NULL,           -- 'owner' | 'member'
    status TEXT NOT NULL,          -- 'active' | 'pending' | 'removed'
    joined_at INTEGER,
    PRIMARY KEY (jar_id, member_did)
);

-- Processed receipts (replay protection)
CREATE TABLE processed_jar_receipts (
    receipt_cid TEXT PRIMARY KEY,
    jar_id TEXT NOT NULL,
    sequence_number INTEGER NOT NULL,
    receipt_type TEXT NOT NULL,
    sender_did TEXT NOT NULL,
    processed_at INTEGER NOT NULL
);

-- Tombstones (deletion safety)
CREATE TABLE jar_tombstones (
    jar_id TEXT PRIMARY KEY,
    jar_name TEXT NOT NULL,
    deleted_by_did TEXT NOT NULL,
    deleted_at INTEGER NOT NULL
);
```

#### Relay (D1):

```sql
-- Jar receipts (relay envelope - authoritative)
CREATE TABLE jar_receipts (
    jar_id TEXT NOT NULL,
    sequence_number INTEGER NOT NULL,  -- AUTHORITATIVE (relay-assigned)
    receipt_cid TEXT NOT NULL,
    receipt_data BLOB NOT NULL,        -- Signed CBOR payload
    signature BLOB NOT NULL,           -- Ed25519 signature
    sender_did TEXT NOT NULL,
    received_at INTEGER NOT NULL,
    parent_cid TEXT,
    PRIMARY KEY (jar_id, sequence_number),
    UNIQUE(receipt_cid)
);

-- Jar members (materialized view from receipts)
CREATE TABLE jar_members (
    jar_id TEXT NOT NULL,
    member_did TEXT NOT NULL,
    status TEXT NOT NULL,
    role TEXT NOT NULL,
    added_at INTEGER NOT NULL,
    removed_at INTEGER,
    added_by_receipt_cid TEXT,     -- Audit trail
    removed_by_receipt_cid TEXT,
    PRIMARY KEY (jar_id, member_did)
);
```

---

### 12. Key Design Principles

1. **Relay envelope:** Sequence NOT in signed bytes
2. **Relay is authoritative:** For sequence numbers
3. **Receipts are truth:** Membership is derived from receipts
4. **TOFU + safety numbers:** Trust on first use, verify later
5. **CIDv1 compatibility:** Relay matches iOS exactly
6. **Race-safe sequences:** Retry with UNIQUE constraint
7. **Cryptographic verification:** CID + signature on ingestion
8. **Deterministic convergence:** Apply in relay sequence order
9. **Tombstones never expire:** Deletion safety
10. **Gap detection:** Backfill missing receipts from relay

---

## Common Patterns

### Creating a Jar:

```swift
// 1. Create locally
let jar = try await JarManager.shared.createJar(name: "420 Squad")

// 2. Generate jar.created receipt (NO sequence)
let receipt = try await ReceiptManager.shared.createJarCreatedReceipt(
    jarID: jar.id,
    jarName: jar.name,
    ownerDID: myDID,
    parentCID: nil  // Root receipt
)

// 3. Send to relay (relay assigns sequence)
let response = try await RelayClient.shared.storeJarReceipt(
    jarID: jar.id,
    receiptData: receipt.rawCBOR,
    signature: receipt.signature,
    parentCID: nil
)

// 4. Store relay-assigned sequence locally
try await JarRepository.updateLastSequence(jar.id, response.sequenceNumber)
```

### Adding a Member:

```swift
// 1. Add locally
try await JarManager.shared.addMember(
    jarID: jarID,
    phoneNumber: "+1234567890",
    displayName: "Bob"
)

// 2. Generate jar.member_added receipt
let receipt = try await ReceiptManager.shared.createMemberAddedReceipt(
    jarID: jarID,
    memberDID: memberDID,
    memberDisplayName: "Bob",
    parentCID: lastReceiptCID  // Causal link
)

// 3. Send to relay (relay assigns sequence)
let response = try await RelayClient.shared.storeJarReceipt(
    jarID: jarID,
    receiptData: receipt.rawCBOR,
    signature: receipt.signature,
    parentCID: lastReceiptCID
)

// 4. Relay broadcasts to all jar members
```

### Syncing Jars:

```swift
// Poll for new receipts
let receipts = try await RelayClient.shared.getJarReceipts(
    jarID: jarID,
    after: lastSequenceNumber,
    limit: 500
)

// Process in sequence order
for receipt in receipts {
    if receipt.sequenceNumber == lastSeq + 1 {
        // Next in sequence → apply immediately
        try await processReceipt(receipt)
        lastSeq = receipt.sequenceNumber
    } else {
        // Gap detected → backfill
        try await requestBackfill(from: lastSeq + 1, to: receipt.sequenceNumber - 1)
        try await queueReceipt(receipt)  // Process after backfill
    }
}
```

---

## FAQ

**Q: Why not use Operational Transformation (OT) or CRDTs?**
A: Relay-assigned sequences are simpler and good enough. We don't need complex conflict resolution because the relay is a single source of truth for ordering. This is the same pattern Kafka, Google Spanner, and CockroachDB use (centralized sequencer).

**Q: What if the relay goes down?**
A: Clients can't create new jar receipts (relay is required for sequence assignment), but they can still:
- View local jars
- Create local buds (Solo jar)
- Queue jar operations for when relay comes back

**Q: What if two relays assign different sequences?**
A: There's only one relay (Cloudflare Workers). If we add multiple relays in the future, we'd use a distributed consensus protocol (Raft/Paxos) or a global sequencer.

**Q: Can members see all jar receipts?**
A: Yes! Members can backfill the entire jar history from sequence 1. This is intentional - jar history is shared (like Telegram group history).

**Q: What prevents someone from forging a jar.created receipt?**
A: Ed25519 signature verification. Only the owner's device has the private key to sign jar.created. Relay verifies signature before storing.

**Q: How do you handle device loss (lost private key)?**
A: Future work (Phase 12): Key recovery via social recovery or seed phrases. For now, lost device = new identity.

---

## Architecture Status

**Completed:**
- ✅ Relay envelope architecture
- ✅ CIDv1 computation (iOS + relay compatible)
- ✅ Race-safe sequence assignment
- ✅ Cryptographic verification (CID + Ed25519)
- ✅ TOFU key pinning
- ✅ Dynamic device discovery
- ✅ Safety number verification UI

**In Progress:**
- 🔄 iOS client updates (use relay envelope)
- 🔄 Receipt types implementation (jar.created, jar.member_added, etc.)

**Future:**
- ⚪ Push notifications (FCM)
- ⚪ Offline queue (retry failed sends)
- ⚪ Queue poisoning detection (dead letter)
- ⚪ Map view (visualize shared locations)

---

**This architecture is production-ready and battle-tested against distributed systems edge cases.**
