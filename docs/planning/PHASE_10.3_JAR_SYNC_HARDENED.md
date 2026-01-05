# Phase 10.3: Jar Sync & Multiplayer (Hardened)

**Status:** 📋 Ready for Implementation
**Priority:** 🔴 CRITICAL - Blocks real multiplayer
**Estimated Time:** 50-70 hours (added crypto hardening + distributed systems)
**Date:** December 30, 2025

**Audits:**
- See `PHASE_10.3_EDGE_CASE_AUDIT.md` for distributed systems edge cases
- See `PHASE_10.3_CRYPTO_ADDENDUM.md` for crypto blind spots & fixes

---

## Executive Summary

Convert jars from local organizing buckets to synchronized group chats with proper distributed systems hardening AND crypto fixes.

**Distributed Systems Hardening:**
- ✅ Relay-assigned sequence numbers (conflict-free ordering)
- ✅ Causal ordering with `parent_cid` chains (optional metadata)
- ✅ Tombstones for deletion safety
- ✅ Replay protection with processed receipt tracking
- ✅ Server-side membership validation
- ✅ Offline conflict prevention (relay is source of truth)

**Crypto Hardening (NEW):**
- ✅ Phone-based identity (fixes multi-device DID problem)
- ✅ Deterministic phone encryption (prevents rainbow tables)
- ✅ Dynamic device discovery (handles new devices after TOFU)
- ✅ CBOR library pinning + golden tests (prevents signature breaks)
- ✅ Safety number verification UI (optional TOFU verification)
- ⚪ Forward secrecy limitation documented (defer to Phase 12)
- ⚪ Metadata leakage accepted and documented

**Philosophy:** Coherent and defensible, not perfect. Handle critical edge cases, document limitations honestly.

---

## Core Architecture Changes

### 1. Receipt Structure - Relay Envelope Architecture

**CRITICAL ARCHITECTURE CHANGE (Dec 30, 2025):**

**Problem:** If sequence_number is inside signed receipt bytes:
- Client signs receipt before sending to relay
- Relay assigns sequence after receiving
- Signed bytes would need sequence → **paradox** (can't sign what you don't know)

**Solution:** Separate signed payload from relay envelope

**Receipt Payload (Client-Signed, Canonical CBOR):**
```swift
// What the CLIENT signs (stable, canonical)
struct JarReceiptPayload: Codable {
    let jarID: String              // Which jar
    let receiptType: String        // "jar.created", "jar.member_added", etc.
    let senderDID: String          // Who created this receipt
    let timestamp: Int64           // Local time (UX only, not for ordering)
    let parentCID: String?         // Previous operation CID (optional causal metadata)

    // Payload-specific fields
    let payload: Data              // Receipt-specific CBOR (member info, jar name, etc.)
}

// Client computes: CID(CBOR(payload)) → receipt_cid
// Client signs: Ed25519(receipt_cid) → signature
```

**Relay Envelope (Relay Metadata, NOT Signed by Client):**
```swift
// What the RELAY adds (not part of signed bytes)
struct RelayEnvelope {
    let jarID: String              // Which jar (duplicated for indexing)
    let sequenceNumber: Int        // AUTHORITATIVE (relay-assigned, UNIQUE)
    let receiptCID: String         // CID of signed payload
    let receiptData: Data          // The signed payload bytes (canonical CBOR)
    let signature: Data            // Client's Ed25519 signature over receiptData
    let senderDID: String          // Duplicated for indexing
    let receivedAt: Int64          // When relay received it (server timestamp)
}
```

**Key Principles:**
- `sequenceNumber` lives in relay envelope (NOT in signed bytes)
- Client NEVER sees or predicts sequence (no clientSequenceHint)
- Relay assigns sequence atomically: `MAX(sequence_number) + 1`
- `UNIQUE(jar_id, sequence_number)` prevents conflicts
- All clients apply receipts in relay-assigned order (deterministic)
- Sequence is the ONLY apply order (parent_cid is optional metadata)

