# Module 5a: Jar Sync Loop - FINAL IMPLEMENTATION PLAN

**Date:** January 5, 2026
**Estimated:** 2-3 hours
**Dependencies:** Module 4 (JarSyncManager) ✅ Complete

---

## Ship-It Checklist (5 Critical Fixes)

✅ **Fix 1:** Sort + dedupe envelopes by sequenceNumber before processing
✅ **Fix 2:** Document JarSyncManager owns `last_sequence_number` (already true, just clarify)
✅ **Fix 3:** Check `isJarHalted()` before polling to avoid spam
✅ **Fix 4:** Assert local CID == relay CID (deferred to 5b - jar creation)
✅ **Fix 5:** Add sync_status for jar creation (deferred to 5b)

---

## Architecture Refinement: Clean Interface

**Problem:** InboxManager shouldn't import jar DB schema details

**Solution:** Add interface methods to JarSyncManager

```swift
// JarSyncManager exposes:
- getSyncTargets() → [(jarID, afterSeq, isHalted)]
- processEnvelopes(jarID, envelopes) → handles sorting + processing

// InboxManager becomes pure router:
- poll buds inbox
- poll jar sync targets
- forward envelopes
```

---

## Implementation

### 1. Add Interface to JarSyncManager.swift (~60 lines)

**Location:** After existing `getLastSequence()` helper (line ~950)

```swift
// MARK: - Sync Interface (Module 5a)

/**
 * Get jars that need syncing
 *
 * Returns array of (jarID, lastSeq, isHalted) for InboxManager to poll
 *
 * INVARIANT: JarSyncManager owns all writes to jars.last_sequence_number
 * InboxManager only reads via this interface.
 */
func getSyncTargets() async throws -> [JarSyncTarget] {
    try await db.readAsync { db in
        // Fetch all active jars (not tombstoned)
        let rows = try Row.fetchAll(db, sql: """
            SELECT j.id, j.last_sequence_number, COALESCE(s.is_halted, 0) AS is_halted
            FROM jars j
            LEFT JOIN jar_sync_state s ON j.id = s.jar_id
            WHERE j.id NOT IN (SELECT jar_id FROM jar_tombstones)
            ORDER BY j.created_at DESC
        """)

        return rows.map { row in
            JarSyncTarget(
                jarID: row["id"] as! String,
                lastSequenceNumber: row["last_sequence_number"] as! Int,
                isHalted: (row["is_halted"] as! Int) == 1
            )
        }
    }
}

/**
 * Process batch of envelopes for a jar
 *
 * Handles:
 * - Sorting by sequence (ascending)
 * - In-memory deduplication by sequenceNumber (pagination bugs)
 * - DB replay protection by receiptCID
 * - Routing to processEnvelope()
 *
 * CRITICAL: Envelopes from relay might be out-of-order or contain duplicates.
 * We MUST sort + dedupe before processing to avoid unnecessary gap detection.
 */
func processEnvelopes(for jarID: String, _ envelopes: [RelayEnvelope]) async throws {
    guard !envelopes.isEmpty else { return }

    let jarPrefix = String(jarID.prefix(8))
    print("📦 [BATCH] Processing \(envelopes.count) envelopes for \(jarPrefix)...")

    // CRITICAL FIX 1a: Sort by sequence (ascending)
    let sorted = envelopes.sorted { $0.sequenceNumber < $1.sequenceNumber }

    // CRITICAL FIX 1b: In-memory dedupe by sequenceNumber (keep first occurrence)
    // Handles pagination bugs where relay returns seq=3 twice
    var seenSequences: Set<Int> = []
    let deduped = sorted.filter { envelope in
        if seenSequences.contains(envelope.sequenceNumber) {
            print("⚠️  [BATCH] Duplicate seq=\(envelope.sequenceNumber), skipping")
            return false
        }
        seenSequences.insert(envelope.sequenceNumber)
        return true
    }

    // Process each envelope with DB replay protection
    var processed = 0
    var skipped = 0

    for envelope in deduped {
        // CRITICAL FIX 2: Check DB for (jarID, seq, CID) consistency
        if let existingCID = try await getProcessedReceiptCID(jarID: jarID, sequenceNumber: envelope.sequenceNumber) {
            if existingCID != envelope.receiptCID {
                // CORRUPTION: Same sequence with different CID
                print("🚨 [CORRUPTION] jar=\(jarPrefix) seq=\(envelope.sequenceNumber) CID mismatch!")
                print("🚨   Expected: \(existingCID)")
                print("🚨   Got:      \(envelope.receiptCID)")
                try await haltJar(jarID: jarID, reason: "Sequence \(envelope.sequenceNumber) CID mismatch (corruption detected)")
                throw SyncError.sequenceCIDMismatch(jarID: jarID, sequence: envelope.sequenceNumber)
            }
            // Same CID, already processed (replay)
            skipped += 1
            continue
        }

        // Process envelope (gap detection, verification, apply)
        do {
            try await processEnvelope(envelope)
            processed += 1
        } catch {
            print("❌ [BATCH] Failed to process seq=\(envelope.sequenceNumber): \(error)")
            // Continue processing rest (don't let one failure stop the batch)
            // Individual failures are handled by processEnvelope (halting, etc.)
        }
    }

    print("✅ [BATCH] Processed \(processed)/\(deduped.count) (\(skipped) skipped)")
}

/**
 * Get CID of already-processed receipt for (jarID, sequence)
 *
 * Returns:
 * - nil if not processed
 * - CID if processed (for mismatch detection)
 */
private func getProcessedReceiptCID(jarID: String, sequenceNumber: Int) async throws -> String? {
    try await db.readAsync { db in
        try String.fetchOne(db, sql: """
            SELECT receipt_cid FROM processed_jar_receipts
            WHERE jar_id = ? AND sequence_number = ?
        """, arguments: [jarID, sequenceNumber])
    }
}

// MARK: - Models

struct JarSyncTarget {
    let jarID: String
    let lastSequenceNumber: Int
    let isHalted: Bool
}
```

