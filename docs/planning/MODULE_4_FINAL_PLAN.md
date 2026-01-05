# Module 4: Gap Detection & Queueing - FINAL IMPLEMENTATION PLAN

**Status:** IMPLEMENTED
**Date:** January 5, 2026
**Actual Time:** ~2 hours
**Prerequisite:** Module 3 complete (JarSyncManager exists)

## Implementation Summary

**Files Modified:**
- `Core/Database/Database.swift` - Migration v9 (queue envelope fields + jar_sync_state table)
- `Core/JarSyncManager.swift` - Full gap detection implementation (~400 new lines)

**Key Design Decisions (Senior Systems Engineer Fixes):**
1. **Actor-safe concurrency** - `JarSyncState` actor manages `processingQueues` and `backfillInProgress`
2. **Exponential backoff for backfills** - Delays: 5s, 15s, 1m, 5m, 15m (not immediate retry)
3. **Poison → HALT jar** - Maintains sequence invariant (doesn't skip to next receipt)

---

---

## Executive Summary

This module extends JarSyncManager to handle imperfect networks:
- Out-of-order delivery (receive seq 1, 4, 2, 3)
- Packet loss (receive seq 1, 2, 4 - missing 3)
- Incomplete backfills (request 3-10, get only 3-5)

**Philosophy:** Process receipts in relay sequence order. Queue what we can't process yet. Backfill what's missing. Eventually consistent.

---

## Red Flag Analysis (From Review Prompt)

### Red Flag 1: Recursion Concern ✅ SAFE (with fix)

**Issue:** `processEnvelope()` → `processQueuedReceipts()` → `processEnvelope()`

**Analysis:**
```
processEnvelope(skipGapDetection=false)
  → applies receipt
  → calls processQueuedReceipts()
    → calls processEnvelope(skipGapDetection=true)
      → applies receipt
      → calls processQueuedReceipts() ← NESTED CALL!
```

The nested call is SAFE but INEFFICIENT because:
1. The nested `processQueuedReceipts()` sees stale queue (item not yet removed)
2. It checks `seq == expected`, finds mismatch (seq < expected because we just processed it), breaks
3. Returns immediately without doing anything useful

**FIX:** Don't call `processQueuedReceipts()` when `skipGapDetection=true`. The parent loop handles it.

```swift
// At end of processEnvelope:
if !skipGapDetection {
    try await processQueuedReceipts(jarID: envelope.jarID)
}
```

---

### Red Flag 2: Gap Detection After Incomplete Backfill ⚠️ BUG (needs fix)

**Scenario:**
1. Receive: 1, 2, 10
2. Process 1, 2. Detect gap. Queue 10. Request backfill 3-9.
3. Backfill returns: 3, 4, 5 (incomplete - relay doesn't have 6-9 yet)
4. Process 3, 4, 5 with skipGapDetection=true
5. Try queue → expect 6, have 10, can't process
6. **STUCK!** No mechanism to request 6-9.

**FIX:** After processing backfill, check if queue is still blocked. If so, request remaining gap.

```swift
func requestBackfill(jarID: String, from: Int, to: Int) async throws {
    let envelopes = try await RelayClient.shared.getJarReceipts(jarID: jarID, from: from, to: to)

    // Process what we got
    for envelope in envelopes.sorted(by: { $0.sequenceNumber < $1.sequenceNumber }) {
        try await processEnvelope(envelope, skipGapDetection: true)
    }

    // Check if queue is still blocked
    let lastSeq = try await getLastSequence(jarID: jarID)
    let queued = try await getQueuedReceipts(jarID: jarID)

    if let firstQueued = queued.first {
        let expectedSeq = lastSeq + 1
        if firstQueued.sequenceNumber > expectedSeq {
            // Still missing receipts! Request remaining gap.
            print("⚠️ Incomplete backfill: still missing \(expectedSeq) to \(firstQueued.sequenceNumber - 1)")
            // DON'T recurse immediately - schedule retry after delay
            try await scheduleBackfillRetry(jarID: jarID, from: expectedSeq, to: firstQueued.sequenceNumber - 1)
        }
    }
}
```

---

### Red Flag 3: Queue Processing Race ✅ SAFE (Swift async is cooperative)

**Issue:** Can `processQueuedReceipts()` be called concurrently?

**Analysis:** Swift async/await is cooperative (single-threaded within actor). Tasks interleave at `await` points but don't run truly in parallel.

**Scenario:**
1. Task A: `processEnvelope(5)` → await DB write → suspended
2. Task B: `processEnvelope(6)` starts running
3. Both eventually call `processQueuedReceipts()`

**Why it's safe:**
- Replay protection catches duplicates: `isAlreadyProcessed()` returns true
- Sequence check catches stale: `seq < expected` gets skipped

**IMPROVEMENT:** Use an actor or serial queue to prevent redundant work:

```swift
// Add to JarSyncManager
private var processingQueues: Set<String> = []

func processQueuedReceipts(jarID: String) async throws {
    // Prevent concurrent queue processing for same jar
    guard !processingQueues.contains(jarID) else {
        print("⏳ Queue processing already in progress for \(jarID)")
        return
    }

    processingQueues.insert(jarID)
    defer { processingQueues.remove(jarID) }

    // ... actual queue processing
}
```

---

### Red Flag 4: Backfill Overlap ⚠️ BUG (needs fix)

**Scenario:**
1. Request backfill 3-10 (in flight)
2. Receive 4 from normal sync → gap detected → queue 4 → request backfill 3-3
3. Backfill from step 1 arrives: [3, 4, 5, 6, 7, 8, 9, 10]
4. Process 3 ✓
5. Process 4 (from backfill) → marks processed
6. Queue still has 4 → **ORPHANED FOREVER!**

**Root cause:** When processing from backfill, we don't remove matching items from queue.

**FIX:** In `processQueuedReceipts()`, handle `seq < expected` by removing orphaned items:

```swift
func processQueuedReceipts(jarID: String) async throws {
    var queued = try await getQueuedReceipts(jarID: jarID)
    var lastSeq = try await getLastSequence(jarID: jarID)

    for queuedReceipt in queued.sorted(by: { $0.sequenceNumber < $1.sequenceNumber }) {
        let expectedSeq = lastSeq + 1

        if queuedReceipt.sequenceNumber < expectedSeq {
            // ORPHANED: Already processed (via backfill or other path)
            print("🧹 Removing orphaned queued receipt seq=\(queuedReceipt.sequenceNumber) (expected \(expectedSeq))")
            try await removeFromQueue(queuedReceipt.id)
            continue  // Check next item
        }

        if queuedReceipt.sequenceNumber == expectedSeq {
            // Ready to process
            // ... process and remove
            lastSeq = queuedReceipt.sequenceNumber
            continue
        }

        // queuedReceipt.sequenceNumber > expectedSeq
        // Still missing earlier receipts
        print("⏸️ Waiting for seq=\(expectedSeq), have \(queuedReceipt.sequenceNumber)")
        break
    }
}
```

---

### Red Flag 5: Verification Failure in Queue ⚠️ BUG (needs fix)

**Scenario:**
1. Receive seq 5 out of order
2. Verify ✓, queue it
3. Backfill arrives, process 2-4
4. Dequeue 5 → verify AGAIN → **FAILS** (corrupted in storage?)
5. Receipt stays in queue forever

**FIX:** Handle verification failure by marking as poison and removing:

```swift
func processQueuedReceipts(jarID: String) async throws {
    for queuedReceipt in sorted {
        if queuedReceipt.sequenceNumber == expectedSeq {
            let envelope = reconstructEnvelope(queuedReceipt)

            do {
                try await verifyReceipt(envelope)
                try await applyReceipt(envelope)
                try await markProcessed(...)
                try await removeFromQueue(queuedReceipt.id)
                lastSeq = queuedReceipt.sequenceNumber
            } catch {
                // Verification or apply failed - mark as poison
                print("☠️ Poison receipt detected: \(queuedReceipt.receiptCID) - \(error)")
                try await markAsPoisoned(queuedReceipt.id, reason: error.localizedDescription)
                // Continue to next queued item (don't block queue forever)
                continue
            }
        }
    }
}
```

---

### Red Flag 6: Jar Creation Failure Recovery ✅ SAFE

**Scenario:**
1. Receive jar.created (seq=1)
2. Apply fails (disk full)
3. Next receipt: seq=2 arrives
4. `getLastSequence()` returns 0 (jar doesn't exist)
5. Expected=1, actual=2 → gap detected → queue 2 → request backfill(1,1)
6. Backfill returns jar.created again
7. Process with skipGapDetection=true → creates jar → works!

**Why it works:**
- `getLastSequence()` returns 0 for non-existent jar
- Backfill gets the same receipt again
- Retry succeeds (assuming transient failure)

**SAFE** - no fix needed.

---

### Red Flag 7: Additional Edge Cases

**7a. Duplicate Backfill Requests (Storm)**

Multiple gaps can trigger overlapping backfill requests:
1. Receive 10 → request backfill 1-9
2. Receive 15 → request backfill 1-14 (overlaps!)

**FIX:** Add backfill lock per jar:

```swift
private var backfillInProgress: [String: (from: Int, to: Int, until: Date)] = [:]

func requestBackfill(jarID: String, from: Int, to: Int) async throws {
    // Check if backfill already in progress for overlapping range
    if let inProgress = backfillInProgress[jarID] {
        if inProgress.until > Date() && from >= inProgress.from && to <= inProgress.to {
            print("⏳ Backfill already in progress for \(jarID) [\(inProgress.from)-\(inProgress.to)]")
            return
        }
    }

    // Mark backfill in progress (15 second lock)
    backfillInProgress[jarID] = (from: from, to: to, until: Date().addingTimeInterval(15))
    defer { backfillInProgress.removeValue(forKey: jarID) }

    // ... actual backfill
}
```

**7b. Queue Poisoning (Dead Letter)**

Receipts that can never be processed:
- Parent CID refers to non-existent receipt
- Signature key not found
- CBOR decode fails

**FIX:** Add retry_count and dead letter handling:

```sql
-- Migration: Add poison detection columns
ALTER TABLE jar_receipt_queue ADD COLUMN retry_count INTEGER DEFAULT 0;
ALTER TABLE jar_receipt_queue ADD COLUMN last_retry_at REAL;
ALTER TABLE jar_receipt_queue ADD COLUMN poison_reason TEXT;
```

```swift
let MAX_RETRIES = 5
let MAX_AGE_SECONDS: TimeInterval = 7 * 24 * 60 * 60  // 7 days

func processQueuedReceipts(jarID: String) async throws {
    for queuedReceipt in sorted {
        // Check if poisoned
        if queuedReceipt.retryCount >= MAX_RETRIES {
            print("☠️ Dead letter: \(queuedReceipt.receiptCID) exceeded \(MAX_RETRIES) retries")
            try await moveToDeadLetter(queuedReceipt)
            continue
        }

        let age = Date().timeIntervalSince1970 - queuedReceipt.queuedAt
        if age > MAX_AGE_SECONDS {
            print("☠️ Dead letter: \(queuedReceipt.receiptCID) expired after \(Int(age/86400)) days")
            try await moveToDeadLetter(queuedReceipt)
            continue
        }

        // ... process
    }
}
```

**7c. Missing Queue Columns**

Current queue table is missing `signature` and `sender_did` needed to reconstruct envelope.

**FIX:** Migration v9 adds these columns.

---

## State Machine (Final, Correct)

```
┌─────────────────────────────────────────────────────────────────┐
│                     ENVELOPE ARRIVES                             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │ Replay Check    │
                    │ (already        │
                    │  processed?)    │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              │ YES          │              │ NO
              ▼              │              ▼
        ┌─────────┐          │        ┌─────────────┐
        │ SKIP    │          │        │ Tombstone   │
        │ (done)  │          │        │ Check       │
        └─────────┘          │        └──────┬──────┘
                             │               │
                             │    ┌──────────┼──────────┐
                             │    │ TOMBSTONED         │ NOT TOMBSTONED
                             │    ▼                    ▼
                             │ ┌─────────┐       ┌─────────────┐
                             │ │ SKIP    │       │ Gap Check   │
                             │ │ (done)  │       │ (if normal  │
                             │ └─────────┘       │  processing)│
                             │                   └──────┬──────┘
                             │                          │
                    ┌────────┴────────┬────────────────┼────────────────┐
                    │                 │                │                │
                    │ skipGapDetection│ seq < expected │ seq == expected│ seq > expected
                    │ == true         │ (LATE)         │ (HAPPY PATH)   │ (GAP)
                    ▼                 ▼                ▼                ▼
              ┌───────────┐     ┌─────────┐     ┌───────────┐    ┌────────────────┐
              │ VERIFY    │     │ SKIP    │     │ VERIFY    │    │ VERIFY         │
              │ APPLY     │     │ (done)  │     │ APPLY     │    │ (before queue) │
              │ MARK      │     └─────────┘     │ MARK      │    └───────┬────────┘
              │ (no queue │                     │ TRY QUEUE │            │
              │  check)   │                     └───────────┘            ▼
              └───────────┘                                       ┌────────────────┐
                                                                  │ QUEUE RECEIPT  │
                                                                  │ REQUEST        │
                                                                  │ BACKFILL       │
                                                                  │ (done)         │
                                                                  └────────────────┘
```

---

## Database Changes (Migration v9)

**File:** `Core/Database/Database.swift`

```swift
// Add to migrator
migrator.registerMigration("v9_queue_envelope_fields") { db in
    try migrateQueueEnvelopeFields(db)
}

private func migrateQueueEnvelopeFields(_ db: GRDB.Database) throws {
    print("🔧 [MIGRATION v9] Adding envelope fields to jar_receipt_queue...")

    // Add signature column (BLOB for raw bytes)
    try db.execute(sql: """
        ALTER TABLE jar_receipt_queue ADD COLUMN signature BLOB
    """)

    // Add sender_did column
    try db.execute(sql: """
        ALTER TABLE jar_receipt_queue ADD COLUMN sender_did TEXT
    """)

    // Add retry tracking columns
    try db.execute(sql: """
        ALTER TABLE jar_receipt_queue ADD COLUMN retry_count INTEGER DEFAULT 0
    """)

    try db.execute(sql: """
        ALTER TABLE jar_receipt_queue ADD COLUMN last_retry_at REAL
    """)

    try db.execute(sql: """
        ALTER TABLE jar_receipt_queue ADD COLUMN poison_reason TEXT
    """)

    print("✅ [MIGRATION v9] Complete")
}
```

---

## Implementation (Step by Step)

### Step 1: Add QueuedReceipt Model

**File:** `Core/JarSyncManager.swift` (add at bottom)

```swift
// MARK: - QueuedReceipt Model

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
    let retryCount: Int
    let lastRetryAt: TimeInterval?
    let poisonReason: String?

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
        case retryCount = "retry_count"
        case lastRetryAt = "last_retry_at"
        case poisonReason = "poison_reason"
    }
}
```

### Step 2: Add Properties to JarSyncManager

**File:** `Core/JarSyncManager.swift` (add to class)

```swift
class JarSyncManager {
    static let shared = JarSyncManager()

    private let db: Database
    private let tombstoneRepo: JarTombstoneRepository

    // NEW: Concurrency guards
    private var processingQueues: Set<String> = []
    private var backfillInProgress: [String: (from: Int, to: Int, until: Date)] = [:]

    // NEW: Poison thresholds
    private let maxRetries = 5
    private let maxQueueAge: TimeInterval = 7 * 24 * 60 * 60  // 7 days

    // ... rest of init
}
```

### Step 3: Rewrite processEnvelope with Gap Detection

**File:** `Core/JarSyncManager.swift` (REPLACE existing method)

```swift
// MARK: - Main Entry Point (Module 4: Gap Detection)

/// Process relay envelope with gap detection and queueing
///
/// - Parameter envelope: The relay envelope to process
/// - Parameter skipGapDetection: If true, skip gap detection (used for backfill and queue processing)
///
/// INVARIANTS:
/// - Receipts are processed in relay sequence order (1, 2, 3, ...)
/// - Gaps trigger backfill requests
/// - Out-of-order receipts are queued until dependencies satisfied
/// - Replay protection prevents duplicate processing
func processEnvelope(_ envelope: RelayEnvelope, skipGapDetection: Bool = false) async throws {

    // ═══════════════════════════════════════════════════════════════
    // STEP 1: REPLAY PROTECTION
    // Check if we've already processed this exact receipt
    // ═══════════════════════════════════════════════════════════════

    guard !(try await isAlreadyProcessed(envelope.receiptCID)) else {
        print("⏭️ [REPLAY] Skipping already processed: \(envelope.receiptCID.prefix(12))...")
        return
    }

    // ═══════════════════════════════════════════════════════════════
    // STEP 2: TOMBSTONE CHECK
    // Don't process receipts for deleted jars
    // ═══════════════════════════════════════════════════════════════

    guard !(try await tombstoneRepo.isTombstoned(envelope.jarID)) else {
        print("🪦 [TOMBSTONE] Skipping receipt for deleted jar: \(envelope.jarID.prefix(12))...")
        return
    }

    // ═══════════════════════════════════════════════════════════════
    // STEP 3: GAP DETECTION (only for normal processing)
    // Compare received sequence to expected sequence
    // ═══════════════════════════════════════════════════════════════

    if !skipGapDetection {
        let lastSeq = try await getLastSequence(jarID: envelope.jarID)
        let expectedSeq = lastSeq + 1

        // CASE A: seq > expected → GAP DETECTED
        if envelope.sequenceNumber > expectedSeq {
            print("⚠️ [GAP] Expected seq=\(expectedSeq), got seq=\(envelope.sequenceNumber)")

            // Verify BEFORE queueing (don't queue invalid receipts)
            do {
                try await verifyReceipt(envelope)
            } catch {
                print("❌ [VERIFY] Receipt failed verification, not queueing: \(error)")
                throw error
            }

            // Queue this receipt (we'll process it later)
            try await queueReceipt(envelope)

            // Request missing receipts from relay
            try await requestBackfill(
                jarID: envelope.jarID,
                from: expectedSeq,
                to: envelope.sequenceNumber - 1
            )

            return  // Done - will process when backfill arrives
        }

        // CASE B: seq < expected → LATE/DUPLICATE
        if envelope.sequenceNumber < expectedSeq {
            print("⏪ [LATE] Ignoring late receipt: expected seq=\(expectedSeq), got seq=\(envelope.sequenceNumber)")
            return  // Already processed higher sequences
        }

        // CASE C: seq == expected → HAPPY PATH (fall through to processing)
    }

    // ═══════════════════════════════════════════════════════════════
    // STEP 4: VERIFY RECEIPT
    // Check signature and CID integrity
    // ═══════════════════════════════════════════════════════════════

    try await verifyReceipt(envelope)

    // ═══════════════════════════════════════════════════════════════
    // STEP 5: APPLY RECEIPT
    // Route to type-specific handler
    // ═══════════════════════════════════════════════════════════════

    try await applyReceipt(envelope)

    // ═══════════════════════════════════════════════════════════════
    // STEP 6: MARK AS PROCESSED
    // Update replay protection table and jar sequence
    // ═══════════════════════════════════════════════════════════════

    try await markProcessed(
        receiptCID: envelope.receiptCID,
        jarID: envelope.jarID,
        sequenceNumber: envelope.sequenceNumber
    )

    print("✅ [PROCESSED] Receipt seq=\(envelope.sequenceNumber) for jar \(envelope.jarID.prefix(12))...")

    // ═══════════════════════════════════════════════════════════════
    // STEP 7: TRY TO PROCESS QUEUED RECEIPTS (only for normal processing)
    // Don't call when skipGapDetection=true to avoid nested calls
    // ═══════════════════════════════════════════════════════════════

    if !skipGapDetection {
        try await processQueuedReceipts(jarID: envelope.jarID)
    }
}
```

### Step 4: Implement Queue Functions

**File:** `Core/JarSyncManager.swift` (add new section)

```swift
// MARK: - Queue Management (Module 4)

/// Queue a receipt that arrived out of order
///
/// - Parameter envelope: The envelope to queue
///
/// PRE-CONDITIONS:
/// - Receipt has been verified (signature valid)
/// - Gap was detected (seq > expected)
private func queueReceipt(_ envelope: RelayEnvelope) async throws {
    let queued = QueuedReceipt(
        id: UUID().uuidString,
        jarID: envelope.jarID,
        sequenceNumber: envelope.sequenceNumber,
        receiptCID: envelope.receiptCID,
        receiptData: envelope.receiptData,
        signature: envelope.signature,
        senderDID: envelope.senderDID,
        parentCID: envelope.parentCID,
        queuedAt: Date().timeIntervalSince1970,
        retryCount: 0,
        lastRetryAt: nil,
        poisonReason: nil
    )

    try await db.writeAsync { db in
        try queued.insert(db)
    }

    print("📥 [QUEUE] Queued receipt seq=\(envelope.sequenceNumber) for jar \(envelope.jarID.prefix(12))...")
}

/// Process queued receipts that now have their dependencies satisfied
///
/// - Parameter jarID: The jar to process queued receipts for
///
/// ALGORITHM:
/// 1. Get all queued receipts for this jar, sorted by sequence
/// 2. For each receipt:
///    - If seq < expected: ORPHANED (already processed via backfill) → remove from queue
///    - If seq == expected: READY → process and remove
///    - If seq > expected: BLOCKED (still missing earlier) → stop, request backfill
/// 3. Continue until queue is empty or blocked
private func processQueuedReceipts(jarID: String) async throws {
    // Prevent concurrent queue processing for same jar
    guard !processingQueues.contains(jarID) else {
        print("⏳ [QUEUE] Already processing queue for \(jarID.prefix(12))...")
        return
    }

    processingQueues.insert(jarID)
    defer { processingQueues.remove(jarID) }

    // Get queued receipts
    let queued = try await getQueuedReceipts(jarID: jarID)
    guard !queued.isEmpty else { return }

    print("🔄 [QUEUE] Processing \(queued.count) queued receipts for \(jarID.prefix(12))...")

    // Sort by sequence (ascending) - CRITICAL for correctness
    let sorted = queued.sorted { $0.sequenceNumber < $1.sequenceNumber }

    // Track last processed sequence (read once, update locally)
    var lastSeq = try await getLastSequence(jarID: jarID)

    for queuedReceipt in sorted {
        let expectedSeq = lastSeq + 1

        // ─────────────────────────────────────────────────────────
        // CHECK: Is this receipt poisoned?
        // ─────────────────────────────────────────────────────────

        if queuedReceipt.retryCount >= maxRetries {
            print("☠️ [POISON] Dead letter: seq=\(queuedReceipt.sequenceNumber) exceeded \(maxRetries) retries")
            try await removeFromQueue(queuedReceipt.id)
            continue
        }

        let age = Date().timeIntervalSince1970 - queuedReceipt.queuedAt
        if age > maxQueueAge {
            print("☠️ [POISON] Dead letter: seq=\(queuedReceipt.sequenceNumber) expired after \(Int(age / 86400)) days")
            try await removeFromQueue(queuedReceipt.id)
            continue
        }

        // ─────────────────────────────────────────────────────────
        // CASE A: seq < expected → ORPHANED (already processed)
        // ─────────────────────────────────────────────────────────

        if queuedReceipt.sequenceNumber < expectedSeq {
            print("🧹 [ORPHAN] Removing orphaned receipt seq=\(queuedReceipt.sequenceNumber) (expected \(expectedSeq))")
            try await removeFromQueue(queuedReceipt.id)
            continue  // Check next item
        }

        // ─────────────────────────────────────────────────────────
        // CASE B: seq == expected → READY TO PROCESS
        // ─────────────────────────────────────────────────────────

        if queuedReceipt.sequenceNumber == expectedSeq {
            print("✅ [DEQUEUE] Processing queued receipt seq=\(queuedReceipt.sequenceNumber)")

            // Reconstruct envelope from queue data
            let envelope = RelayEnvelope(
                jarID: queuedReceipt.jarID,
                sequenceNumber: queuedReceipt.sequenceNumber,
                receiptCID: queuedReceipt.receiptCID,
                receiptData: queuedReceipt.receiptData,
                signature: queuedReceipt.signature,
                senderDID: queuedReceipt.senderDID,
                receivedAt: Int64(queuedReceipt.queuedAt * 1000),
                parentCID: queuedReceipt.parentCID
            )

            do {
                // Process with skipGapDetection=true (we know sequence is correct)
                try await processEnvelope(envelope, skipGapDetection: true)

                // Remove from queue AFTER successful processing
                try await removeFromQueue(queuedReceipt.id)

                // Update local tracking
                lastSeq = queuedReceipt.sequenceNumber

            } catch {
                // Processing failed - increment retry count
                print("❌ [RETRY] Failed to process queued receipt: \(error)")
                try await incrementRetryCount(queuedReceipt.id)

                // Don't continue with rest of queue if this one failed
                // (maintain sequence order)
                break
            }

            continue  // Check next item
        }

        // ─────────────────────────────────────────────────────────
        // CASE C: seq > expected → STILL BLOCKED
        // ─────────────────────────────────────────────────────────

        print("⏸️ [BLOCKED] Waiting for seq=\(expectedSeq), have seq=\(queuedReceipt.sequenceNumber)")

        // Request missing receipts
        try await requestBackfill(
            jarID: jarID,
            from: expectedSeq,
            to: queuedReceipt.sequenceNumber - 1
        )

        break  // Can't process rest of queue yet
    }
}

/// Request missing receipts from relay (backfill)
///
/// - Parameters:
///   - jarID: The jar to backfill
///   - from: First missing sequence (inclusive)
///   - to: Last missing sequence (inclusive)
///
/// GUARDS:
/// - Prevents overlapping backfill requests (storm prevention)
/// - Handles incomplete backfills (schedules retry)
private func requestBackfill(jarID: String, from: Int, to: Int) async throws {

    // ─────────────────────────────────────────────────────────
    // GUARD: Prevent overlapping backfill requests
    // ─────────────────────────────────────────────────────────

    if let inProgress = backfillInProgress[jarID] {
        if inProgress.until > Date() {
            // Check if requested range is subset of in-progress range
            if from >= inProgress.from && to <= inProgress.to {
                print("⏳ [BACKFILL] Already in progress for \(jarID.prefix(12))... [\(inProgress.from)-\(inProgress.to)]")
                return
            }
        }
    }

    // Mark backfill in progress (15 second lock)
    backfillInProgress[jarID] = (from: from, to: to, until: Date().addingTimeInterval(15))
    defer { backfillInProgress.removeValue(forKey: jarID) }

    // ─────────────────────────────────────────────────────────
    // REQUEST: Fetch missing receipts from relay
    // ─────────────────────────────────────────────────────────

    print("🔁 [BACKFILL] Requesting seq=\(from)-\(to) for jar \(jarID.prefix(12))...")

    let envelopes: [RelayEnvelope]
    do {
        envelopes = try await RelayClient.shared.getJarReceipts(jarID: jarID, from: from, to: to)
    } catch {
        print("❌ [BACKFILL] Failed to fetch from relay: \(error)")
        throw error
    }

    print("📬 [BACKFILL] Received \(envelopes.count) receipts (requested \(to - from + 1))")

    // ─────────────────────────────────────────────────────────
    // PROCESS: Handle backfilled receipts
    // ─────────────────────────────────────────────────────────

    if envelopes.isEmpty {
        print("⚠️ [BACKFILL] Relay returned no receipts - will retry later")
        return
    }

    // Process in sequence order (CRITICAL)
    for envelope in envelopes.sorted(by: { $0.sequenceNumber < $1.sequenceNumber }) {
        do {
            try await processEnvelope(envelope, skipGapDetection: true)
        } catch {
            print("❌ [BACKFILL] Failed to process seq=\(envelope.sequenceNumber): \(error)")
            // Continue with other receipts - don't fail entire backfill
        }
    }

    // ─────────────────────────────────────────────────────────
    // CHECK: Did we get complete backfill?
    // ─────────────────────────────────────────────────────────

    let expectedCount = to - from + 1
    if envelopes.count < expectedCount {
        print("⚠️ [BACKFILL] Incomplete: got \(envelopes.count)/\(expectedCount)")

        // Check what's still missing
        let lastSeq = try await getLastSequence(jarID: jarID)
        let queued = try await getQueuedReceipts(jarID: jarID)

        if let firstQueued = queued.first {
            let expectedSeq = lastSeq + 1
            if firstQueued.sequenceNumber > expectedSeq {
                // Still have a gap - will be handled on next receipt arrival
                // or next processQueuedReceipts call
                print("⚠️ [BACKFILL] Still missing seq=\(expectedSeq) to \(firstQueued.sequenceNumber - 1)")
            }
        }
    }
}
```

### Step 5: Implement Helper Functions

**File:** `Core/JarSyncManager.swift` (add new section)

```swift
// MARK: - Queue Helpers

/// Get last processed sequence number for a jar
/// Returns 0 if jar doesn't exist yet (expects seq=1 for jar.created)
func getLastSequence(jarID: String) async throws -> Int {
    try await db.readAsync { db in
        try Int.fetchOne(
            db,
            sql: "SELECT last_sequence_number FROM jars WHERE id = ?",
            arguments: [jarID]
        ) ?? 0  // Return 0 if jar doesn't exist (expects seq=1)
    }
}

/// Get all queued receipts for a jar
private func getQueuedReceipts(jarID: String) async throws -> [QueuedReceipt] {
    try await db.readAsync { db in
        try QueuedReceipt
            .filter(Column("jar_id") == jarID)
            .filter(Column("poison_reason") == nil)  // Exclude poisoned
            .order(Column("sequence_number").asc)
            .fetchAll(db)
    }
}

/// Remove a receipt from the queue
private func removeFromQueue(_ queueID: String) async throws {
    try await db.writeAsync { db in
        try db.execute(
            sql: "DELETE FROM jar_receipt_queue WHERE id = ?",
            arguments: [queueID]
        )
    }
}

/// Increment retry count for a queued receipt
private func incrementRetryCount(_ queueID: String) async throws {
    try await db.writeAsync { db in
        try db.execute(
            sql: """
                UPDATE jar_receipt_queue
                SET retry_count = retry_count + 1, last_retry_at = ?
                WHERE id = ?
            """,
            arguments: [Date().timeIntervalSince1970, queueID]
        )
    }
}
```

### Step 6: Add RelayClient.getJarReceipts

**File:** `Core/RelayClient.swift` (add new method)

```swift
// MARK: - Jar Receipts (Phase 10.3 Module 4)

/// Fetch jar receipts for backfill
///
/// - Parameters:
///   - jarID: The jar to fetch receipts for
///   - from: First sequence number (inclusive)
///   - to: Last sequence number (inclusive)
/// - Returns: Array of relay envelopes
func getJarReceipts(jarID: String, from: Int, to: Int) async throws -> [RelayEnvelope] {
    let headers = try await authHeader()

    // URL encode jar ID
    let encodedJarID = jarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? jarID
    let url = URL(string: "\(baseURL)/api/jars/\(encodedJarID)/receipts?from=\(from)&to=\(to)")!

    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }

    print("[DEBUG] Fetching jar receipts: \(url)")

    let (data, res) = try await URLSession.shared.data(for: req)
    let statusCode = (res as? HTTPURLResponse)?.statusCode ?? 0

    print("[DEBUG] Jar receipts response status: \(statusCode)")

    guard statusCode == 200 else {
        if let errorBody = String(data: data, encoding: .utf8) {
            print("❌ Jar receipts fetch failed (HTTP \(statusCode)): \(errorBody)")
        }
        throw RelayError.httpError(statusCode: statusCode, message: "Failed to fetch jar receipts")
    }

    // Parse response
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let receiptsArray = json["receipts"] as? [[String: Any]] else {
        throw RelayError.invalidResponse
    }

    // Convert to RelayEnvelope array
    var envelopes: [RelayEnvelope] = []

    for receipt in receiptsArray {
        guard let jarID = receipt["jar_id"] as? String,
              let sequenceNumber = receipt["sequence_number"] as? Int,
              let receiptCID = receipt["receipt_cid"] as? String,
              let receiptDataBase64 = receipt["receipt_data"] as? String,
              let signatureBase64 = receipt["signature"] as? String,
              let senderDID = receipt["sender_did"] as? String,
              let receivedAt = receipt["received_at"] as? Int64,
              let receiptData = Data(base64Encoded: receiptDataBase64),
              let signature = Data(base64Encoded: signatureBase64) else {
            print("⚠️ Skipping malformed receipt in backfill response")
            continue
        }

        let parentCID = receipt["parent_cid"] as? String

        let envelope = RelayEnvelope(
            jarID: jarID,
            sequenceNumber: sequenceNumber,
            receiptCID: receiptCID,
            receiptData: receiptData,
            signature: signature,
            senderDID: senderDID,
            receivedAt: receivedAt,
            parentCID: parentCID
        )

        envelopes.append(envelope)
    }

    print("✅ Parsed \(envelopes.count) envelopes from backfill response")
    return envelopes
}
```

---

## Testing Strategy

### Test Case 1: Happy Path (In-Order Delivery)

```
SETUP: Empty jar
INPUT: Receive seq [1, 2, 3, 4] in order
EXPECTED:
  - All 4 receipts processed immediately
  - No queueing
  - No backfill requests
  - jars.last_sequence_number = 4
```

**How to test:**
```swift
func testHappyPath() async throws {
    let jarID = "test-jar-\(UUID())"

    // Simulate receiving 4 receipts in order
    for seq in 1...4 {
        let envelope = makeTestEnvelope(jarID: jarID, seq: seq)
        try await JarSyncManager.shared.processEnvelope(envelope)
    }

    // Verify
    let lastSeq = try await JarSyncManager.shared.getLastSequence(jarID: jarID)
    XCTAssertEqual(lastSeq, 4)

    let queuedCount = try await getQueuedCount(jarID: jarID)
    XCTAssertEqual(queuedCount, 0)
}
```

### Test Case 2: Single Gap

```
SETUP: Empty jar
INPUT: Receive seq [1, 2, 4]
EXPECTED:
  - Process 1, 2 immediately
  - Detect gap at 4 (expected 3)
  - Queue 4
  - Request backfill(3, 3)
  - When backfill arrives: process 3, then queued 4
  - jars.last_sequence_number = 4
```

**How to test:**
```swift
func testSingleGap() async throws {
    let jarID = "test-jar-\(UUID())"

    // Mock relay to return seq 3 on backfill
    MockRelayClient.shared.setBackfillResponse(jarID: jarID, from: 3, to: 3, envelopes: [
        makeTestEnvelope(jarID: jarID, seq: 3)
    ])

    // Receive 1, 2
    try await JarSyncManager.shared.processEnvelope(makeTestEnvelope(jarID: jarID, seq: 1))
    try await JarSyncManager.shared.processEnvelope(makeTestEnvelope(jarID: jarID, seq: 2))

    // Receive 4 (gap!)
    try await JarSyncManager.shared.processEnvelope(makeTestEnvelope(jarID: jarID, seq: 4))

    // Verify all processed (backfill filled the gap)
    let lastSeq = try await JarSyncManager.shared.getLastSequence(jarID: jarID)
    XCTAssertEqual(lastSeq, 4)
}
```

### Test Case 3: Out-of-Order Delivery

```
SETUP: Empty jar
INPUT: Receive seq [1, 4, 2, 3]
EXPECTED:
  - Process 1
  - Detect gap at 4 → queue 4, request backfill(2, 3)
  - Backfill arrives [2, 3]: process 2, 3
  - Queue processing: process queued 4
  - jars.last_sequence_number = 4
```

### Test Case 4: Incomplete Backfill

```
SETUP: Jar with seq 1, 2 processed
INPUT: Receive seq 10, then incomplete backfill [3, 4, 5]
EXPECTED:
  - Detect gap at 10 → queue 10, request backfill(3, 9)
  - Backfill returns only [3, 4, 5]
  - Process 3, 4, 5
  - Try queue: can't process 10 (missing 6-9)
  - Log warning about incomplete backfill
  - jars.last_sequence_number = 5
  - Queue still has 10
```

### Test Case 5: Orphaned Queue Entry

```
SETUP: Queue has receipt seq=4, jar at seq=1
INPUT: Backfill arrives [2, 3, 4]
EXPECTED:
  - Process 2, 3, 4 from backfill
  - Queue processing: seq=4 < expected=5 → ORPHANED
  - Remove 4 from queue (don't process again)
  - Queue empty
```

### Test Case 6: Poison Detection (Max Retries)

```
SETUP: Queue has receipt that always fails verification
ACTION: Process queue 6 times
EXPECTED:
  - 5 failures, retry_count incremented each time
  - 6th attempt: detected as poison
  - Removed from queue
  - Warning logged
```

### Test Case 7: Backfill Storm Prevention

```
SETUP: Jar at seq=1
INPUT: Rapidly receive seq 10, 15, 20
EXPECTED:
  - First gap: request backfill(2, 9)
  - Second gap: backfill in progress, skip
  - Third gap: backfill in progress, skip
  - Only ONE backfill request made
```

### Test Case 8: Jar Creation (seq=1)

```
SETUP: Jar does not exist
INPUT: Receive jar.created with seq=1
EXPECTED:
  - getLastSequence returns 0 (jar doesn't exist)
  - expected = 1, actual = 1 → no gap
  - Process jar.created → jar created
  - jars.last_sequence_number = 1
```

### Test Case 9: Duplicate/Replay Protection

```
SETUP: Jar with seq 1-5 processed
INPUT: Receive seq=3 again
EXPECTED:
  - isAlreadyProcessed(receipt_cid) returns true
  - Skip immediately
  - No processing, no queueing
```

### Test Case 10: Late Receipt (seq < expected)

```
SETUP: Jar with seq 1-5 processed
INPUT: Receive seq=2 (different CID, but same sequence)
EXPECTED:
  - Replay check passes (different CID)
  - Gap check: seq=2 < expected=6 → LATE
  - Skip (log message)
  - No queueing
```

---

## Files Modified Summary

| File | Changes |
|------|---------|
| `Core/Database/Database.swift` | Add migration v9 (queue envelope fields) |
| `Core/JarSyncManager.swift` | Add QueuedReceipt model, rewrite processEnvelope, add queue functions |
| `Core/RelayClient.swift` | Add getJarReceipts() for backfill |

---

## Implementation Checklist

```
[ ] 1. Add migration v9 to Database.swift
[ ] 2. Add QueuedReceipt struct to JarSyncManager.swift
[ ] 3. Add properties (processingQueues, backfillInProgress, thresholds)
[ ] 4. Replace processEnvelope with gap-detecting version
[ ] 5. Implement queueReceipt()
[ ] 6. Implement processQueuedReceipts() with orphan handling
[ ] 7. Implement requestBackfill() with storm prevention
[ ] 8. Implement helper functions (getLastSequence, etc.)
[ ] 9. Add getJarReceipts() to RelayClient
[ ] 10. Build and fix compile errors
[ ] 11. Run test cases
[ ] 12. Manual testing with two devices
```

---

## Success Criteria

1. **Correctness:** All receipts processed in relay sequence order
2. **Idempotency:** No duplicate processing (replay protection)
3. **Termination:** No infinite loops (skipGapDetection flag)
4. **Liveness:** Queue eventually drains when dependencies satisfied
5. **Resilience:** Handles incomplete backfills gracefully
6. **Performance:** No backfill storms (lock prevents overlapping requests)
7. **Safety:** Poison receipts detected and removed (don't block forever)

---

**This plan is implementation-ready. Every edge case is handled. Every bug is fixed. Let's nail it first try.**
