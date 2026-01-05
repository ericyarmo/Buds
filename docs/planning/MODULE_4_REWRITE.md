# Module 4: Gap Detection & Queueing - REWRITTEN (Jan 4, 2026)

**Status:** Ready for implementation
**Estimated:** 4-5 hours
**Goal:** Handle imperfect networks (packet loss, out-of-order delivery, incomplete backfills)

---

## Architecture - Distributed Systems Semantics

### The Problem

**Network Reality:**
- Receipts arrive out-of-order (seq 1, 3, 2, 4)
- Receipts get lost (seq 1, 2, 4 - missing 3)
- Backfills can be incomplete (request 3-10, get only 3-5)
- Multiple gaps possible (seq 1, 5, 9 - missing 2-4 and 6-8)

**What We Must Handle:**
1. Gap detection (expected seq != actual seq)
2. Backfill requests for missing receipts
3. Queueing out-of-order receipts
4. Incomplete backfill recovery
5. Jar creation before jar exists (first receipt = jar.created)
6. Recursion prevention (backfill triggering more gaps)

---

## Solution Architecture

### State Machine Approach

**3 Processing Paths:**

```
1. HAPPY PATH (seq matches expected)
   → Verify → Apply → Mark Processed → Try Queue

2. GAP DETECTED (seq > expected)
   → Verify → Queue → Request Backfill → Wait

3. LATE/DUPLICATE (seq < expected)
   → Skip (already processed higher sequences)
```

**Key Insight:** Separate backfill processing from normal processing to prevent recursion.

---

## Implementation Plan

### Part 1: Add QueuedReceipt Model (GRDB-compatible)

**Location:** `Core/JarSyncManager.swift` (bottom of file)

```swift
struct QueuedReceipt: Codable, FetchableRecord, PersistableRecord {
    let id: String
    let jarID: String
    let sequenceNumber: Int
    let receiptCID: String
    let receiptData: Data
    let signature: Data
    let senderDID: String
    let parentCID: String?
    let queuedAt: TimeInterval

    static let databaseTableName = "jar_receipt_queue"

    enum CodingKeys: String, CodingKey {
        case id
        case jarID = "jar_id"
        case sequenceNumber = "sequence_number"
        case receiptCID = "receipt_cid"
        case receiptData = "receipt_data"
        case signature
        case senderDID = "sender_did"
        case parentCID = "parent_cid"
        case queuedAt = "queued_at"
    }
}
```

**Why:** GRDB needs `FetchableRecord` + `PersistableRecord` for DB operations.

---

### Part 2: Update Database Schema (Migration v9)

**Add columns to jar_receipt_queue:**

```sql
ALTER TABLE jar_receipt_queue ADD COLUMN signature BLOB;
ALTER TABLE jar_receipt_queue ADD COLUMN sender_did TEXT;
```

**Why:** Need to store full envelope for verification on dequeue.

**Location:** Create `migrations/0009_add_queue_signature.sql` in buds-relay repo

---

### Part 3: Rewrite processEnvelope() with Gap Detection

**Replace Module 3 version with:**

```swift
func processEnvelope(_ envelope: RelayEnvelope, skipGapDetection: Bool = false) async throws {
    // 1. Replay protection
    guard !(try await isAlreadyProcessed(envelope.receiptCID)) else {
        print("⏭️ Skipping already processed: \(envelope.receiptCID)")
        return
    }

    // 2. Tombstone check
    guard !(try await tombstoneRepo.isTombstoned(envelope.jarID)) else {
        print("🪦 Skipping tombstoned jar: \(envelope.jarID)")
        return
    }

    // 3. Gap detection (ONLY if not backfill processing)
    if !skipGapDetection {
        let lastSeq = try await getLastSequence(jarID: envelope.jarID)
        let expectedSeq = lastSeq + 1

        if envelope.sequenceNumber > expectedSeq {
            // GAP DETECTED - Missing receipts [expectedSeq ... sequenceNumber - 1]
            print("⚠️ Gap: expected \(expectedSeq), got \(envelope.sequenceNumber)")

            // Verify BEFORE queueing (important!)
            try await verifyReceipt(envelope)

            // Queue this receipt (can't process yet)
            try await queueReceipt(envelope, reason: "sequence_gap")

            // Request missing receipts
            try await requestBackfill(
                jarID: envelope.jarID,
                from: expectedSeq,
                to: envelope.sequenceNumber - 1
            )

            return
        }

        if envelope.sequenceNumber < expectedSeq {
            // LATE/DUPLICATE - Already processed higher sequences
            print("⏪ Late receipt: expected \(expectedSeq), got \(envelope.sequenceNumber)")
            return
        }
    }

    // 4. HAPPY PATH - Process normally
    try await verifyReceipt(envelope)
    try await applyReceipt(envelope)
    try await markProcessed(
        receiptCID: envelope.receiptCID,
        jarID: envelope.jarID,
        sequenceNumber: envelope.sequenceNumber
    )

    print("✅ Processed receipt seq=\(envelope.sequenceNumber)")

    // 5. Try to process queued receipts
    try await processQueuedReceipts(jarID: envelope.jarID)
}
```