**Why:**
- `sequenceNumber`: Detect missing receipts (gap from 5 → 7 means 6 is missing)
- `parentCID`: Causal chain (can't process receipt N+1 until receipt N arrives)

---

## Production-Grade Upgrades (Dec 30, 2025)

### Upgrade A: Relay Envelope (CRITICAL)
**Problem:** Can't include relay-assigned sequence in client-signed bytes.
**Solution:** Separate receipt payload (signed) from relay envelope (metadata).
- Receipt payload: jar_id, receipt_type, sender_did, timestamp, parent_cid, payload
- Relay envelope: sequence_number, receipt_cid, receipt_data, signature, received_at
- NO sequence_number inside signed bytes

### Upgrade B: `/receipts?after=` API (Ergonomics)
**Problem:** Most clients want "everything after my last seq", not from/to range.
**Solution:** Add both APIs:
- `GET /api/jars/{jar}/receipts?after={lastSeq}&limit=500` - Workhorse (normal sync)
- `GET /api/jars/{jar}/receipts?from={seq}&to={seq}` - Gap filling (specific range)

### Upgrade C: Backfill Lock (Prevent Storms)
**Problem:** Multiple messages with gaps → multiple backfill requests for same range.
**Solution:** Add per-jar backfill guard:
- `backfill_in_progress_until` timestamp (local client state)
- Prevents requesting same range 15 times in parallel
- Example: If backfilling seq 5-10, don't request again until complete or timeout

### Upgrade D: Queue Poisoning Detection (Dead Letter)
**Problem:** Queued receipts that can never be applied (missing parent forever).
**Solution:** Add poison detection fields to `jar_receipt_queue`:
- `retry_count` - How many times we tried to process
- `last_attempt_at` - When we last tried
- `dead_letter_reason` - Why we gave up
**Policy:** If retry_count > N or age > T, drop receipt + show toast/log.

### Upgrade E: Membership Changes as Receipts (Single Source of Truth)
**Problem:** Two sources of truth:
- `jar.member_added` receipts (user-visible history)
- `/api/jars/{jar}/sync` endpoint (relay access control state)
**Risk:** Drift between "history says X, access control says Y"

**Solution:** Receipts are truth, relay state is materialized view.
- Membership changes ARE receipts (`jar.member_added`, `jar.member_removed`)
- Relay `jar_members` table is updated by PROCESSING receipts
- `/sync` endpoint becomes admin repair tool only (not primary API)
- Prevents state drift: access control matches visible history

**Implementation:**
1. Client sends `jar.member_added` receipt → relay assigns sequence
2. Relay processes receipt internally → updates `jar_members` table
3. Relay broadcasts receipt to jar members
4. All clients see same membership history + access control matches
- Timestamp: For UI display only ("2 hours ago"), not for ordering

### 2. Database Schema (Migration v8)

**New tables for hardening:**

```sql
-- Track processed receipts (prevent replay attacks)
CREATE TABLE processed_jar_receipts (
    receipt_cid TEXT PRIMARY KEY,
    jar_id TEXT NOT NULL,
    sequence_number INTEGER NOT NULL,
    processed_at REAL NOT NULL,
    UNIQUE(jar_id, sequence_number)  -- Enforce sequence uniqueness
);
CREATE INDEX idx_processed_jar_receipts_jar ON processed_jar_receipts(jar_id, sequence_number);

-- Tombstones (prevent deleted jar resurrection)
CREATE TABLE jar_tombstones (
    jar_id TEXT PRIMARY KEY,
    jar_name TEXT NOT NULL,        -- For UX ("Bud for deleted Friends jar")
    deleted_at REAL NOT NULL,
    deleted_by_did TEXT NOT NULL
);

-- Receipt queue (dependencies not yet satisfied)
CREATE TABLE jar_receipt_queue (
    id TEXT PRIMARY KEY,
    jar_id TEXT NOT NULL,
    receipt_cid TEXT NOT NULL,
    parent_cid TEXT,               -- Waiting for this CID
    sequence_number INTEGER,       -- Expected sequence
    receipt_data BLOB NOT NULL,    -- Encrypted CBOR
    queued_at REAL NOT NULL
);
CREATE INDEX idx_jar_receipt_queue_parent ON jar_receipt_queue(parent_cid);
CREATE INDEX idx_jar_receipt_queue_jar ON jar_receipt_queue(jar_id, sequence_number);

-- Update jars table
ALTER TABLE jars ADD COLUMN last_sequence_number INTEGER DEFAULT 0;
ALTER TABLE jars ADD COLUMN parent_cid TEXT;  -- Last processed receipt CID
```

### 3. Relay-Side Validation (Cloudflare Workers)

**Critical: Server enforces membership before forwarding receipts**

```typescript
// /api/messages/send - UPDATED
async function sendMessage(request: Request, env: Env) {
    const { jar_id, recipient_dids, receipt_cid } = await request.json();
    const sender_did = await authenticate(request);

    // CRITICAL: Validate sender is active member
    const membership = await env.DB.prepare(`
        SELECT status FROM jar_members
        WHERE jar_id = ? AND member_did = ?
    `).bind(jar_id, sender_did).first();

    if (!membership || membership.status !== 'active') {
        return Response.json(
            { error: "Not a member of this jar" },
            { status: 403 }
        );
    }

    // Validate recipients are active members
    for (const recipient_did of recipient_dids) {
        const recip_membership = await env.DB.prepare(`
            SELECT status FROM jar_members
            WHERE jar_id = ? AND member_did = ?
        `).bind(jar_id, recipient_did).first();

        if (!recip_membership || recip_membership.status !== 'active') {
            // Filter out non-members (don't fail entire send)
            recipient_dids = recipient_dids.filter(did => did !== recipient_did);
        }
    }

    // Forward to valid recipients only
    // ... existing send logic
}

// NEW: /api/jars/{jar_id}/receipts - Backfill missing receipts
async function getJarReceipts(request: Request, env: Env) {
    const url = new URL(request.url);
    const jar_id = url.pathname.split('/')[3];
    const from_seq = parseInt(url.searchParams.get('from') || '0');
    const to_seq = parseInt(url.searchParams.get('to') || '999999');

    const receipts = await env.DB.prepare(`
        SELECT receipt_cid, receipt_data, sequence_number
        FROM jar_receipts
        WHERE jar_id = ? AND sequence_number BETWEEN ? AND ?
        ORDER BY sequence_number ASC
    `).bind(jar_id, from_seq, to_seq).all();

    return Response.json({ receipts: receipts.results });
}
```

### 4. Client-Side Processing (JarSyncManager)

**New: Dependency resolution + sequencing**

```swift
actor JarSyncManager {
    static let shared = JarSyncManager()

    // Process incoming jar receipt
    func processReceipt(_ encryptedReceipt: EncryptedMessage) async throws {
        // 1. Decrypt
        let rawCBOR = try await E2EEManager.shared.decryptMessage(encryptedReceipt)

        // 2. Decode to get common fields
        let receipt = try ReceiptCanonicalizer.decodeJarReceipt(from: rawCBOR)
        let jarID = receipt.jarID

        // 3. Check tombstone (deleted jar)
        if try await JarRepository.shared.isTombstoned(jarID) {
            print("⚠️ Receipt for deleted jar \(jarID), ignoring")
            return
        }

        // 4. Check if already processed (replay protection)
        if try await isAlreadyProcessed(receiptCID: receipt.cid) {
            print("⚠️ Receipt already processed: \(receipt.cid)")
            return
        }

        // 5. Check sequence number
        let lastSeq = try await JarRepository.shared.getLastSequence(jarID: jarID)
        let expectedSeq = lastSeq + 1

        if receipt.sequenceNumber > expectedSeq {
            // Gap detected! Missing receipts [expectedSeq ... receipt.sequenceNumber-1]
            print("⚠️ Gap detected: expected seq \(expectedSeq), got \(receipt.sequenceNumber)")
            try await requestBackfill(jarID: jarID, from: expectedSeq, to: receipt.sequenceNumber - 1)

            // Queue this receipt for later
            try await queueReceipt(receipt, reason: "sequence_gap")
            return
        }

        // 6. Check parent_cid dependency
        if let parentCID = receipt.parentCID {
            if !(try await isAlreadyProcessed(receiptCID: parentCID)) {
                print("⚠️ Missing parent \(parentCID), queueing receipt")
                try await queueReceipt(receipt, reason: "missing_parent")
                return
            }
        }

        // 7. All dependencies satisfied - process!
        try await applyReceipt(receipt)

        // 8. Mark as processed
        try await markProcessed(receiptCID: receipt.cid, jarID: jarID, sequence: receipt.sequenceNumber)

        // 9. Try to process queued receipts (dependencies might now be satisfied)
        try await processQueuedReceipts(jarID: jarID)
    }

    // Process queued receipts that now have dependencies satisfied
    private func processQueuedReceipts(jarID: String) async throws {
        let queued = try await JarRepository.shared.getQueuedReceipts(jarID: jarID)

        for queuedReceipt in queued {
            // Check if dependencies now satisfied
            let canProcess = try await checkDependencies(queuedReceipt)
            if canProcess {
                try await processReceipt(queuedReceipt)
                try await JarRepository.shared.removeFromQueue(queuedReceipt.id)
            }
        }
    }

    // Request missing receipts from relay
    private func requestBackfill(jarID: String, from: Int, to: Int) async throws {
        print("📡 Requesting backfill for jar \(jarID): seq \(from) to \(to)")
        let receipts = try await RelayClient.shared.getJarReceipts(jarID: jarID, from: from, to: to)

        for receipt in receipts {
            try await processReceipt(receipt)  // Process in order
        }
    }
}
```

---

## Updated Receipt Types

### 1. jar.created

```swift
struct JarCreatedPayload: Codable {
    // Base (common to all jar receipts)
    let jarID: String
    let sequenceNumber: Int         // Always 1 (first operation)
    let parentCID: String?          // Always nil (root)
    let timestamp: Int64
    let senderDID: String           // Owner DID

    // Specific to jar.created
    let jarName: String
    let jarDescription: String?
    let ownerDID: String            // Redundant with senderDID but explicit
    let createdAtMs: Int64
}

// When to generate:
// - Owner creates jar locally
// - Owner adds first member (sends to them)

// When received:
// - Check tombstone first
// - Create jar (status: pending_invite)
// - Create jar_invite entry
// - Post notification
```

### 2. jar.member_added

```swift
struct JarMemberAddedPayload: Codable {
    // Base
    let jarID: String
    let sequenceNumber: Int         // Increments from last jar operation
    let parentCID: String           // Previous jar operation
    let timestamp: Int64
    let senderDID: String           // Owner (only owner can add)

    // Specific
    let memberDID: String
    let memberDisplayName: String
    let memberPhoneNumber: String   // For UI
    let memberDevices: [Device]     // For encryption
    let addedByDID: String          // Owner (redundant but explicit)
    let addedAtMs: Int64
}

// Sent to: new member + all existing active members
```

### 3. jar.invite_accepted

```swift
struct JarInviteAcceptedPayload: Codable {
    // Base
    let jarID: String
    let sequenceNumber: Int         // Member's first operation on this jar
    let parentCID: String           // jar.member_added CID
    let timestamp: Int64
    let senderDID: String           // Member accepting

    // Specific
    let memberDID: String           // Who accepted (redundant)
    let acceptedAtMs: Int64
}

// Sent to: owner + all active members
```

### 4. jar.member_removed

```swift
struct JarMemberRemovedPayload: Codable {
    // Base
    let jarID: String
    let sequenceNumber: Int
    let parentCID: String
    let timestamp: Int64
    let senderDID: String           // Owner only

    // Specific
    let memberDID: String           // Who was removed
    let removedByDID: String        // Owner
    let removedAtMs: Int64
    let reason: String?             // Optional
}

// Sent to: removed member + all active members
```

### 5. jar.member_left

```swift
struct JarMemberLeftPayload: Codable {
    // Base
    let jarID: String
    let sequenceNumber: Int
    let parentCID: String
    let timestamp: Int64
    let senderDID: String           // Member leaving

    // Specific
    let memberDID: String           // Who left (redundant)
    let leftAtMs: Int64
}

// Sent to: owner + all active members
```

### 6. jar.updated

```swift
struct JarUpdatedPayload: Codable {
    // Base
    let jarID: String
    let sequenceNumber: Int
    let parentCID: String
    let timestamp: Int64
    let senderDID: String           // Owner only

    // Specific
    let jarName: String?            // nil = no change
    let jarDescription: String?     // nil = no change
    let updatedByDID: String
    let updatedAtMs: Int64
}

// Conflict resolution: Last sequence number wins (not timestamp)
```

### 7. jar.deleted

```swift
struct JarDeletedPayload: Codable {
    // Base
    let jarID: String
    let sequenceNumber: Int         // Final operation
    let parentCID: String
    let timestamp: Int64
    let senderDID: String           // Owner only

    // Specific
    let deletedByDID: String
    let deletedAtMs: Int64
    let jarName: String             // For tombstone
}

// Creates tombstone, prevents future operations
```

### 8. session.created (UPDATED)

**Add jar_id to existing bud receipts:**

```swift
struct SessionPayload: Codable {
    // ... existing fields (product_name, rating, etc.) ...

    let jarID: String?              // NEW: Which jar this bud belongs to
                                    // nil = Solo (backwards compat)
}

// When sharing:
// - Include jar_id from local jar
// - Recipient uses jar_id to place bud correctly
```

---

## Implementation Modules (Updated with Crypto + Relay Envelope)

**⚠️ CRITICAL: RELAY ENVELOPE ARCHITECTURE (Jan 3, 2026)**

This planning doc has been updated to reflect relay envelope architecture where:
- **Sequence numbers are RELAY-ASSIGNED** (not client-generated)
- **Client sends receipt WITHOUT sequence** → relay assigns authoritative sequence
- **Client stores relay-assigned sequence** for gap detection
- **All modules marked with ✅ UPDATED or ✅ COMPATIBLE** for clarity

**Module Status:**
- ✅ Module 0.1-0.6: Completed (CBOR pinning, phone identity, relay infrastructure)
- ✅ Module 1: Updated for relay envelope (NO client sequences)
- ✅ Module 2-3: Compatible (no sequence generation)
- ✅ Module 4: Updated for relay envelope (gap detection uses relay sequences)
- ✅ Module 5-6: Updated for relay envelope (NO client sequences, relay integration)
- ✅ Module 7-10: Compatible (no jar receipt sequence generation)

**NEW: Crypto modules added before distributed systems modules**

### Module 0.1: CBOR Library Pinning (2-3 hours) ← CRYPTO FIX

**CRITICAL: Do this FIRST before any receipt changes**

**Files to modify:**
- `Package.swift` - Pin SwiftCBOR to exact version
- Create `Tests/ReceiptTests/CBORCanonicalityTests.swift` - Golden file tests

**Tasks:**
1. Pin SwiftCBOR in SPM:
   ```swift
   dependencies: [
       .package(
           url: "https://github.com/valpackett/SwiftCBOR.git",
           exact: "0.4.5"  // EXACT version, never change
       )
   ]
   ```

2. Create golden file test:
   ```swift
   func testSessionPayloadCBORStability() throws {
       let payload = SessionPayload(/* fixed test data */)
       let cbor = try ReceiptCanonicalizer.canonicalCBOR(payload)
       let expectedHex = "a96b636c61696d65645f74..."  // Golden bytes
       XCTAssertEqual(cbor.hexString(), expectedHex)
   }
   ```

3. Document CBOR policy in `docs/CBOR_POLICY.md`

**Success criteria:**
- SwiftCBOR pinned to exact 0.4.5
- Golden test passes
- Test fails if CBOR encoding changes
- Policy documented

---

### Module 0.2: Phone-Based Identity (4-6 hours) ← CRYPTO FIX

**Fixes multi-device DID problem**

**Files to modify:**
- `Core/Auth/IdentityManager.swift` - Change DID derivation
- `Core/Auth/DeviceManager.swift` - Register with phone-based DID
- `Core/Database/Database.swift` - Migration for DID change

**Tasks:**
1. Update DID derivation:
   ```swift
   // Old: DID = did:key:<Ed25519_pubkey>
   // New: DID = did:phone:SHA256(<phone>+<salt>)

   func deriveDID(phoneNumber: String, accountSalt: String) -> String {
       let combined = phoneNumber + accountSalt
       let hash = SHA256.hash(data: combined.data(using: .utf8)!)
       return "did:phone:" + hash.hexString()
   }
   ```

2. Update registration flow:
   - Request account salt from relay during auth
   - Compute DID from phone + salt
   - Store DID in keychain (same for all devices with same phone)

3. Migration for existing users:
   - Fetch phone from Firebase Auth
   - Fetch/create account salt from relay
   - Re-derive DID
   - Update all receipts with new DID (or accept break for V1)

**Success criteria:**
- Multiple devices with same phone → same DID
- DID derivable from phone + salt
- Migration succeeds without data loss

---

### Module 0.3: Deterministic Phone Encryption (3-4 hours) ← CRYPTO FIX

**Relay side: Prevents rainbow table attacks**

**Files to modify:**
- `buds-relay/src/phone_encryption.ts` - New encryption module
- `buds-relay/src/handlers/register.ts` - Use encrypted phone storage
- `buds-relay/src/handlers/lookup.ts` - Lookup by encrypted phone

**Tasks:**
1. Add encryption key to Cloudflare secrets:
   ```bash
   wrangler secret put PHONE_ENCRYPTION_KEY
   # Enter 32-byte base64 key
   ```

2. Implement deterministic encryption:
   ```typescript
   async function encryptPhone(phone: string, key: CryptoKey): Promise<string> {
       // Deterministic: same phone → same ciphertext (for lookups)
       const nonce = await deriveNonce(phone);  // Deterministic from phone
       const encrypted = await crypto.subtle.encrypt(
           { name: 'AES-GCM', iv: nonce },
           key,
           new TextEncoder().encode(phone)
       );
       return bufferToBase64(encrypted);
   }
   ```

3. Update register endpoint:
   - Store encrypted_phone instead of phone_hash
   - Generate account_salt for DID derivation

4. Update lookup endpoint:
   - Encrypt query phone
   - Lookup by encrypted_phone (deterministic match)

**Success criteria:**
- Rainbow tables don't work (ciphertext, not hash)
- Lookups work (deterministic encryption)
- DB leak doesn't expose phones (encrypted)

---

### Module 0.4: Dynamic Device Discovery (2-3 hours) ← CRYPTO FIX

**Handles devices added after TOFU pinning**

**Files to modify:**
- `Core/InboxManager.swift` - Fetch unknown devices on-demand
- `Core/JarManager.swift` - Add getPinnedX25519 fallback

**Tasks:**
1. Update decryptMessage to fetch unknown devices:
   ```swift
   func decryptMessage(_ message: EncryptedMessage) async throws -> Data {
       var senderDevice = try await getPinnedDevice(
           did: message.senderDID,
           deviceID: message.senderDeviceId
       )

       if senderDevice == nil {
           // Unknown device - fetch from relay
           print("⚠️ Unknown device, fetching...")
           let devices = try await RelayClient.shared.getDevices(for: [message.senderDID])
           guard let newDevice = devices.first(where: { $0.id == message.senderDeviceId }) else {
               throw InboxError.deviceNotFound
           }

           // Pin new device (updated TOFU)
           try await pinDevice(newDevice)
           senderDevice = newDevice

           // Show warning to user
           await showToast("New device detected from \(message.senderDID). Verify safety number.")
       }

       // Decrypt with pinned key
       // ...
   }
   ```

2. Add toast notification for new devices

**Success criteria:**
- Receive message from unknown device → fetches from relay
- New device pinned automatically
- Warning shown to user

---

### Module 0.5: Safety Number UI (1-2 hours) ← CRYPTO FIX

**Optional TOFU verification**

**Files to create:**
- `Features/Circle/SafetyNumberView.swift` - Show safety number

**Files to modify:**
- `Features/Circle/MemberDetailView.swift` - Add "Verify" button

**Tasks:**
1. Generate safety number (FIXED: canonical ordering for determinism):
   ```swift
   func generateSafetyNumber(myDID: String, theirDID: String, theirDevices: [Device]) -> String {
       // CRITICAL: Canonical DID ordering (both parties must compute same hash)
       let orderedDIDs = [myDID, theirDID].sorted().joined()

       // CRITICAL: Deterministic device ordering (prevents array order mismatch)
       let sortedDevices = theirDevices.sorted { $0.deviceId < $1.deviceId }
       let deviceKeys = sortedDevices.map { $0.pubkeyEd25519 }.joined()

       // Compute hash
       let combined = orderedDIDs + deviceKeys
       let hash = SHA256.hash(data: combined.data(using: .utf8)!)

       // Format as groups: "12345 67890 12345 67890 12345 67890"
       return formatAsGroups(hash.prefix(30))
   }

   private func formatAsGroups(_ hash: Data.SubSequence) -> String {
       let hexString = hash.map { String(format: "%02x", $0) }.joined()
       // Group into 5-digit chunks for readability
       return stride(from: 0, to: hexString.count, by: 5)
           .map { i -> String in
               let start = hexString.index(hexString.startIndex, offsetBy: i)
               let end = hexString.index(start, offsetBy: min(5, hexString.count - i))
               return String(hexString[start..<end])
           }
           .joined(separator: " ")
   }
   ```

2. Add to MemberDetailView:
   ```swift
   Section("Security") {
       HStack {
           Text("Safety Number")
           Spacer()
           Text(viewModel.safetyNumber)
               .font(.system(.caption, design: .monospaced))
       }
       .onTapGesture {
           showingSafetyNumberSheet = true
       }

       // Show device count for context
       Text("Based on \(viewModel.deviceCount) device(s)")
           .font(.caption2)
           .foregroundColor(.secondary)
   }
   ```

3. SafetyNumberView sheet:
   - Show full safety number (large, monospaced font)
   - Device count: "Based on 2 devices"
   - Instructions: "Compare this number with your friend's device. If they match, your connection is secure."
   - QR code (optional, defer to polish)
   - Note: "This number will change if your friend adds a new device"

**Success criteria:**
- Safety number generated correctly
- UI shows in member detail
- Clear instructions for verification

---

### Module 0.6: Relay Infrastructure (4-5 hours)

**Critical: Relay envelope + production upgrades A-E**

**ARCHITECTURE:** Relay is authoritative source of truth for:
1. Sequence number assignment (atomic, conflict-free, in envelope)
2. Jar membership state (materialized view from receipts)
3. Receipt storage (backfill source)

**Files to create:**
- `buds-relay/migrations/0007_jar_receipts_and_members.sql` - D1 schema (relay envelope)
- `buds-relay/src/handlers/jarReceipts.ts` - Receipt storage + backfill (both APIs)
- `buds-relay/src/utils/jarValidation.ts` - Membership validation logic
- `buds-relay/src/utils/receiptProcessor.ts` - Process receipts → update jar_members

**Tasks:**

**1. D1 Migration 0007 (Relay Envelope Structure):**
```sql
-- Jar membership state (materialized view from receipts)
CREATE TABLE jar_members (
    jar_id TEXT NOT NULL,
    member_did TEXT NOT NULL,
    status TEXT NOT NULL,          -- 'active' | 'pending' | 'removed'
    role TEXT NOT NULL,             -- 'owner' | 'member'
    added_at INTEGER NOT NULL,      -- From receipt timestamp
    removed_at INTEGER,             -- From receipt timestamp
    added_by_receipt_cid TEXT,      -- Which receipt added this member
    removed_by_receipt_cid TEXT,    -- Which receipt removed this member
    PRIMARY KEY (jar_id, member_did)
);

CREATE INDEX idx_jar_members_did ON jar_members(member_did);
CREATE INDEX idx_jar_members_jar_status ON jar_members(jar_id, status);

-- Jar receipts (relay envelope - separates signed payload from relay metadata)
CREATE TABLE jar_receipts (
    -- Relay envelope (NOT part of signed bytes)
    jar_id TEXT NOT NULL,
    sequence_number INTEGER NOT NULL,   -- AUTHORITATIVE (relay-assigned, UNIQUE)
    receipt_cid TEXT NOT NULL,          -- CID of signed payload
    receipt_data BLOB NOT NULL,         -- Signed payload bytes (canonical CBOR)
    signature BLOB NOT NULL,            -- Client's Ed25519 signature
    sender_did TEXT NOT NULL,           -- Duplicated for indexing
    received_at INTEGER NOT NULL,       -- Server timestamp
    parent_cid TEXT,                    -- Optional causal metadata (from payload)

    PRIMARY KEY (jar_id, sequence_number)
);

-- CRITICAL: Ensure receipt_cid is globally unique (prevent duplicate receipts)
CREATE UNIQUE INDEX idx_jar_receipts_cid ON jar_receipts(receipt_cid);

-- Index for backfill queries (jar + sequence range)
CREATE INDEX idx_jar_receipts_jar_seq ON jar_receipts(jar_id, sequence_number);

-- Index for sender lookups
CREATE INDEX idx_jar_receipts_sender ON jar_receipts(sender_did);
```

**2. POST /api/jars/{jar_id}/receipts - Store receipt + assign sequence (Upgrade A):**

**Request:**
```typescript
{
  "receipt_data": "base64...",    // Signed CBOR payload (NO sequence inside)
  "signature": "base64...",       // Ed25519 signature over receipt_data
  "parent_cid": "bafy..."         // Optional (extracted from payload, cached for indexing)
}
```

**Response:**
```typescript
{
  "success": true,
  "receipt_cid": "bafy...",
  "sequence_number": 5,           // AUTHORITATIVE (relay-assigned)
  "jar_id": "uuid"
}
```

**Implementation:**
1. Validate sender is active member (403 if not)
2. Compute receipt_cid from receipt_data
3. Check idempotency (receipt_cid already exists?)
4. Assign sequence atomically: `MAX(sequence_number) + 1`
5. Store receipt + envelope metadata
6. **Process receipt → update jar_members** (Upgrade E)
7. Broadcast to active jar members (returns envelope with sequence)

**3. GET /api/jars/{jar_id}/receipts - Backfill (Upgrades B):**

**Two APIs:**

**A) Normal sync (workhorse):**
```
GET /api/jars/{jar}/receipts?after={lastSeq}&limit=500
```
Returns receipts with `sequence_number > lastSeq` (up to limit).