---

### 2. Update InboxManager.swift (~80 lines added)

**Location:** After existing `pollInbox()` method

```swift
// EXISTING: Keep pollInbox() unchanged, add jar polling after bud processing

func pollInbox() async {
    guard !isPolling else { return }
    isPolling = true
    defer { isPolling = false }

    do {
        // ═══════════════════════════════════════════════════════
        // EXISTING: Poll bud receipts (keep unchanged)
        // ═══════════════════════════════════════════════════════

        let did = try await IdentityManager.shared.currentDID
        let messages = try await RelayClient.shared.getInbox(for: did)

        // ... existing bud processing logic ...

        // ═══════════════════════════════════════════════════════
        // NEW: Poll jar receipts (after bud polling)
        // ═══════════════════════════════════════════════════════

        await pollJarReceipts()

    } catch {
        print("❌ Inbox poll failed: \(error)")
    }
}

// NEW: Poll jar receipts for all active jars
private func pollJarReceipts() async {
    do {
        // Get sync targets from JarSyncManager (clean interface)
        let targets = try await JarSyncManager.shared.getSyncTargets()

        guard !targets.isEmpty else {
            print("📭 No active jars to sync")
            return
        }

        print("📡 [JAR_SYNC] Polling \(targets.count) active jars...")

        // Poll each jar independently
        for target in targets {
            do {
                try await pollJar(target)
            } catch {
                print("❌ [JAR_SYNC] Failed to poll jar \(String(target.jarID.prefix(8))...): \(error)")
                // Continue polling other jars (isolation)
            }
        }

    } catch {
        print("❌ [JAR_SYNC] Failed to get sync targets: \(error)")
    }
}

// NEW: Poll receipts for a single jar
private func pollJar(_ target: JarSyncTarget) async throws {
    let jarPrefix = String(target.jarID.prefix(8))

    // CRITICAL FIX 3: Skip halted jars (avoid spam during backfill)
    guard !target.isHalted else {
        print("⏸️  [JAR_SYNC] Skipping halted jar \(jarPrefix)...")
        return
    }

    print("📡 [JAR_SYNC] Polling jar \(jarPrefix)... (after seq=\(target.lastSequenceNumber))")

    // Fetch new receipts from relay (using ?after= API)
    let envelopes: [RelayEnvelope]
    do {
        envelopes = try await RelayClient.shared.getJarReceipts(
            jarID: target.jarID,
            after: target.lastSequenceNumber,
            limit: 100
        )
    } catch let error as RelayError {
        // CRITICAL FIX 3: Handle 403 gracefully (don't spam every 30s)
        if case .httpError(let statusCode, _) = error, statusCode == 403 {
            print("🚫 [JAR_SYNC] Not a member of jar \(jarPrefix), halting polling")
            // Mark jar as halted due to membership revocation
            try await JarSyncManager.shared.haltJar(
                jarID: target.jarID,
                reason: "Not a member (HTTP 403)"
            )
            return
        }
        throw error
    }

    guard !envelopes.isEmpty else {
        print("📭 [JAR_SYNC] No new receipts for \(jarPrefix)")
        return
    }

    print("📬 [JAR_SYNC] Received \(envelopes.count) receipts for \(jarPrefix)")

    // Process batch (JarSyncManager handles sorting, deduping, gap detection)
    try await JarSyncManager.shared.processEnvelopes(for: target.jarID, envelopes)

    // Notify UI to refresh jar
    await MainActor.run {
        NotificationCenter.default.post(
            name: .jarUpdated,
            object: nil,
            userInfo: ["jar_id": target.jarID]
        )
    }
}
```

