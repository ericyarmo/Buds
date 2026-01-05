# Phase 10.3 - Module 5: Jar Sync Loop + Jar Creation

**Date:** January 5, 2026
**Status:** 📋 Ready for Review
**Estimated Time:** 4-6 hours total (5a: 2-3h, 5b: 2-3h)

---

## Overview

Split into two focused modules:
- **Module 5a: Jar Sync Loop** - Extend existing InboxManager to poll jar receipts
- **Module 5b: Jar Creation** - Generate and send jar.created receipts

**Architecture Philosophy:**
- **NO new polling loop** - extend the existing 30s InboxManager loop
- **NO duplicate systems** - route jar receipts to JarSyncManager (already built in Module 4)
- **Clean separation** - InboxManager is the "router", JarSyncManager is the "processor"

---

## Current Architecture (What We Have)

```
┌─────────────────────────────────────────────────────────────┐
│ InboxManager.swift (30s polling loop)                      │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ pollInbox() every 30s                                   │ │
│ │  ├─ RelayClient.getInbox(did) → [EncryptedMessage]     │ │
│ │  ├─ Process BUD receipts → MemoryRepository            │ │
│ │  └─ Process REACTION receipts → ReactionRepository     │ │
│ └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ JarSyncManager.swift (Module 3+4 - COMPLETE)               │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ processEnvelope(RelayEnvelope)                          │ │
│ │  ├─ Verify signature + CID                             │ │
│ │  ├─ Gap detection + queueing                           │ │
│ │  ├─ Apply to local state (9 receipt types)             │ │
│ │  └─ Backfill missing receipts                          │ │
│ └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘

❌ PROBLEM: No connection between them!
   - JarSyncManager can PROCESS jar receipts
   - But nothing is FETCHING jar receipts from relay
```

---

## Module 5a: Jar Sync Loop (2-3 hours)

**Goal:** Extend InboxManager to poll jar receipts and route to JarSyncManager

### Architecture Changes

```
┌─────────────────────────────────────────────────────────────┐
│ InboxManager.swift (UPDATED - single 30s loop)             │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ pollInbox() every 30s                                   │ │
│ │  ├─ Buds: RelayClient.getInbox(did) → process buds     │ │
│ │  └─ Jars: pollJarReceipts() → NEW                      │ │
│ │     ├─ Get all active jars from DB                     │ │
│ │     ├─ For each jar:                                   │ │
│ │     │   ├─ Get lastSeq from DB                         │ │
│ │     │   ├─ RelayClient.getJarReceipts(jar, after=seq) │ │
│ │     │   └─ Route to JarSyncManager.processEnvelope()   │ │
│ │     └─ Handle errors gracefully                        │ │
│ └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ RelayClient+JarReceipts.swift (NEW extension)               │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ GET /api/jars/{jar}/receipts?after={seq}&limit=100     │ │
│ │  → [RelayEnvelope]                                     │ │
│ └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Files to Modify

#### 1. `Core/InboxManager.swift` (~50 lines added)

**Add jar polling to existing loop:**

```swift
// EXISTING: pollInbox() - keep as is, add jar polling after bud polling

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
        // Get all active jars (not tombstoned)
        let jars = try await getActiveJars()

        guard !jars.isEmpty else {
            print("📭 No active jars to sync")
            return
        }

        print("📡 [JAR_SYNC] Polling \(jars.count) active jars...")

        for jar in jars {
            do {
                try await pollJarReceipts(for: jar)
            } catch {
                print("❌ [JAR_SYNC] Failed to poll jar \(jar.id): \(error)")
                // Continue polling other jars (don't fail entire sync)
            }
        }

    } catch {
        print("❌ [JAR_SYNC] Failed to get active jars: \(error)")
    }
}