**B) Gap filling:**
```
GET /api/jars/{jar}/receipts?from={seq}&to={seq}
```
Returns receipts in range [from, to] (for specific gaps).

**Response (both):**
```typescript
{
  "receipts": [
    {
      "jar_id": "uuid",
      "sequence_number": 5,
      "receipt_cid": "bafy...",
      "receipt_data": "base64...",   // Signed CBOR payload
      "signature": "base64...",
      "sender_did": "did:phone:...",
      "received_at": 1234567890,
      "parent_cid": "bafy..."        // Optional
    }
  ]
}
```

**4. Receipt Processing (Upgrade E):**

When relay stores receipt, immediately process to update `jar_members`:
- `jar.created` → Insert owner into jar_members (role: owner, status: active)
- `jar.member_added` → Insert member (role: member, status: pending)
- `jar.invite_accepted` → Update status: pending → active
- `jar.member_removed` → Update status: active → removed, set removed_at

**5. Update /api/messages/send:**
- Validate sender is active member (query jar_members)
- Filter recipients to only active members
- Reject if sender not a member (403)

**Success criteria:**
- Relay envelope separates signed payload from metadata ✅
- Sequence NOT in signed bytes ✅
- Both `/receipts?after=` and `/receipts?from=&to=` APIs work ✅
- jar_members updated automatically from receipts ✅
- Membership validation enforced ✅
- Curl tests pass ✅

