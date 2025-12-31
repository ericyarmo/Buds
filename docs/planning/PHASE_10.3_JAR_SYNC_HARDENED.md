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
- ✅ Causal ordering with `parent_cid` chains
- ✅ Sequence numbers for gap detection
- ✅ Tombstones for deletion safety
- ✅ Replay protection with processed receipt tracking
- ✅ Server-side membership validation
- ✅ Offline conflict detection

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

### 1. Receipt Structure (All Jar Receipts)

**Add causal ordering fields:**

```swift
// Common fields for ALL jar receipts
struct JarReceiptBase: Codable {
    let jarID: String              // Which jar
    let sequenceNumber: Int        // Monotonic per jar (1, 2, 3...)
    let parentCID: String?         // Previous operation CID (causal chain)
    let timestamp: Int64           // Local time (UX only, not for ordering)
    let senderDID: String          // Who created this receipt
}
```

**Why:**
- `sequenceNumber`: Detect missing receipts (gap from 5 → 7 means 6 is missing)
- `parentCID`: Causal chain (can't process receipt N+1 until receipt N arrives)
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

## Implementation Modules (Updated with Crypto)

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
1. Generate safety number:
   ```swift
   func generateSafetyNumber(myDID: String, theirDID: String, theirDevices: [Device]) -> String {
       let combined = myDID + theirDID + theirDevices.map { $0.pubkeyEd25519 }.joined()
       let hash = SHA256.hash(data: combined.data(using: .utf8)!)
       return formatAsGroups(hash.prefix(30))  // "12345 67890 12345..."
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
   }
   ```

3. SafetyNumberView sheet:
   - Show full safety number
   - QR code (optional)
   - Instructions: "Compare with friend's device"

**Success criteria:**
- Safety number generated correctly
- UI shows in member detail
- Clear instructions for verification

---

### Module 0.6: Relay Infrastructure (3-4 hours)

**Critical: Server-side validation before any client work**

**Files to create:**
- `buds-relay/src/jar_validation.ts` - Membership validation logic
- `buds-relay/src/jar_storage.ts` - Jar state tracking

**Tasks:**
1. Add `jar_members` table to relay D1 database
   ```sql
   CREATE TABLE jar_members (
       jar_id TEXT NOT NULL,
       member_did TEXT NOT NULL,
       status TEXT NOT NULL,  -- 'active' | 'pending' | 'removed'
       added_at INTEGER NOT NULL,
       PRIMARY KEY (jar_id, member_did)
   );
   ```

2. Update `/api/messages/send` endpoint:
   - Validate sender is active member of jar
   - Filter recipients to only active members
   - Reject if sender not a member (403)

3. New endpoint: `/api/jars/{jar_id}/receipts?from={seq}&to={seq}`
   - Return receipts for backfill
   - Require authentication
   - Only return if requester is active member

4. New endpoint: `/api/jars/{jar_id}/sync`
   - Accept jar membership updates from owner
   - Store in relay database (authoritative state)
   - Called when owner adds/removes members

**Success criteria:**
- Relay rejects receipts from non-members
- Backfill endpoint returns missing receipts
- Membership sync updates relay state

### Module 1: Receipt Types & Sequencing (3-4 hours)

**Files to create:**
- `Core/Models/JarReceipts.swift` - All jar payload structs with sequencing

**Files to modify:**
- `Core/ChaingeKernel/ReceiptType.swift` - Add jar receipt types
- `Core/ChaingeKernel/ReceiptCanonicalizer.swift` - Encode/decode with sequence numbers

**Tasks:**
1. Define JarReceiptBase with sequence + parent_cid
2. Define 7 jar payload structs inheriting base
3. Add canonicalization support (CBOR encoding preserves field order)
4. Add sequence number generation (fetch last seq + 1)

**Success criteria:**
- Can generate jar.created with seq=1, parent_cid=nil
- Can generate jar.member_added with seq=2, parent_cid=<jar.created CID>
- Encode/decode round-trips correctly

### Module 2: Database Migration (2-3 hours)

**Files to modify:**
- `Core/Database/Database.swift` - Migration v8

**Tasks:**
1. Create processed_jar_receipts table
2. Create jar_tombstones table
3. Create jar_receipt_queue table
4. Add last_sequence_number to jars table
5. Backfill Solo jar with owner_did, sequence=0

**Success criteria:**
- Fresh install: v8 schema created
- Existing install: v7 → v8 migration succeeds
- No data loss

### Module 3: Tombstone & Replay Protection (2-3 hours)

**Files to create:**
- `Core/Database/Repositories/JarTombstoneRepository.swift`

**Files to modify:**
- `Core/JarManager.swift` - Create tombstone on delete
- `Core/JarSyncManager.swift` - Check tombstone before processing

**Tasks:**
1. Implement tombstone creation:
   ```swift
   func deleteJar(_ jarID: String) async throws {
       // Soft delete: create tombstone
       try await JarTombstoneRepository.shared.create(
           jarID: jarID,
           jarName: jar.name,
           deletedByDID: ownerDID
       )

       // Delete local jar
       try await JarRepository.shared.delete(jarID)
   }
   ```

2. Implement replay protection:
   ```swift
   func isAlreadyProcessed(receiptCID: String) async throws -> Bool {
       try await db.readAsync { db in
           try Int.fetchOne(db, sql: "SELECT 1 FROM processed_jar_receipts WHERE receipt_cid = ?", arguments: [receiptCID]) != nil
       }
   }
   ```

3. Check tombstone before processing any jar receipt

**Success criteria:**
- Delete jar → tombstone created
- Late receipts for deleted jar rejected
- Receipt replays detected and skipped

### Module 4: Dependency Resolution & Queueing (4-5 hours) ← MOST COMPLEX

**Files to create:**
- `Core/JarSyncManager.swift` - New manager for jar receipt processing

**Tasks:**
1. Implement receipt queueing for missing dependencies:
   ```swift
   func queueReceipt(_ receipt: JarReceipt, reason: String) async throws {
       try await db.writeAsync { db in
           let queue = JarReceiptQueue(
               id: UUID(),
               jarID: receipt.jarID,
               receiptCID: receipt.cid,
               parentCID: receipt.parentCID,
               sequenceNumber: receipt.sequenceNumber,
               receiptData: receipt.rawCBOR,
               queuedAt: Date()
           )
           try queue.insert(db)
       }
   }
   ```

2. Implement sequence gap detection + backfill request:
   ```swift
   func processReceipt(_ receipt: JarReceipt) async throws {
       let lastSeq = try await getLastSequence(jarID: receipt.jarID)
       let expectedSeq = lastSeq + 1

       if receipt.sequenceNumber > expectedSeq {
           // Missing receipts [expectedSeq ... receipt.sequenceNumber - 1]
           try await requestBackfill(jarID: receipt.jarID, from: expectedSeq, to: receipt.sequenceNumber - 1)
           try await queueReceipt(receipt, reason: "sequence_gap")
           return
       }

       // Process normally
       try await applyReceipt(receipt)
   }
   ```

3. Implement queue processing (after dependencies satisfied):
   ```swift
   func processQueuedReceipts(jarID: String) async throws {
       let queued = try await getQueuedReceipts(jarID: jarID)

       for queuedReceipt in queued.sorted(by: { $0.sequenceNumber < $1.sequenceNumber }) {
           // Check if can process now
           if try await canProcess(queuedReceipt) {
               try await processReceipt(queuedReceipt)
               try await removeFromQueue(queuedReceipt.id)
           }
       }
   }
   ```

**Success criteria:**
- Out-of-order receipts queued
- Missing receipts requested from relay
- Queued receipts processed in order once deps satisfied

### Module 5: Jar Creation with Sync (2-3 hours)

**Files to modify:**
- `Core/JarManager.swift` - Generate jar.created receipt
- `Core/JarSyncManager.swift` - Process jar.created

**Tasks:**
1. Update createJar to generate receipt:
   ```swift
   func createJar(name: String, description: String?) async throws -> Jar {
       // Create jar locally
       let jar = try await JarRepository.shared.createJar(...)

       // Generate jar.created receipt (seq=1, parent_cid=nil)
       let receipt = try await ReceiptManager.shared.createJarCreatedReceipt(
           jarID: jar.id,
           jarName: name,
           jarDescription: description,
           ownerDID: currentDID,
           sequenceNumber: 1,
           parentCID: nil
       )

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

**Success criteria:**
- Create jar locally → jar.created receipt generated
- Receive jar.created → jar created as pending

### Module 6: Member Invite Flow (4-5 hours)

**Files to modify:**
- `Core/JarManager.swift` - Add member with sync
- `Core/JarSyncManager.swift` - Process member_added/invite_accepted

**Tasks:**
1. Update addMember:
   - Lookup DID via relay
   - Get member devices
   - Generate jar.member_added receipt (increment seq)
   - Send jar.created + jar.member_added to new member
   - Send jar.member_added to existing members
   - **Call relay sync endpoint** to update authoritative state

2. Process jar.member_added on receive:
   - If you're the new member: store invite
   - If you're existing member: add to jar_members

3. Implement accept invite:
   - Generate jar.invite_accepted receipt
   - Send to owner + all members
   - Update local status: pending → active

**Success criteria:**
- Add member → receipts sent to member + existing members
- Member receives invite → shows in UI
- Member accepts → all members notified
- **Relay membership state updated**

### Module 7: Bud Sharing with jar_id (2-3 hours)

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

### Module 8: Offline Hardening (3-4 hours)

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

### Module 9: UI Components (3-4 hours)

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

### Module 10: Notifications & Polish (2-3 hours)

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

### 1. Conflict Resolution Strategy

**Question:** When two operations have same sequence number (network partition), which wins?

**Options:**
- A) First-to-relay wins (relay assigns final sequence)
- B) Owner's device_id as tiebreaker (deterministic)
- C) Reject conflict, require manual resolution

**Recommendation:** A (relay is source of truth)

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