// NEW: Poll receipts for a single jar
private func pollJarReceipts(for jar: ActiveJar) async throws {
    let jarPrefix = String(jar.id.prefix(8))

    // Get last processed sequence from DB
    let lastSeq = jar.lastSequenceNumber

    print("📡 [JAR_SYNC] Polling jar \(jarPrefix)... (after seq=\(lastSeq))")

    // Fetch new receipts from relay (using ?after= API)
    let envelopes = try await RelayClient.shared.getJarReceipts(
        jarID: jar.id,
        after: lastSeq,
        limit: 100
    )

    guard !envelopes.isEmpty else {
        print("📭 [JAR_SYNC] No new receipts for \(jarPrefix)")
        return
    }

    print("📬 [JAR_SYNC] Received \(envelopes.count) receipts for \(jarPrefix)")

    // Process each envelope (JarSyncManager handles gap detection, queueing, etc.)
    for envelope in envelopes {
        do {
            try await JarSyncManager.shared.processEnvelope(envelope)
        } catch {
            print("❌ [JAR_SYNC] Failed to process seq=\(envelope.sequenceNumber): \(error)")
            // JarSyncManager handles halting if needed, continue processing
        }
    }

    // Notify UI to refresh jar (post notification)
    await MainActor.run {
        NotificationCenter.default.post(
            name: .jarUpdated,
            object: nil,
            userInfo: ["jar_id": jar.id]
        )
    }
}

// NEW: Helper to get active jars
private func getActiveJars() async throws -> [ActiveJar] {
    try await Database.shared.readAsync { db in
        try ActiveJar.fetchAll(db, sql: """
            SELECT id, last_sequence_number
            FROM jars
            WHERE id NOT IN (SELECT jar_id FROM jar_tombstones)
            ORDER BY created_at DESC
        """)
    }
}

// NEW: Simple struct for active jars
struct ActiveJar: FetchableRecord {
    let id: String
    let lastSequenceNumber: Int

    enum CodingKeys: String, CodingKey {
        case id
        case lastSequenceNumber = "last_sequence_number"
    }
}
```

**Add notification name:**

```swift
extension Notification.Name {
    static let inboxUpdated = Notification.Name("inboxUpdated")      // Existing
    static let newDeviceDetected = Notification.Name("newDeviceDetected")  // Existing
    static let jarUpdated = Notification.Name("jarUpdated")          // NEW
}
```

#### 2. `Core/RelayClient+JarReceipts.swift` (MODIFY existing extension, ~30 lines)

**The extension already exists from Module 1, but we need to update it:**

Current state (Module 1):
```swift
extension RelayClient {
    func storeJarReceipt(...) async throws { ... }  // ✅ Already exists
    func getJarReceipts(jarID: String, from: Int, to: Int) async throws -> [RelayEnvelope] { ... }  // ✅ Already exists (gap filling)
}
```

**Add the `after=` API for normal sync:**

```swift
extension RelayClient {
    // EXISTING: Keep storeJarReceipt() as-is

    // EXISTING: Keep getJarReceipts(from:to:) for gap filling

    // NEW: Sync API (poll for new receipts after last sequence)
    func getJarReceipts(jarID: String, after lastSeq: Int, limit: Int = 100) async throws -> [RelayEnvelope] {
        let headers = try await authHeader()
        let url = URL(string: "\(baseURL)/api/jars/\(jarID)/receipts?after=\(lastSeq)&limit=\(limit)")!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }

        let (data, res) = try await URLSession.shared.data(for: req)
        let statusCode = (res as? HTTPURLResponse)?.statusCode ?? 0