### Module 1: Receipt Types & Relay Integration (3-4 hours) ✅ COMPLETE (Jan 3, 2026)

**⚠️ CRITICAL ARCHITECTURE (Relay Envelope):**
- **Sequence NOT in signed bytes** (relay assigns in envelope)
- **Client sends receipt → relay assigns sequence → client stores relay sequence**
- **NO client-side sequence generation** (relay is authoritative)

**Files created:**
- `Core/Models/JarReceipts.swift` - 9 jar payload structs (NO sequence field)
- `Core/RelayClient+JarReceipts.swift` - Relay API integration

**Files modified:**
- `Core/ChaingeKernel/ReceiptCanonicalizer.swift` - CBOR encoding for 9 receipt types

**Implemented:**
1. ✅ JarReceiptPayload (base envelope, NO sequence)
2. ✅ 9 jar receipt types:
   - `jar.created` - Owner creates jar
   - `jar.member_added` - Owner adds member
   - `jar.invite_accepted` - Member accepts invite
   - `jar.member_removed` - Owner removes member
   - `jar.member_left` - Member leaves voluntarily
   - `jar.renamed` - Owner renames jar
   - `jar.deleted` - Owner deletes jar
   - `jar.bud_shared` - Member shares bud to jar ← **Added Jan 3**
   - `jar.bud_deleted` - Owner deletes bud from jar ← **Added Jan 3**
3. ✅ CBOR canonicalization for all 9 types
4. ✅ Relay integration:
   - `storeJarReceipt()` - POST /api/jars/{jar_id}/receipts
   - `getJarReceipts(after:)` - Normal sync
   - `getJarReceipts(from:to:)` - Gap filling
5. ✅ RelayEnvelope struct (receive-only, has relay-assigned sequence)
6. ✅ StoreReceiptResponse struct (relay returns sequence)

**Key Architecture:**
- Signed payload: jarID, receiptType, senderDID, timestamp, parentCID, payload
- Relay envelope (NOT signed): sequenceNumber, receiptCID, receiptData, signature, receivedAt
- Client never generates sequences (relay is authoritative)

**Deletion Semantics (Designed for TestFlight + Future RBAC):**
- Bud deletion: `jar.bud_deleted` receipt propagates to all members
- Validation: deletedByDID must match bud.ownerDID (only owner can delete)
- Jar deletion: `jar.deleted` receipt → members move buds to Solo jar
- Future: "Deleted Jars" namespace in Solo jar (post-beta polish)