**Add notification:**

```swift
extension Notification.Name {
    static let inboxUpdated = Notification.Name("inboxUpdated")          // Existing
    static let newDeviceDetected = Notification.Name("newDeviceDetected")  // Existing
    static let jarUpdated = Notification.Name("jarUpdated")              // NEW
}
```

---

### 3. Update RelayClient+JarReceipts.swift (~30 lines)

**Add `after=` API for normal sync (gap-filling `from/to` already exists from Module 1):**

```swift
extension RelayClient {
    // EXISTING: storeJarReceipt() - keep as-is
    // EXISTING: getJarReceipts(from:to:) - keep as-is for gap filling

    // NEW: Sync API (poll for new receipts after last sequence)
    func getJarReceipts(jarID: String, after lastSeq: Int, limit: Int = 100) async throws -> [RelayEnvelope] {
        let headers = try await authHeader()
        let url = URL(string: "\(baseURL)/api/jars/\(jarID)/receipts?after=\(lastSeq)&limit=\(limit)")!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }

        let (data, res) = try await URLSession.shared.data(for: req)
        let statusCode = (res as? HTTPURLResponse)?.statusCode ?? 0

        // Handle errors gracefully
        if statusCode == 404 {
            // Jar not found (might be deleted or never created on relay)
            print("⚠️  [RELAY] Jar \(String(jarID.prefix(8)))... not found on relay")
            return []
        }
        if statusCode == 403 {
            // Not a member (removed from jar)
            print("⚠️  [RELAY] Not a member of jar \(String(jarID.prefix(8)))...")
            throw RelayError.httpError(statusCode: 403, message: "Not a member of this jar")
        }
        guard statusCode == 200 else {
            throw RelayError.httpError(statusCode: statusCode, message: "Failed to fetch jar receipts")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let receiptsArray = json?["receipts"] as? [[String: Any]] else {
            throw RelayError.invalidResponse
        }

        // Parse relay envelopes
        return try receiptsArray.map { dict in
            guard let jarID = dict["jar_id"] as? String,
                  let sequenceNumber = dict["sequence_number"] as? Int,
                  let receiptCID = dict["receipt_cid"] as? String,
                  let receiptDataB64 = dict["receipt_data"] as? String,
                  let signatureB64 = dict["signature"] as? String,
                  let senderDID = dict["sender_did"] as? String,
                  let receivedAt = dict["received_at"] as? Int64 else {
                throw RelayError.invalidResponse
            }

            guard let receiptData = Data(base64Encoded: receiptDataB64),
                  let signature = Data(base64Encoded: signatureB64) else {
                throw RelayError.invalidResponse
            }

            let parentCID = dict["parent_cid"] as? String

            return RelayEnvelope(
                jarID: jarID,
                sequenceNumber: sequenceNumber,
                receiptCID: receiptCID,
                receiptData: receiptData,
                signature: signature,
                senderDID: senderDID,
                receivedAt: receivedAt,
                parentCID: parentCID
            )
        }
    }
}
```

---

## Invariants (Critical - Document Clearly)

### 1. Sequence Number Ownership
**INVARIANT:** `JarSyncManager` is the ONLY component that writes to `jars.last_sequence_number`.

- ✅ JarSyncManager: Writes via `markProcessed()` (line 610-625)
- ✅ InboxManager: Reads via `getSyncTargets()` (new interface)
- ❌ No other component touches `last_sequence_number`

### 2. Envelope Ordering
**INVARIANT:** Relay MAY return envelopes out-of-order or with duplicates.