        guard statusCode == 200 else {
            if statusCode == 404 {
                // Jar not found (might be deleted or never created on relay)
                return []
            }
            if statusCode == 403 {
                // Not a member (removed from jar)
                throw RelayError.httpError(statusCode: 403, message: "Not a member of this jar")
            }
            throw RelayError.httpError(statusCode: statusCode, message: "Failed to fetch jar receipts")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let receiptsArray = json?["receipts"] as? [[String: Any]] else {
            throw RelayError.invalidResponse
        }

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

### Success Criteria

- ✅ InboxManager polls jar receipts every 30s (same loop as buds)
- ✅ Each active jar fetched independently via `?after=lastSeq`
- ✅ Receipts routed to JarSyncManager.processEnvelope()
- ✅ Errors in one jar don't break polling for other jars
- ✅ No duplicate polling loops (single 30s timer)
- ✅ UI refreshes when jar updated (NotificationCenter)

### Testing

**Manual test:**
1. Create jar on device A
2. Wait 30s
3. Device B should receive jar.created receipt
4. Verify jar appears in device B's jars table

---

## Module 5b: Jar Creation (2-3 hours)

**Goal:** Allow users to create jars and sync them across devices

### Files to Modify

#### 1. `Core/JarManager.swift` (CREATE NEW, ~150 lines)

**Full implementation:**

```swift
import Foundation
import GRDB

class JarManager: ObservableObject {
    static let shared = JarManager()

    private let db: Database
    private let jarRepo: JarRepository

    private init() {
        self.db = Database.shared
        self.jarRepo = JarRepository.shared
    }

    // MARK: - Jar Creation

    /**
     * Create a new jar and sync to relay
     *
     * Flow:
     * 1. Create jar locally (pending sync)
     * 2. Generate jar.created receipt (NO sequence, NO parent_cid)
     * 3. Send to relay → relay assigns seq=1 (likely)
     * 4. Store relay-assigned sequence locally
     * 5. Relay broadcasts to future members (none yet, just owner)
     */
    func createJar(name: String, description: String?) async throws -> Jar {
        print("🆕 Creating jar: \(name)")

        // Get current user DID
        let ownerDID = try await IdentityManager.shared.currentDID

        // Generate unique jar ID
        let jarID = UUID().uuidString

        // 1. Create jar locally (optimistic - before relay confirms)
        let jar = try await jarRepo.createJar(
            id: jarID,
            name: name,
            description: description,
            ownerDID: ownerDID,
            lastSequenceNumber: 0,  // Will be updated after relay assigns
            parentCID: nil          // Root receipt has no parent
        )

        print("✅ Jar created locally: \(jarID)")

        // 2. Generate jar.created receipt payload
        let payloadCBOR = try ReceiptCanonicalizer.encodeJarCreatedPayload(
            jarName: name,
            jarDescription: description,
            ownerDID: ownerDID,
            createdAtMs: Int64(Date().timeIntervalSince1970 * 1000)
        )

        // 3. Wrap in jar receipt envelope (NO sequence, NO parent_cid)
        let receiptCBOR = try ReceiptCanonicalizer.encodeJarReceiptPayload(
            jarID: jarID,
            receiptType: "jar.created",
            senderDID: ownerDID,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            parentCID: nil,  // Root receipt
            payload: payloadCBOR
        )

        // 4. Compute CID + sign
        let receiptCID = CanonicalCBOREncoder.computeCID(from: receiptCBOR)
        let signature = try await ReceiptManager.shared.signReceipt(receiptCBOR)

        print("📝 Receipt CID: \(receiptCID)")

        // 5. Send to relay → relay assigns sequence (likely seq=1)
        let response = try await RelayClient.shared.storeJarReceipt(
            jarID: jarID,
            receiptData: receiptCBOR,
            signature: signature,
            parentCID: nil
        )

        print("✅ Relay assigned sequence: \(response.sequenceNumber)")

        // 6. Update jar with relay-assigned sequence
        try await jarRepo.updateLastSequence(jarID, response.sequenceNumber)
        try await jarRepo.updateParentCID(jarID, receiptCID)

        // 7. Add owner to jar_members (active)
        try await db.writeAsync { db in
            try db.execute(sql: """
                INSERT INTO jar_members (jar_id, did, role, status, added_at)
                VALUES (?, ?, 'owner', 'active', ?)
            """, arguments: [jarID, ownerDID, Date().timeIntervalSince1970])
        }

        print("🎉 Jar created and synced: \(name)")

        // Notify UI
        await MainActor.run {
            NotificationCenter.default.post(name: .jarCreated, object: jar)
        }

        return jar
    }

    // MARK: - Jar Retrieval

    func getJar(_ jarID: String) async throws -> Jar? {
        try await jarRepo.getJar(jarID)
    }

    func getAllJars() async throws -> [Jar] {
        try await jarRepo.getAllJars()
    }

    // MARK: - TOFU Device Management (for Circle members)

    /// Get TOFU-pinned Ed25519 key for a specific device
    /// Used by InboxManager for signature verification
    func getPinnedEd25519PublicKey(did: String, deviceId: String) async throws -> Data? {
        try await db.readAsync { db in
            guard let base64Key = try String.fetchOne(db, sql: """
                SELECT pubkey_ed25519 FROM devices
                WHERE owner_did = ? AND device_id = ?
            """, arguments: [did, deviceId]) else {
                return nil
            }

            return Data(base64Encoded: base64Key)
        }
    }
}

// MARK: - Models

struct Jar: Codable, FetchableRecord, Identifiable {
    let id: String
    let name: String
    let description: String?
    let ownerDID: String
    let createdAt: TimeInterval
    let lastSequenceNumber: Int
    let parentCID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case ownerDID = "owner_did"
        case createdAt = "created_at"
        case lastSequenceNumber = "last_sequence_number"
        case parentCID = "parent_cid"
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let jarCreated = Notification.Name("jarCreated")
}
```

#### 2. `Core/Database/Repositories/JarRepository.swift` (CREATE NEW, ~120 lines)

```swift
import Foundation
import GRDB

class JarRepository {
    static let shared = JarRepository()

    private let db: Database

    private init() {
        self.db = Database.shared
    }

    // MARK: - Create

    func createJar(
        id: String,
        name: String,
        description: String?,
        ownerDID: String,
        lastSequenceNumber: Int,
        parentCID: String?
    ) async throws -> Jar {
        try await db.writeAsync { db in
            try db.execute(sql: """
                INSERT INTO jars (id, name, description, owner_did, created_at, last_sequence_number, parent_cid)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                id,
                name,
                description,
                ownerDID,
                Date().timeIntervalSince1970,
                lastSequenceNumber,
                parentCID
            ])
        }

        // Fetch and return
        return try await db.readAsync { db in
            try Jar.fetchOne(db, sql: "SELECT * FROM jars WHERE id = ?", arguments: [id])!
        }
    }

    // MARK: - Read

    func getJar(_ jarID: String) async throws -> Jar? {
        try await db.readAsync { db in
            try Jar.fetchOne(db, sql: "SELECT * FROM jars WHERE id = ?", arguments: [jarID])
        }
    }

    func getAllJars() async throws -> [Jar] {
        try await db.readAsync { db in
            try Jar.fetchAll(db, sql: """
                SELECT * FROM jars
                WHERE id NOT IN (SELECT jar_id FROM jar_tombstones)
                ORDER BY created_at DESC
            """)
        }
    }

    // MARK: - Update

    func updateLastSequence(_ jarID: String, _ sequenceNumber: Int) async throws {
        try await db.writeAsync { db in
            try db.execute(sql: """
                UPDATE jars
                SET last_sequence_number = ?
                WHERE id = ?
            """, arguments: [sequenceNumber, jarID])
        }
    }

    func updateParentCID(_ jarID: String, _ parentCID: String) async throws {
        try await db.writeAsync { db in
            try db.execute(sql: """
                UPDATE jars
                SET parent_cid = ?
                WHERE id = ?
            """, arguments: [parentCID, jarID])
        }
    }

    // MARK: - Delete

    func delete(_ jarID: String) async throws {
        try await db.writeAsync { db in
            try db.execute(sql: "DELETE FROM jars WHERE id = ?", arguments: [jarID])
            try db.execute(sql: "DELETE FROM jar_members WHERE jar_id = ?", arguments: [jarID])
        }
    }
}
```

#### 3. `Core/ChaingeKernel/ReceiptCanonicalizer.swift` (MODIFY, ~80 lines added)

**Add encoding methods for jar.created:**

```swift
extension ReceiptCanonicalizer {

    // MARK: - Jar Receipt Payload Encoding

    /**
     * Encode jar receipt envelope (outer layer)
     *
     * Contains: jar_id, receipt_type, sender_did, timestamp, parent_cid, payload
     * Does NOT contain: sequence_number (relay assigns)
     */
    static func encodeJarReceiptPayload(
        jarID: String,
        receiptType: String,
        senderDID: String,
        timestamp: Int64,
        parentCID: String?,
        payload: Data
    ) throws -> Data {
        let encoder = CBOREncoder()

        var map: [CBORValue: CBORValue] = [
            .text("jar_id"): .text(jarID),
            .text("receipt_type"): .text(receiptType),
            .text("sender_did"): .text(senderDID),
            .text("timestamp"): .int(timestamp),
            .text("payload"): .bytes([UInt8](payload))
        ]

        // Add parent_cid if present
        if let parentCID = parentCID {
            map[.text("parent_cid")] = .text(parentCID)
        }

        // Encode to canonical CBOR (sorted keys)
        let cbor = try encoder.encode(CBORValue.map(map.sorted { $0.key < $1.key }))
        return cbor
    }

    /**
     * Encode jar.created payload (inner layer)
     */
    static func encodeJarCreatedPayload(
        jarName: String,
        jarDescription: String?,
        ownerDID: String,
        createdAtMs: Int64
    ) throws -> Data {
        let encoder = CBOREncoder()

        var map: [CBORValue: CBORValue] = [
            .text("jar_name"): .text(jarName),
            .text("owner_did"): .text(ownerDID),
            .text("created_at_ms"): .int(createdAtMs)
        ]

        if let desc = jarDescription {
            map[.text("jar_description")] = .text(desc)
        }

        let cbor = try encoder.encode(CBORValue.map(map.sorted { $0.key < $1.key }))
        return cbor
    }
}
```

#### 4. `Core/Models/JarReceipts.swift` (MODIFY existing, add StoreReceiptResponse)

**The file already has all the receipt payload structs from Module 1. Add response model:**

```swift
// EXISTING: JarCreatedPayload, JarMemberAddedPayload, etc. (Module 1)

// NEW: Response from relay when storing a receipt
struct StoreReceiptResponse: Codable {
    let success: Bool
    let receiptCID: String
    let sequenceNumber: Int
    let jarID: String

    enum CodingKeys: String, CodingKey {
        case success
        case receiptCID = "receipt_cid"
        case sequenceNumber = "sequence_number"
        case jarID = "jar_id"
    }
}
```

#### 5. `Core/RelayClient+JarReceipts.swift` (MODIFY, update storeJarReceipt to parse response)

**Current implementation returns nothing. Update to return StoreReceiptResponse:**

```swift
extension RelayClient {
    // MODIFY: Return StoreReceiptResponse (was: async throws -> Void)
    func storeJarReceipt(
        jarID: String,
        receiptData: Data,
        signature: Data,
        parentCID: String?
    ) async throws -> StoreReceiptResponse {
        let headers = try await authHeader()
        let url = URL(string: "\(baseURL)/api/jars/\(jarID)/receipts")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }

        var body: [String: Any] = [
            "receipt_data": receiptData.base64EncodedString(),
            "signature": signature.base64EncodedString()
        ]

        if let parentCID = parentCID {
            body["parent_cid"] = parentCID
        }

        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, res) = try await URLSession.shared.data(for: req)
        let statusCode = (res as? HTTPURLResponse)?.statusCode ?? 0

        guard statusCode == 200 || statusCode == 201 else {
            if let errorBody = String(data: data, encoding: .utf8) {
                print("❌ Store jar receipt failed (HTTP \(statusCode)): \(errorBody)")
            }
            throw RelayError.httpError(statusCode: statusCode, message: "Failed to store jar receipt")
        }

        // Parse response
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let success = json?["success"] as? Bool,
              let receiptCID = json?["receipt_cid"] as? String,
              let sequenceNumber = json?["sequence_number"] as? Int,
              let jarID = json?["jar_id"] as? String else {
            throw RelayError.invalidResponse
        }

        return StoreReceiptResponse(
            success: success,
            receiptCID: receiptCID,
            sequenceNumber: sequenceNumber,
            jarID: jarID
        )
    }

    // EXISTING: Keep getJarReceipts(after:) from Module 5a
    // EXISTING: Keep getJarReceipts(from:to:) from Module 1
}
```

### Success Criteria

- ✅ Can create jar via JarManager.createJar()
- ✅ Jar.created receipt generated WITHOUT sequence
- ✅ Receipt sent to relay → relay assigns sequence
- ✅ Relay-assigned sequence stored locally
- ✅ Owner added to jar_members table (active)
- ✅ Jar appears in getAllJars()

### Testing

**Manual test (single device):**
1. Call `JarManager.shared.createJar(name: "Friends", description: nil)`
2. Verify jar appears in jars table
3. Verify last_sequence_number = 1 (or whatever relay assigned)
4. Verify owner in jar_members with status=active

**Manual test (two devices):**
1. Device A creates jar
2. Wait 30s for InboxManager polling
3. Device B should receive jar.created receipt
4. Verify jar appears on device B

---

## Relay Side (Already Implemented in Module 0.6)

**No changes needed** - Module 0.6 already implemented:
- ✅ `POST /api/jars/{jar_id}/receipts` - Store receipt + assign sequence
- ✅ `GET /api/jars/{jar_id}/receipts?after={seq}` - Sync API
- ✅ `GET /api/jars/{jar_id}/receipts?from={seq}&to={seq}` - Gap filling API
- ✅ Relay envelope architecture (sequence NOT in signed bytes)
- ✅ Membership validation (Upgrade E)

---

## Red Flags & Mitigations

### ❌ RED FLAG: Duplicate Polling Loops
**Mitigation:** Use existing InboxManager loop, just add jar polling after bud polling. Single 30s timer.

### ❌ RED FLAG: Jar Polling Storms (100 jars = 100 API calls every 30s)
**Mitigation:**
- Acceptable for MVP (most users have <5 jars)
- Future optimization: Batch API (`GET /api/jars/receipts?jar_ids=...`)
- Future optimization: SSE/WebSocket push (defer to Phase 11)

### ❌ RED FLAG: Jar Creation Fails if Relay Down
**Mitigation:**
- Optimistic create (jar exists locally immediately)
- Retry logic: Queue failed jar.created receipts
- Show "Syncing..." status in UI until relay confirms

### ✅ GREEN FLAG: Clean Architecture
- InboxManager = "router" (fetch + route)
- JarSyncManager = "processor" (verify + apply)
- No duplicate systems, no competing loops

---

## Implementation Order

**Module 5a first (sync loop):**
1. Modify InboxManager.swift (~50 lines)
2. Update RelayClient+JarReceipts.swift (~30 lines)
3. Test polling with curl (create fake receipts on relay)

**Module 5b second (jar creation):**
1. Create JarManager.swift (~150 lines)
2. Create JarRepository.swift (~120 lines)
3. Update ReceiptCanonicalizer.swift (~80 lines)
4. Update RelayClient+JarReceipts.swift (return response, ~20 lines)
5. Test jar creation end-to-end

---

## Total Estimated Time

- **Module 5a:** 2-3 hours (polling integration)
- **Module 5b:** 2-3 hours (jar creation)
- **Testing:** 1 hour (manual two-device tests)

**Total: 5-7 hours**

---

## Next Steps (Module 6)

After Module 5 complete:
- Module 6: Member invite flow (jar.member_added, jar.invite_accepted)
- Depends on: Jar creation (Module 5b) + sync loop (Module 5a)

---

**Ready for review?** Let me know if you see any architectural red flags or knots this might create!