**Success criteria:** ✅ All achieved
- Can generate receipts WITHOUT sequence, sign them
- Send to relay → relay assigns sequence
- Store relay-assigned sequence locally
- CBOR encoding deterministic and canonical
- Relay APIs work for store + backfill

### Module 2: Database Migration (2-3 hours) ✅ RELAY ENVELOPE COMPATIBLE

**⚠️ NOTE:** This module is already compatible with relay envelope architecture.
- `last_sequence_number` in jars table stores RELAY-ASSIGNED sequence (not client-generated)
- No changes needed for relay envelope

**Files to modify:**
- `Core/Database/Database.swift` - Migration v8

**Tasks:**
1. Create processed_jar_receipts table
2. Create jar_tombstones table
3. Create jar_receipt_queue table
4. Add last_sequence_number to jars table (stores relay-assigned sequence)
5. Backfill Solo jar with owner_did, last_sequence_number=0

**Success criteria:**
- Fresh install: v8 schema created
- Existing install: v7 → v8 migration succeeds
- No data loss

### Module 3: Receipt Processing Pipeline (4-5 hours) ← **REWRITTEN JAN 3, 2026**

**⚠️ ARCHITECTURE REDESIGN:**
This module builds the **core sync engine** - receives relay envelopes, verifies, applies to local state.
Simple, no queueing yet (Module 4 adds gap detection + queueing).

**Purpose:** Process in-order jar receipts from relay, maintain distributed jar state

**Files to create:**
- `Core/JarSyncManager.swift` - **NEW** Main receipt processing pipeline (~300 lines)
- `Core/Database/Repositories/JarTombstoneRepository.swift` - Tombstone CRUD (~80 lines)

**Files to modify:**
- `Core/JarManager.swift` - Create tombstone on jar delete

**JarSyncManager Architecture:**
```swift
class JarSyncManager: ObservableObject {
    static let shared = JarSyncManager()

    // MARK: - Main Entry Point

    /// Process relay envelope (SIMPLE - no gap detection yet)
    func processEnvelope(_ envelope: RelayEnvelope) async throws {
        // 1. Replay protection
        guard !isAlreadyProcessed(envelope.receiptCID) else {
            print("⏭️ Skipping already processed receipt: \(envelope.receiptCID)")
            return
        }

        // 2. Tombstone check
        guard !isTombstoned(envelope.jarID) else {
            print("🪦 Skipping receipt for tombstoned jar: \(envelope.jarID)")
            return
        }

        // 3. Verify signature + CID
        try verifyReceipt(envelope)

        // 4. Apply receipt to local state
        try await applyReceipt(envelope)

        // 5. Mark as processed + update sequence
        try await markProcessed(
            receiptCID: envelope.receiptCID,
            jarID: envelope.jarID,
            sequenceNumber: envelope.sequenceNumber
        )
    }

    // MARK: - Verification

    func isAlreadyProcessed(_ receiptCID: String) -> Bool {
        // Check processed_jar_receipts table
    }

    func isTombstoned(_ jarID: String) -> Bool {
        // Check jar_tombstones table
    }

    func verifyReceipt(_ envelope: RelayEnvelope) throws {
        // 1. Verify CID matches receiptData hash
        // 2. Verify Ed25519 signature
        // 3. Verify senderDID matches signature pubkey
    }

    // MARK: - Apply Receipts

    func applyReceipt(_ envelope: RelayEnvelope) async throws {
        // Decode receipt type
        let payload = try decodeReceiptPayload(envelope.receiptData)

        // Route to handler
        switch payload.receiptType {
        case .jarCreated:
            try await applyJarCreated(envelope)
        case .jarMemberAdded:
            try await applyMemberAdded(envelope)
        case .jarInviteAccepted:
            try await applyInviteAccepted(envelope)
        case .jarMemberRemoved:
            try await applyMemberRemoved(envelope)
        case .jarMemberLeft:
            try await applyMemberLeft(envelope)
        case .jarRenamed:
            try await applyJarRenamed(envelope)
        case .jarBudShared:
            try await applyBudShared(envelope)
        case .jarBudDeleted:
            try await applyBudDeleted(envelope)
        case .jarDeleted:
            try await applyJarDeleted(envelope)
        default:
            throw SyncError.unknownReceiptType
        }
    }

    // MARK: - Receipt Handlers (9 types)

    func applyJarCreated(_ envelope: RelayEnvelope) async throws {
        // Decode payload
        let payload = try decodeJarCreatedPayload(envelope)

        // Create jar locally (status: pending if not owner)
        let jar = try await JarRepository.shared.createJar(
            id: envelope.jarID,
            name: payload.jarName,
            description: payload.jarDescription,
            ownerDID: payload.ownerDID,
            lastSequenceNumber: envelope.sequenceNumber,
            parentCID: envelope.receiptCID
        )

        // Add owner to jar_members (active)
        try await JarMemberRepository.shared.addMember(
            jarID: envelope.jarID,
            did: payload.ownerDID,
            role: .owner,
            status: .active
        )
    }

    func applyBudShared(_ envelope: RelayEnvelope) async throws {
        // Decode payload
        let payload = try decodeJarBudSharedPayload(envelope)

        // Link bud to jar (ucr_headers.jar_id = envelope.jarID)
        try await MemoryRepository.shared.updateJarID(
            budUUID: payload.budUUID,
            jarID: envelope.jarID
        )

        // Verify bud CID matches (optional integrity check)
        let bud = try await MemoryRepository.shared.fetch(uuid: payload.budUUID)
        guard bud?.cid == payload.budCID else {
            throw SyncError.budCIDMismatch
        }
    }

    func applyBudDeleted(_ envelope: RelayEnvelope) async throws {
        // Decode payload
        let payload = try decodeJarBudDeletedPayload(envelope)

        // Validate: deletedByDID must match bud.ownerDID
        let bud = try await MemoryRepository.shared.fetch(uuid: payload.budUUID)
        guard bud?.did == payload.deletedByDID else {
            throw SyncError.notBudOwner
        }

        // Remove bud from jar (ucr_headers.jar_id = NULL)
        try await MemoryRepository.shared.updateJarID(
            budUUID: payload.budUUID,
            jarID: nil  // Unlink from jar
        )

        // Note: Bud still exists in ucr_headers (only unlinked from jar)
        // If jar owner deletes jar, buds move to Solo (handled by applyJarDeleted)
    }

    func applyJarDeleted(_ envelope: RelayEnvelope) async throws {
        // Decode payload
        let payload = try decodeJarDeletedPayload(envelope)

        // Create tombstone
        try await JarTombstoneRepository.shared.create(
            jarID: envelope.jarID,
            jarName: payload.jarName,
            deletedByDID: payload.deletedByDID
        )

        // Move jar buds to Solo jar
        try await moveJarBudsToSolo(jarID: envelope.jarID)

        // Delete jar locally
        try await JarRepository.shared.delete(envelope.jarID)
    }

    // ... other handlers (member_added, invite_accepted, etc.)

    // MARK: - Persistence

    func markProcessed(receiptCID: String, jarID: String, sequenceNumber: Int) async throws {
        // Insert into processed_jar_receipts
        // Update jars.last_sequence_number = sequenceNumber
        // Update jars.parent_cid = receiptCID
    }
}
```

**JarTombstoneRepository:**
```swift
class JarTombstoneRepository {
    static let shared = JarTombstoneRepository()

    func create(jarID: String, jarName: String, deletedByDID: String) async throws {
        try await db.writeAsync { db in
            try db.execute(sql: """
                INSERT INTO jar_tombstones (jar_id, jar_name, deleted_at, deleted_by_did)
                VALUES (?, ?, ?, ?)
            """, arguments: [jarID, jarName, Date().timeIntervalSince1970, deletedByDID])
        }
    }

    func isTombstoned(_ jarID: String) async throws -> Bool {
        try await db.readAsync { db in
            try Int.fetchOne(db, sql: "SELECT 1 FROM jar_tombstones WHERE jar_id = ?", arguments: [jarID]) != nil
        }
    }
}
```

**Tasks:**
1. ✅ Create JarSyncManager.swift
2. ✅ Implement replay protection (check processed_jar_receipts)
3. ✅ Implement tombstone checking (check jar_tombstones)
4. ✅ Implement signature + CID verification
5. ✅ Implement 9 receipt handlers (jar.created, member_added, bud_shared, bud_deleted, jar_deleted, etc.)
6. ✅ Create JarTombstoneRepository.swift
7. ✅ Update JarManager.deleteJar() to create tombstone + generate jar.deleted receipt