- ✅ JarSyncManager: Sorts + dedupes in `processEnvelopes()` before routing to `processEnvelope()`
- ✅ Reduces unnecessary gap detection
- ✅ Prevents wasted verification work

### 3. Halt State Isolation
**INVARIANT:** Halted jars are NOT polled until manually unhalted or app restart.

- ✅ InboxManager: Checks `isHalted` flag before polling
- ✅ Prevents spam during backfill-in-progress
- ✅ Reduces log noise

---

## Edge Cases Handled

### 1. Out-of-Order Receipts
**Scenario:** Relay returns [seq=5, seq=3, seq=4]
**Handling:** Sort to [3, 4, 5] before processing ✅

### 2. Duplicate Receipts (Pagination Bug)
**Scenario:** Relay returns seq=3 twice in same batch
**Handling:** In-memory dedupe by sequenceNumber (keep first) ✅

### 2b. Duplicate Receipts (Replay)
**Scenario:** Relay returns seq=3 again in next poll (already processed)
**Handling:** DB check via `getProcessedReceiptCID()` ✅

### 2c. Sequence CID Mismatch (Corruption)
**Scenario:** Relay returns seq=3 with different CID than previously processed
**Handling:** Halt jar immediately, log corruption ✅

### 3. Halted Jar
**Scenario:** Jar has poison receipt, needs backfill retry
**Handling:** Skip polling until unhalt ✅

### 4. Jar Not on Relay
**Scenario:** Jar created locally but relay down, never synced
**Handling:** 404 → return empty array, continue polling ✅

### 5. Removed from Jar
**Scenario:** User removed from jar while offline
**Handling:** 403 → throw error, stop polling that jar ✅

### 6. One Jar Fails
**Scenario:** Jar A throws error during processing
**Handling:** Continue polling jars B, C, D (isolation) ✅

---

## Testing Plan

### Unit Tests (Defer to 5b Integration Test)

**Mock scenarios:**
1. Relay returns out-of-order envelopes → verify sorted before processing
2. Relay returns duplicates → verify deduped
3. Jar is halted → verify polling skipped

### Manual Test (After 5b Implemented)

**Two-device test:**
1. Device A creates jar (Module 5b)
2. Wait 30s for InboxManager polling
3. Device B should receive jar.created receipt
4. Verify jar appears on device B

---

## Performance Considerations

### Polling Storm Mitigation (Optional - Defer to Future)

**Current:** Poll every jar every 30s (100 jars = 100 API calls/30s)

**Future optimization (not implemented now):**
- Per-jar backoff on repeated empty polls
- Batch API: `GET /api/jars/receipts?jar_ids=a,b,c`
- Server-sent events (SSE) for push notifications

**Decision:** Acceptable for MVP (most users <5 jars), optimize in Phase 11

---

## Files Modified Summary

1. **JarSyncManager.swift** (~90 lines added)
   - `getSyncTargets()` - Interface for InboxManager
   - `processEnvelopes()` - Batch processing with sort + 2-layer dedupe
   - `getProcessedReceiptCID()` - Check (jarID, seq) → CID for corruption detection
   - `SyncError.sequenceCIDMismatch` - New error case

2. **InboxManager.swift** (~90 lines added)
   - `pollJarReceipts()` - Poll all active jars
   - `pollJar()` - Poll single jar with 403 handling
   - `.jarUpdated` notification

3. **RelayClient+JarReceipts.swift** (~30 lines added)
   - `getJarReceipts(after:limit:)` - Sync API

**Total:** ~210 lines, 2-3 hours

---

## Success Criteria

- ✅ InboxManager polls jar receipts every 30s (same loop as buds)
- ✅ JarSyncManager interface hides DB schema from InboxManager
- ✅ Envelopes sorted + deduped before processing
- ✅ Halted jars skipped during polling
- ✅ One jar failure doesn't break other jars
- ✅ No duplicate polling loops
- ✅ UI refreshes on jar updates

---

## Ready for Implementation?

All 5 critical fixes implemented:
1. ✅ Sort + dedupe envelopes
2. ✅ JarSyncManager owns lastSeq (documented invariant)
3. ✅ Skip halted jars during polling
4. ✅ CID assertion (deferred to 5b)
5. ✅ sync_status (deferred to 5b)

Clean architecture:
- ✅ InboxManager = pure router
- ✅ JarSyncManager = processor + state owner
- ✅ No schema coupling via `getSyncTargets()` interface

**Approve to implement Module 5a?**