**Key Changes:**
- ✅ Added `skipGapDetection` flag to prevent recursion
- ✅ Verify BEFORE queueing (not after)
- ✅ Request backfill AFTER queueing (order matters)

---

### Part 4: Implement Queueing Functions

```swift
func queueReceipt(_ envelope: RelayEnvelope, reason: String) async throws {
    let queued = QueuedReceipt(
        id: UUID().uuidString,
        jarID: envelope.jarID,
        sequenceNumber: envelope.sequenceNumber,
        receiptCID: envelope.receiptCID,
        receiptData: envelope.receiptData,
        signature: envelope.signature,
        senderDID: envelope.senderDID,
        parentCID: envelope.parentCID,
        queuedAt: Date().timeIntervalSince1970
    )

    try await db.writeAsync { db in
        try queued.insert(db)
    }

    print("📥 Queued receipt \(envelope.receiptCID) (reason: \(reason))")
}

func processQueuedReceipts(jarID: String) async throws {
    let queued = try await getQueuedReceipts(jarID: jarID)
    guard !queued.isEmpty else { return }

    print("🔄 Processing \(queued.count) queued receipts for \(jarID)")

    // Sort by sequence (ascending)
    let sorted = queued.sorted { $0.sequenceNumber < $1.sequenceNumber }

    // Track last processed sequence (optimize - get once, not per iteration)
    var lastSeq = try await getLastSequence(jarID: jarID)

    for queuedReceipt in sorted {
        let expectedSeq = lastSeq + 1

        if queuedReceipt.sequenceNumber == expectedSeq {
            // Ready to process!
            print("✅ Processing queued seq=\(queuedReceipt.sequenceNumber)")

            // Reconstruct envelope
            let envelope = RelayEnvelope(
                jarID: queuedReceipt.jarID,
                sequenceNumber: queuedReceipt.sequenceNumber,
                receiptCID: queuedReceipt.receiptCID,
                receiptData: queuedReceipt.receiptData,
                signature: queuedReceipt.signature,
                senderDID: queuedReceipt.senderDID,
                receivedAt: 0,
                parentCID: queuedReceipt.parentCID
            )

            // Process WITHOUT gap detection (we already know sequence is correct)
            try await processEnvelope(envelope, skipGapDetection: true)

            // Remove from queue
            try await removeFromQueue(queuedReceipt.id)

            // Update tracking
            lastSeq = queuedReceipt.sequenceNumber
        } else {
            // Still missing earlier receipts
            print("⏸️ Waiting for seq=\(expectedSeq), have \(queuedReceipt.sequenceNumber)")
            break  // Can't process rest yet
        }
    }
}
```

**Key Changes:**
- ✅ Store full envelope in queue (signature + senderDID)
- ✅ Track `lastSeq` outside loop (optimization)
- ✅ Call `processEnvelope(..., skipGapDetection: true)` on dequeue (prevents recursion)

---

### Part 5: Implement Backfill with Recursion Prevention

```swift
func requestBackfill(jarID: String, from: Int, to: Int) async throws {
    print("🔁 Requesting backfill: \(jarID) seq=\(from)-\(to)")

    // Call relay API
    let envelopes = try await RelayClient.shared.getJarReceipts(
        jarID: jarID,
        from: from,
        to: to
    )

    print("📬 Received \(envelopes.count) backfilled receipts")

    guard !envelopes.isEmpty else {
        print("⚠️ Backfill returned no receipts - possible relay issue")
        return
    }

    // Check backfill completeness
    let expectedCount = to - from + 1
    if envelopes.count < expectedCount {
        print("⚠️ Incomplete backfill: expected \(expectedCount), got \(envelopes.count)")
        // Continue processing what we got - queue will handle remaining gaps
    }

    // Process backfilled receipts WITH gap detection DISABLED
    // (Prevents recursion - if backfill has gaps, they'll be queued normally)
    for envelope in envelopes.sorted(by: { $0.sequenceNumber < $1.sequenceNumber }) {
        try await processEnvelope(envelope, skipGapDetection: true)
    }

    print("✅ Backfill complete, processed \(envelopes.count) receipts")
}
```