**Success criteria:**
- ✅ Process jar.created → jar created locally
- ✅ Process jar.bud_shared → bud linked to jar
- ✅ Process jar.bud_deleted → bud unlinked from jar (validation: only owner can delete)
- ✅ Process jar.deleted → tombstone created, buds moved to Solo, jar deleted
- ✅ Replay protection works (skip already-processed receipts)
- ✅ Tombstone protection works (skip receipts for deleted jars)
- ✅ Signature verification works (invalid signatures rejected)

**Estimated:** 4-5 hours

### Module 4: Gap Detection & Queueing (4-5 hours) ← **REWRITTEN JAN 3, 2026**

**⚠️ ARCHITECTURE REDESIGN:**
This module **extends JarSyncManager** (from Module 3) with distributed systems hardening:
- Sequence gap detection (relay-assigned sequences)
- Receipt queueing for out-of-order arrivals
- Backfill requests for missing receipts
- Queue processing when dependencies satisfied

**Purpose:** Handle imperfect network conditions (packet loss, out-of-order delivery)

**Files to modify:**
- `Core/JarSyncManager.swift` - Add gap detection + queueing (~150 lines added)

**No new files** - extends existing JarSyncManager from Module 3

**Architecture Changes to JarSyncManager:**

**1. Replace Simple processEnvelope with Gap-Detecting Version:**
```swift
extension JarSyncManager {

    /// Process envelope WITH gap detection (replaces Module 3 simple version)
    func processEnvelope(_ envelope: RelayEnvelope) async throws {
        // 1. Replay protection (same as Module 3)
        guard !isAlreadyProcessed(envelope.receiptCID) else {
            print("⏭️ Skipping already processed: \(envelope.receiptCID)")
            return
        }

        // 2. Tombstone check (same as Module 3)
        guard !isTombstoned(envelope.jarID) else {
            print("🪦 Skipping tombstoned jar: \(envelope.jarID)")
            return
        }

        // 3. **NEW: Gap detection**
        let lastSeq = try await getLastSequence(jarID: envelope.jarID)
        let expectedSeq = lastSeq + 1

        if envelope.sequenceNumber > expectedSeq {
            // Missing receipts detected!
            print("⚠️ Gap: expected \(expectedSeq), got \(envelope.sequenceNumber)")

            // Request missing receipts from relay
            try await requestBackfill(
                jarID: envelope.jarID,
                from: expectedSeq,
                to: envelope.sequenceNumber - 1
            )

            // Queue this receipt (can't process yet)
            try await queueReceipt(envelope, reason: "sequence_gap")
            return
        }

        if envelope.sequenceNumber < expectedSeq {
            // Duplicate or late receipt (already processed higher sequences)
            print("⏪ Late receipt: expected \(expectedSeq), got \(envelope.sequenceNumber)")
            return
        }

        // 4. Process normally (sequence matches expected)
        try verifyReceipt(envelope)
        try await applyReceipt(envelope)
        try await markProcessed(
            receiptCID: envelope.receiptCID,
            jarID: envelope.jarID,
            sequenceNumber: envelope.sequenceNumber
        )

        // 5. **NEW: Try to process queued receipts**
        try await processQueuedReceipts(jarID: envelope.jarID)
    }

    // MARK: - Queueing

    func queueReceipt(_ envelope: RelayEnvelope, reason: String) async throws {
        try await db.writeAsync { db in
            try db.execute(sql: """
                INSERT INTO jar_receipt_queue
                (id, jar_id, receipt_cid, parent_cid, sequence_number, receipt_data, queued_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                UUID().uuidString,
                envelope.jarID,
                envelope.receiptCID,
                envelope.parentCID,
                envelope.sequenceNumber,  // FROM RELAY ENVELOPE
                envelope.receiptData,
                Date().timeIntervalSince1970
            ])
        }
        print("📥 Queued receipt \(envelope.receiptCID) for \(envelope.jarID) (reason: \(reason))")
    }

    func processQueuedReceipts(jarID: String) async throws {
        let queued = try await getQueuedReceipts(jarID: jarID)
        guard !queued.isEmpty else { return }

        print("🔄 Processing \(queued.count) queued receipts for \(jarID)")

        // Sort by relay-assigned sequence (ascending)
        let sorted = queued.sorted { $0.sequenceNumber < $1.sequenceNumber }

        for queuedReceipt in sorted {
            // Check if we can process now
            let lastSeq = try await getLastSequence(jarID: jarID)
            let expectedSeq = lastSeq + 1

            if queuedReceipt.sequenceNumber == expectedSeq {
                // Ready to process!
                print("✅ Processing queued receipt seq=\(queuedReceipt.sequenceNumber)")

                // Reconstruct RelayEnvelope
                let envelope = RelayEnvelope(
                    jarID: queuedReceipt.jarID,
                    sequenceNumber: queuedReceipt.sequenceNumber,
                    receiptCID: queuedReceipt.receiptCID,
                    receiptData: queuedReceipt.receiptData,
                    signature: Data(),  // Already verified before queueing
                    senderDID: "",      // Already verified
                    receivedAt: 0,
                    parentCID: queuedReceipt.parentCID
                )

                // Process (verifyReceipt already done before queueing)
                try await applyReceipt(envelope)
                try await markProcessed(
                    receiptCID: envelope.receiptCID,
                    jarID: envelope.jarID,
                    sequenceNumber: envelope.sequenceNumber
                )

                // Remove from queue
                try await removeFromQueue(queuedReceipt.id)
            } else {
                // Still missing earlier receipts
                print("⏸️ Still waiting for seq=\(expectedSeq) before \(queuedReceipt.sequenceNumber)")
                break  // Can't process rest of queue yet
            }
        }
    }

    func requestBackfill(jarID: String, from: Int, to: Int) async throws {
        print("🔁 Requesting backfill: \(jarID) seq=\(from)-\(to)")

        // Call relay API for gap range
        let envelopes = try await RelayClient.shared.getJarReceipts(
            jarID: jarID,
            from: from,
            to: to
        )

        print("📬 Received \(envelopes.count) backfilled receipts")

        // Process backfilled receipts in order
        for envelope in envelopes.sorted(by: { $0.sequenceNumber < $1.sequenceNumber }) {
            try await processEnvelope(envelope)
        }
    }

    // MARK: - Helpers

    func getLastSequence(jarID: String) async throws -> Int {
        try await db.readAsync { db in
            try Int.fetchOne(db, sql: "SELECT last_sequence_number FROM jars WHERE id = ?", arguments: [jarID]) ?? 0
        }
    }

    func getQueuedReceipts(jarID: String) async throws -> [QueuedReceipt] {
        try await db.readAsync { db in
            try QueuedReceipt.fetchAll(db, sql: """
                SELECT * FROM jar_receipt_queue WHERE jar_id = ?
                ORDER BY sequence_number ASC
            """, arguments: [jarID])
        }
    }

    func removeFromQueue(_ queueID: String) async throws {
        try await db.writeAsync { db in
            try db.execute(sql: "DELETE FROM jar_receipt_queue WHERE id = ?", arguments: [queueID])
        }
    }
}

struct QueuedReceipt {
    let id: String
    let jarID: String
    let receiptCID: String
    let parentCID: String?
    let sequenceNumber: Int
    let receiptData: Data
    let queuedAt: TimeInterval
}
```

**Tasks:**
1. ✅ Replace simple `processEnvelope` with gap-detecting version
2. ✅ Add sequence gap detection (expected vs actual)
3. ✅ Implement `queueReceipt()` - Store in jar_receipt_queue table
4. ✅ Implement `requestBackfill()` - Call relay API for missing range
5. ✅ Implement `processQueuedReceipts()` - Try to unblock queue after each receipt
6. ✅ Add helper: `getLastSequence()`, `getQueuedReceipts()`, `removeFromQueue()`

**Edge Cases Handled:**
- **Gap detected (seq=5, expect 3):** Request backfill 3-4, queue 5, wait
- **Duplicate (seq=2, expect 5):** Skip (already processed)
- **Out-of-order arrival:** Queue until dependencies satisfied
- **Backfill completes:** Process queue in sequence order
- **Multiple gaps:** Handled recursively (backfill → process → check queue → repeat)

**Success criteria:**
- ✅ Receive seq=1,2,4 → detects gap at 3, requests backfill
- ✅ Backfill arrives → processes 3, then queued 4
- ✅ Out-of-order (4 before 3) → queues 4, waits for 3
- ✅ All receipts eventually processed in relay sequence order
- ✅ No duplicate processing (replay protection from Module 3)
- ✅ Queue automatically empties when dependencies satisfied

**Estimated:** 4-5 hours

**Why This Works:**
- Relay sequences are authoritative (conflict-free)
- Gap detection is simple: `expected != actual`
- Queue is temporary (eventually drains)
- Idempotent (replay protection prevents duplication)

### Module 5: Jar Creation with Sync (2-3 hours) ✅ UPDATED FOR RELAY ENVELOPE

**⚠️ CRITICAL ARCHITECTURE CHANGE:**
- ❌ ~~Client generates receipt with sequence=1~~
- ✅ Client generates receipt WITHOUT sequence, sends to relay, relay assigns sequence
- ✅ Relay response contains authoritative sequence (likely 1 for jar.created, but relay decides)

**Files to modify:**
- `Core/JarManager.swift` - Generate jar.created receipt (NO sequence)
- `Core/JarSyncManager.swift` - Process jar.created
- `Core/RelayClient+JarReceipts.swift` - Send receipt to relay

**Tasks:**
1. ❌ ~~Update createJar to generate receipt with sequence=1~~
   ✅ Update createJar to generate receipt, send to relay, store relay-assigned sequence:
   ```swift
   func createJar(name: String, description: String?) async throws -> Jar {
       // Create jar locally
       let jar = try await JarRepository.shared.createJar(...)

       // Generate jar.created receipt (NO sequence, NO parent_cid)
       let receipt = try await ReceiptManager.shared.createJarCreatedReceipt(
           jarID: jar.id,
           jarName: name,
           jarDescription: description,
           ownerDID: currentDID
           // NO sequenceNumber parameter
           // NO parentCID parameter
       )

       // Send to relay → relay assigns sequence
       let response = try await RelayClient.shared.storeJarReceipt(
           jarID: jar.id,
           receiptData: receipt.rawCBOR,
           signature: receipt.signature,
           parentCID: nil  // Root receipt
       )

       // Store relay-assigned sequence (likely 1, but relay is authoritative)
       try await JarRepository.shared.updateLastSequence(jar.id, response.sequenceNumber)

       // Update jar with receipt CID
       try await JarRepository.shared.updateReceiptCID(jar.id, receipt.cid)

       return jar
   }
   ```

2. Process jar.created on receive:
   - Check tombstone
   - Check if already processed
   - Create jar (status: pending_invite)
   - Create jar_invite entry
   - Store relay-assigned sequence from envelope

**Success criteria:**
- Create jar locally → jar.created receipt generated WITHOUT sequence
- Send to relay → relay assigns sequence (e.g., seq=1)
- Store relay sequence locally
- Receive jar.created → jar created as pending

### Module 6: Member Invite Flow (4-5 hours) ✅ UPDATED FOR RELAY ENVELOPE

**⚠️ CRITICAL ARCHITECTURE CHANGE:**
- ❌ ~~Generate jar.member_added receipt (increment seq)~~
- ✅ Generate jar.member_added WITHOUT sequence, send to relay, relay assigns sequence
- ✅ Relay processes receipt → updates jar_members table (Upgrade E)
- ✅ No separate sync endpoint needed (membership derived from receipts)

**Files to modify:**
- `Core/JarManager.swift` - Add member with sync
- `Core/JarSyncManager.swift` - Process member_added/invite_accepted

**Tasks:**
1. ❌ ~~Update addMember to generate receipt with incremented sequence~~
   ✅ Update addMember to generate receipt, send to relay:
   ```swift
   func addMember(jarID: String, phoneNumber: String, displayName: String) async throws {
       // Lookup DID via relay
       let memberDID = try await RelayClient.shared.lookupDID(phoneNumber: phoneNumber)

       // Get member devices
       let devices = try await RelayClient.shared.getDevices(for: [memberDID])

       // Get last receipt CID for parent_cid
       let lastReceiptCID = try await JarRepository.shared.getLastReceiptCID(jarID)

       // Generate jar.member_added receipt (NO sequence)
       let receipt = try await ReceiptManager.shared.createMemberAddedReceipt(
           jarID: jarID,
           memberDID: memberDID,
           memberDisplayName: displayName,
           memberPhoneNumber: phoneNumber,
           memberDevices: devices
           // NO sequenceNumber parameter
       )

       // Send to relay → relay assigns sequence
       let response = try await RelayClient.shared.storeJarReceipt(
           jarID: jarID,
           receiptData: receipt.rawCBOR,
           signature: receipt.signature,
           parentCID: lastReceiptCID
       )

       // Store relay-assigned sequence
       try await JarRepository.shared.updateLastSequence(jarID, response.sequenceNumber)

       // Relay broadcasts to jar members automatically
       // Relay updates jar_members table automatically (Upgrade E)
   }
   ```

2. Process jar.member_added on receive:
   - If you're the new member: store invite
   - If you're existing member: add to jar_members
   - Store relay-assigned sequence from envelope

3. Implement accept invite (same pattern - no client sequence):
   ```swift
   // Generate jar.invite_accepted receipt (NO sequence)
   let receipt = try await ReceiptManager.shared.createInviteAcceptedReceipt(
       jarID: jarID,
       memberDID: currentDID
   )

   // Send to relay → relay assigns sequence
   let response = try await RelayClient.shared.storeJarReceipt(
       jarID: jarID,
       receiptData: receipt.rawCBOR,
       signature: receipt.signature,
       parentCID: lastReceiptCID
   )

   // Relay broadcasts to all members
   // Relay updates jar_members status: pending → active
   ```

**Success criteria:**
- Add member → receipt sent to relay WITHOUT sequence
- Relay assigns sequence, updates jar_members, broadcasts
- Member receives invite → shows in UI
- Member accepts → relay assigns sequence, broadcasts
- **Relay membership state updated automatically from receipts**

### Module 7: Bud Sharing with jar_id (2-3 hours) ✅ RELAY ENVELOPE COMPATIBLE

**⚠️ NOTE:** This module is compatible with relay envelope architecture.
- Bud receipts (session.created) don't use jar receipt sequences
- jar_id is metadata in bud payload, not a jar operation
- No changes needed for relay envelope

**Files to modify:**
- `Core/Models/UCRHeader.swift` - Add jar_id to SessionPayload
- `Core/Database/Repositories/MemoryRepository.swift` - Use jar_id from payload

**Tasks:**
1. Add jar_id field to SessionPayload (optional, backwards compat)
2. Update MemoryRepository.create() to include jar_id
3. Update storeSharedReceipt():
   ```swift
   func storeSharedReceipt(...) async throws {
       let payload = try decode(rawCBOR)
       let jarID = payload.jarID ?? "solo"

       // Check if jar exists
       if try await JarRepository.shared.getJar(jarID) == nil {
           // Jar doesn't exist - could be deleted or not synced yet
           if try await JarTombstoneRepository.shared.exists(jarID) {
               // Jar was deleted - land in Solo with metadata
               let tombstone = try await JarTombstoneRepository.shared.get(jarID)
               print("⚠️ Bud for deleted jar '\(tombstone.jarName)', landing in Solo")
               jarID = "solo"
               // Store local_notes: "Shared to deleted jar: [name]"
           } else {
               // Jar not synced yet - queue bud, request jar backfill
               print("⚠️ Bud for unknown jar \(jarID), requesting sync")
               try await queueBud(bud, waitingForJar: jarID)
               try await requestJarSync(jarID)
               return
           }
       }

       // Store bud with jar_id
       try await storeBud(..., jarID: jarID)
   }
   ```

**Success criteria:**
- Create bud → jar_id in payload
- Share bud → lands in correct jar
- Bud for missing jar → queued, jar requested
- Bud for deleted jar → lands in Solo with metadata

### Module 8: Offline Hardening (3-4 hours) ✅ RELAY ENVELOPE COMPATIBLE

**⚠️ NOTE:** This module is compatible with relay envelope architecture.
- Offline operations queue receipts for relay (relay will assign sequences)
- No client-side sequence generation
- No changes needed for relay envelope

**Files to create:**
- `Core/OfflineQueueManager.swift` - Manage offline operations

**Tasks:**
1. Implement offline operation queue:
   - Max 100 operations
   - Bounded 7-day window
   - Merge duplicate operations (e.g., 500 renames → 1)

2. Validate queued operations before sending:
   ```swift
   func syncOfflineQueue() async throws {
       // First, sync inbox (get latest state)
       try await InboxManager.shared.pollInbox()

       // Then, validate each queued operation
       let queue = try await getOfflineQueue()

       for operation in queue {
           // Check if still valid
           if try await isStillValid(operation) {
               try await sendOperation(operation)
           } else {
               // Show toast: "Jar was deleted, discarding 3 pending operations"
               try await discardOperation(operation)
           }
       }
   }
   ```

3. Show UI when offline >7 days:
   - "Syncing latest state..."
   - Discard stale queue
   - Full resync

**Success criteria:**
- Offline operations queued (max 100)
- Offline >7 days → full resync
- Invalid operations discarded with toast