**Key Changes:**
- ✅ Pass `skipGapDetection: true` to prevent recursion
- ✅ Warn on incomplete backfills (but continue processing)
- ✅ Empty backfill handled gracefully

---

### Part 6: Handle Jar Creation Edge Case

```swift
func getLastSequence(jarID: String) async throws -> Int {
    let seq = try await db.readAsync { db in
        try Int.fetchOne(
            db,
            sql: "SELECT last_sequence_number FROM jars WHERE id = ?",
            arguments: [jarID]
        )
    }

    // Handle jar that doesn't exist yet
    // (First receipt will be jar.created with seq=1)
    return seq ?? 0
}
```

**Key Changes:**
- ✅ Returns `0` if jar doesn't exist (expects seq=1 for jar.created)
- ✅ Handles nil gracefully

---

### Part 7: Helper Functions

```swift
func getQueuedReceipts(jarID: String) async throws -> [QueuedReceipt] {
    try await db.readAsync { db in
        try QueuedReceipt
            .filter(Column("jar_id") == jarID)
            .order(Column("sequence_number").asc)
            .fetchAll(db)
    }
}

func removeFromQueue(_ queueID: String) async throws {
    try await db.writeAsync { db in
        try QueuedReceipt
            .filter(Column("id") == queueID)
            .deleteAll(db)
    }
}
```

**Key Changes:**
- ✅ Use GRDB query builder (cleaner than raw SQL)
- ✅ Works with `QueuedReceipt` model

---

## Edge Cases Handled

| Scenario | Behavior |
|----------|----------|
| **Receive 1,2,4** | Process 1,2 → detect gap → queue 4 → request 3 → process 3 → process queued 4 |
| **Receive 1,4,2,3** | Process 1 → gap → queue 4 → request 2-3 → process 2,3 → process queued 4 |
| **Backfill incomplete** | Request 3-10, get 3-5 → process 3-5 → queue unblocks partially → request 6-10 on next gap |
| **Backfill empty** | Warn, continue (queue stays blocked until next receipt triggers new backfill) |
| **Duplicate receipt** | Replay protection skips (already in processed_jar_receipts) |
| **Late receipt** | Skip (seq < expected) |
| **Jar doesn't exist** | `lastSeq = 0`, expect seq=1 (jar.created) |
| **Backfill triggers gap** | Gap detection disabled on backfill → won't recurse |
| **Multiple gaps** | Each gap triggers separate backfill → eventually converges |

---

## Testing Strategy

**Manual Test Cases:**

1. **Happy path:** Send 1,2,3,4 in order → all process immediately
2. **Single gap:** Send 1,2,4 → 4 queued → send 3 → 3,4 both process
3. **Out-of-order:** Send 1,4,2,3 → 4 queued → 2,3 backfilled → all process in order
4. **Incomplete backfill:** Send 1,10 → request 2-9 → get only 2-5 → process 2-5 → still waiting for 6-9
5. **Jar creation:** Send jar.created as first receipt → lastSeq=0, expect seq=1 → works

---

## Success Criteria

- ✅ All receipts processed in relay sequence order
- ✅ No duplicate processing (replay protection)
- ✅ Queue eventually empties when all dependencies satisfied
- ✅ Incomplete backfills handled gracefully
- ✅ No infinite recursion (skipGapDetection flag)
- ✅ Jar creation works (lastSeq=0 case)
- ✅ GRDB queries compile and run

---

## Estimated Time: 4-5 hours

**Breakdown:**
- Migration v9 (relay): 15 min
- QueuedReceipt model: 30 min
- Rewrite processEnvelope: 1h
- Queueing functions: 1h
- Backfill with recursion prevention: 1h
- Helpers + edge cases: 1h
- Testing + debugging: 30-60 min

---

## Files to Modify

1. **`Buds/Core/JarSyncManager.swift`** (~200 lines added)
   - Add QueuedReceipt model
   - Rewrite processEnvelope with gap detection
   - Add queueing functions
   - Add backfill with recursion prevention
   - Add helpers

2. **`buds-relay/migrations/0009_add_queue_signature.sql`** (new file)
   - Add signature, sender_did columns to jar_receipt_queue

---

**Ready to implement. This is physics. Let's do this. 🚀**