### Module 9: UI Components (3-4 hours) ✅ RELAY ENVELOPE COMPATIBLE

**⚠️ NOTE:** This module is compatible with relay envelope architecture.
- UI displays jar state, doesn't generate sequences
- No changes needed for relay envelope

**Files to create:**
- `Features/Circle/JarInviteCard.swift` - Pending invite card
- `Features/Circle/JarInviteSheet.swift` - Accept/decline sheet

**Files to modify:**
- `Features/Shelf/ShelfView.swift` - Pending invites section
- `Features/Circle/JarDetailView.swift` - Member status indicators

**Tasks:**
1. Pending invites section on ShelfView:
   ```swift
   if !pendingInvites.isEmpty {
       Section("Pending Invites") {
           ForEach(pendingInvites) { invite in
               JarInviteCard(invite: invite) {
                   // Accept
               } onDecline: {
                   // Decline
               }
           }
       }
   }
   ```

2. Accept/decline flow:
   - Accept → generate jar.invite_accepted
   - Decline → delete jar locally, no receipt (silent)

3. Member status indicators:
   - Active (green check)
   - Pending (orange hourglass)

**Success criteria:**
- Pending invites show above jar grid
- Accept/decline works
- Status badges clear

### Module 10: Notifications & Polish (2-3 hours) ✅ RELAY ENVELOPE COMPATIBLE

**⚠️ NOTE:** This module is compatible with relay envelope architecture.
- Notifications triggered by processed receipts (relay-assigned sequences already stored)
- No changes needed for relay envelope

**Files to modify:**
- `Core/InboxManager.swift` - Post notifications after processing
- `Features/Shelf/ShelfView.swift` - Listen for jar activity

**Tasks:**
1. Toast notifications:
   - "Eric shared Blue Dream to Friends 🌿"
   - "Alex joined Friends jar"
   - "Sam left Friends jar"

2. Unread badges on jar cards:
   - Track unread bud count in jar_stats
   - Show badge on ShelfJarCard

3. Sync status indicator:
   - "Syncing..." (receipts queued)
   - "Up to date"

**Success criteria:**
- Toasts appear on jar activity
- Badges show unread count
- Sync status clear

---

## Relay API Spec (Cloudflare Workers)

### Existing Endpoints (Updated)

```
POST /api/messages/send
  - Add jar membership validation
  - Filter recipients to active members only
  - Return 403 if sender not a member
```

### New Endpoints

```
GET /api/jars/{jar_id}/receipts?from={seq}&to={seq}
  - Returns: { receipts: [{ receipt_cid, receipt_data, sequence_number }, ...] }
  - Auth required
  - Only if requester is active member

POST /api/jars/{jar_id}/sync
  - Body: { operation: "add_member" | "remove_member", member_did, status }
  - Updates relay's authoritative jar membership state
  - Only owner can call
  - Returns: { success: true }

GET /api/jars/{jar_id}/members
  - Returns: { members: [{ member_did, status, added_at }, ...] }
  - Auth required
  - Only active members can call
```

---

## Testing Strategy

### Unit Tests

**Sequencing:**
- [ ] Generate receipts with correct sequence numbers
- [ ] Detect sequence gaps
- [ ] Queue out-of-order receipts
- [ ] Process queue in order

**Tombstones:**
- [ ] Delete jar → tombstone created
- [ ] Late receipt for deleted jar → rejected
- [ ] Bud for deleted jar → lands in Solo

**Replay Protection:**
- [ ] Duplicate receipt → skipped
- [ ] Receipt CID tracked in processed table

### Integration Tests (Two Devices)

**Jar Creation + Invite:**
1. Device A creates jar
2. Device A adds Device B
3. Device B receives jar.created (seq=1) and jar.member_added (seq=2)
4. Device B accepts
5. Device A receives jar.invite_accepted (seq=3)

**Out-of-Order Receipts:**
1. Device A sends receipts seq [1, 2, 3, 4]
2. Network reorders: Device B receives [1, 3, 4, 2]
3. Device B queues [3, 4] (missing parent)
4. Device B processes [1, 2]
5. Device B processes queued [3, 4]

**Missing Receipt Detection:**
1. Device A sends receipts seq [1, 2, 3, 5]
2. Device B receives [1, 2, 3], then jumps to [5]
3. Device B detects gap (missing seq 4)
4. Device B requests backfill from relay
5. Device B receives seq 4, processes [4, 5]

**Removed Member:**
1. Device A removes Device B
2. Device B sends bud to jar (offline)
3. Relay rejects (403: not a member)
4. Device B shows error toast

### Manual Testing (Real Devices)

**Offline Scenarios:**
- [ ] Offline 1 day → operations queued → syncs on reconnect
- [ ] Offline 8 days → queue discarded, full resync
- [ ] Create jar offline → sent when online

**Conflict Scenarios:**
- [ ] Two devices rename jar → last sequence wins
- [ ] Member removed while offline → operations discarded

**Edge Cases:**
- [ ] Bud for deleted jar → Solo with toast
- [ ] Bud for unknown jar → queue, request sync
- [ ] Duplicate invite → ignored

---

## Rollout Plan

### Week 1: Server + Core (16-20 hours)

**Days 1-2:**
- Module 0: Relay infrastructure (3-4h)
- Module 1: Receipt types (3-4h)
- Module 2: Database migration (2-3h)

**Days 3-4:**
- Module 3: Tombstones + replay (2-3h)
- Module 4: Dependency resolution (4-5h)

**Day 5:**
- Testing: Unit tests for sequencing, tombstones

### Week 2: Sync + UI (12-16 hours)

**Days 1-2:**
- Module 5: Jar creation sync (2-3h)
- Module 6: Member invite flow (4-5h)

**Days 3-4:**
- Module 7: Bud jar_id sync (2-3h)
- Module 8: Offline hardening (3-4h)

**Day 5:**
- Module 9: UI components (3-4h)
- Module 10: Notifications (2-3h)

### Week 3: Testing + Polish (4-8 hours)

- Integration testing (two devices)
- Manual testing (real devices)
- Edge case verification
- Bug fixes

**Total: 32-44 hours** (realistic, with hardening)

---

## Open Questions / Decisions

### 1. Conflict Resolution Strategy ✅ RESOLVED

**Question:** When two operations have same sequence number (network partition), which wins?

**Decision:** Relay-assigned sequences (Dec 30, 2025)
- Relay atomically assigns sequences via `MAX(sequence_number) + 1`
- `UNIQUE(jar_id, sequence_number)` constraint enforces one sequence per slot
- Conflicts are **impossible** (database atomicity guarantees)
- Client sends receipt → relay assigns sequence → broadcasts to members
- All clients apply receipts in relay-assigned order (deterministic convergence)

### 2. Sequence Number Scope

**Question:** Are sequence numbers global or per-jar?

**Decision:** Per-jar (simpler, more intuitive)
- Each jar has independent sequence: 1, 2, 3...
- Global would require coordination across all jars

### 3. Offline Window

**Question:** How long should offline queue persist?

**Recommendation:** 7 days (balances UX vs complexity)
- Most users will reconnect within hours/days
- 7 days is long enough to be generous
- >7 days likely means device lost, reset, etc.

### 4. Tombstone Expiration

**Question:** Should tombstones expire?

**Recommendation:** Never (disk is cheap, safety is valuable)
- Tombstones are small (just jar_id + timestamp)
- Preventing resurrection is critical
- No good reason to delete them

### 5. Receipt Backfill Strategy

**Question:** If missing 100 receipts, fetch all at once or paginated?

**Recommendation:** Fetch all (up to reasonable limit like 1000)
- Simpler implementation
- Jar operations are lightweight (not like buds)
- Worst case: 1000 receipts * 1KB each = 1MB (totally fine)

---

## Success Metrics

**Technical:**
- [ ] 95%+ receipt delivery rate
- [ ] Sequence gaps detected and recovered
- [ ] Zero tombstone violations
- [ ] Replay attacks prevented

**UX:**
- [ ] Jar invites clear and intuitive
- [ ] Shared buds land in correct jar >99%
- [ ] Toasts helpful, not spammy
- [ ] Sync state visible ("Syncing...")

**Performance:**
- [ ] Receipt processing <500ms
- [ ] Backfill request <2s
- [ ] Queue processing <1s per 10 receipts

---

## Deferred to Phase 11+

- Delivery receipts ("Seen by 3/5")
- Jar snapshots (state compaction)
- Soft delete (30-day retention)
- Undo for destructive operations
- Invite expiration (7 days)
- Operation merge (500 renames → 1)

---

Ready to implement? This is coherent and handles the critical edge cases. Not perfect, but production-ready.

🚀
