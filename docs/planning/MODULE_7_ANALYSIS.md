# Phase 10.3 Module 7: Bud Sharing with jar_id - Senior Systems Engineer Review

## Executive Summary

Module 7 connects the bud receipt system with the jar sync system. Currently, buds are created with `jar_id` in local_receipts table (migration v5), but the **E2EE sharing flow ignores jar_id entirely**. This means:
- ✅ Buds have jar_id locally (DB schema ready)
- ❌ Shared buds don't include jar_id (ShareManager broken)
- ❌ Received buds go to "Solo" jar hardcoded (InboxManager broken)

**Goal**: Make jar_id first-class in the sharing flow so received buds land in the correct jar.

---

## Current Architecture (BROKEN)

### What Works ✅
1. **local_receipts table** has `jar_id` column (migration v5)
2. **Bud creation** assigns jar_id when saving locally
3. **JarSyncManager** has `applyBudShared()` receipt handler (Module 3)

### What's Broken ❌

**ShareManager.swift (Lines 20-49)**:
```swift
func shareMemory(memoryCID: String, with circleDIDs: [String]) async throws {
    // 1. Fetch raw CBOR from database ✅
    let rawCBOR = try await Database.shared.readAsync { db in
        try UCRHeaderRow.fetchOne(db, sql: "SELECT * FROM ucr_headers WHERE cid = ?", arguments: [memoryCID])?.rawCBOR
    }

    // 2. Encrypt message for all devices ❌ NO JAR_ID
    let encrypted = try await E2EEManager.shared.encryptMessage(
        receiptCID: memoryCID,
        rawCBOR: rawCBOR,
        recipientDevices: devices
    )

    // 3. Send to relay ❌ NO JAR_ID
    try await RelayClient.shared.sendMessage(encrypted)
}
```

**Problem**: Encrypted message payload has NO jar_id. Receiver has no idea which jar this bud belongs to.

---

## 🚨 RED FLAGS IDENTIFIED

### RED FLAG #1: ShareManager Doesn't Send jar_id ⚠️ **CRITICAL**

**Problem**:
`ShareManager.shareMemory()` sends encrypted bud receipt but doesn't include jar_id in the envelope.

**Current E2EE Message Structure** (E2EEManager):
```swift
struct EncryptedMessage {
    let recipientDID: String
    let recipientDeviceId: String
    let receiptCID: String         // ✅ Has this
    let encryptedPayload: Data     // The bud receipt CBOR
    let senderDID: String
    let senderDeviceId: String
    // ❌ NO jar_id!
}
```

**Impact**: Receiver gets bud but doesn't know which jar it belongs to.

**Solution**: Add `jar_id` field to EncryptedMessage struct and RelayClient.sendMessage().

---

### RED FLAG #2: InboxManager Hardcodes jar_id="solo" ⚠️ **CRITICAL**

**Problem**:
When InboxManager receives a bud, it likely saves with hardcoded jar_id="solo" (need to verify this).

**Expected behavior**:
- Extract jar_id from encrypted message metadata
- Validate user is member of that jar
- Save bud to correct jar

**Current behavior** (SUSPECTED):
```swift
// InboxManager probably does this:
try await db.writeAsync { db in
    try db.execute(sql: """
        INSERT INTO local_receipts (uuid, header_cid, jar_id, ...)
        VALUES (?, ?, 'solo', ...)  // ❌ HARDCODED!
    """, arguments: [...])
}
```

**Solution**: Extract jar_id from message, validate membership, use actual jar_id.

---

### RED FLAG #3: No Jar Membership Validation ⚠️ **SECURITY**

**Problem**:
Nothing prevents user from sharing bud to a jar they're not a member of.

**Attack vector**:
1. Alice creates jar with Bob
2. Alice gets removed from jar
3. Alice shares bud claiming it's for that jar
4. Bob receives bud, adds to jar (**WRONG - Alice not a member**)

**Solution**: Before sharing, validate sender is active member of target jar.

```swift
// ShareManager should do this:
guard let member = try await JarRepository.shared.getMembers(jarID: jarID)
    .first(where: { $0.memberDID == myDID && $0.status == .active }) else {
    throw ShareError.notJarMember
}
```

---

### RED FLAG #4: No jar_id in applyBudShared() ⚠️ **IMPLEMENTATION**

**Problem**:
`JarSyncManager.applyBudShared()` receipt handler (Module 3) doesn't use jar_id from jar receipt envelope.

**Current Implementation** (JarSyncManager.swift ~line 330):
```swift
func applyBudShared(_ envelope: RelayEnvelope) async throws {
    let payload = try decodeJarBudSharedPayload(envelope.receiptData)

    // payload has: budUUID, sharedByDID, sharedAtMs, budCID
    // ❌ NO jar_id extraction from envelope.jarID

    // Likely does:
    // Store bud with jar_id from envelope.jarID ← NEED TO IMPLEMENT
}
```

**Solution**: Extract `envelope.jarID` and use it when storing received bud.

---

### RED FLAG #5: Missing jar_id in UI Share Flow 🚩 **UX**

**Problem**:
Current share UI doesn't let user **choose which jar** to share to.

**Current UX** (suspected):
- User taps "Share"
- Picks contacts
- Bud gets shared (**to what jar?**)

**Correct UX**:
- User taps "Share"
- **Picks jar** (dropdown/picker)
- Picks contacts (filtered to jar members)
- Bud gets shared to that jar

**Files to update**:
- ShareView or wherever share UI lives
- Need jar picker component

---

### RED FLAG #6: Relay Message Schema Unknown 🚩 **SPEC NEEDED**

**Problem**:
Don't know if relay's encrypted_messages table has jar_id column.

**Need to verify**:
```sql
-- Does relay have this?
CREATE TABLE encrypted_messages (
    id TEXT PRIMARY KEY,
    recipient_did TEXT,
    recipient_device_id TEXT,
    sender_did TEXT,
    jar_id TEXT,  -- ❓ Does this exist?
    ...
)
```

**If missing**: Need relay migration to add jar_id column.

**Solution**: Check relay schema, add jar_id if needed.

---

### RED FLAG #7: jar.bud_shared Receipt Payload Missing Fields 🚩 **DESIGN**

**Current JarBudSharedPayload** (JarReceipts.swift):
```swift
struct JarBudSharedPayload: Codable {
    let budUUID: String           // ✅
    let sharedByDID: String       // ✅
    let sharedAtMs: Int64         // ✅
    let budCID: String            // ✅ For verification
    // ❌ Missing: jar_id (redundant but explicit)
}
```

**Should jar.bud_shared include jar_id?**
- Pro: Redundant validation (envelope.jarID should match payload.jar_id)
- Con: Redundant data (jar_id already in envelope)

**Recommendation**: Keep it simple - use envelope.jarID only. No need for redundancy.

---

## Architecture Design Decisions

### Decision 1: Where to Store jar_id in Message?

**Option A: In Encrypted Payload** (WRONG)
```swift
// Encrypt jar_id INSIDE the bud receipt
❌ Bad: jar_id is metadata, not part of the bud
❌ Bad: Can't route before decryption
```

**Option B: In Message Envelope** (CORRECT)
```swift
struct EncryptedMessage {
    let recipientDID: String
    let recipientDeviceId: String
    let receiptCID: String
    let jar_id: String  // ✅ PLAINTEXT metadata
    let encryptedPayload: Data  // The bud receipt (encrypted)
    ...
}
```

**Recommendation**: Option B - jar_id is routing metadata, store in envelope.

---

### Decision 2: Validate Membership Client-Side or Server-Side?

**Option A: Client-Side Only**
```swift
// ShareManager validates before sending
✅ Pro: Prevents wasted relay requests
❌ Con: Attacker can bypass by calling RelayClient directly
```

**Option B: Server-Side Only**
```swift
// Relay validates jar membership
✅ Pro: Authoritative validation
❌ Con: Wasted encryption + network if not a member
```

**Option C: Both** (RECOMMENDED)
```swift
// Client validates (UX fast feedback)
// Relay validates (security enforcement)
✅ Pro: Best of both worlds
```

**Recommendation**: Option C - validate in both places.

---

### Decision 3: jar_id in jar.bud_shared Receipt?

**Option A: Include jar_id in Payload**
```swift
struct JarBudSharedPayload {
    let budUUID: String
    let jar_id: String  // ✅ Redundant validation
    ...
}
```

**Option B: Omit jar_id** (Use envelope.jarID)
```swift
// jar_id comes from RelayEnvelope.jarID
✅ Pro: No redundant data
✅ Pro: Simpler payload
```

**Recommendation**: Option B - use envelope.jarID.

---

## Implementation Plan

### Phase 1: Update E2EE Message Structure

**File**: `Core/Models/EncryptedMessage.swift` (or wherever it's defined)

1. Add `jar_id` field to EncryptedMessage struct
2. Update E2EEManager.encryptMessage() signature:
   ```swift
   func encryptMessage(
       receiptCID: String,
       rawCBOR: Data,
       jar_id: String,  // NEW
       recipientDevices: [Device]
   ) async throws -> EncryptedMessage
   ```

---

### Phase 2: Update ShareManager

**File**: `Core/ShareManager.swift`

1. **Change signature**:
   ```swift
   func shareMemory(memoryCID: String, jarID: String, with circleDIDs: [String]) async throws
   ```

2. **Validate membership**:
   ```swift
   let myDID = try await IdentityManager.shared.currentDID
   let members = try await JarRepository.shared.getMembers(jarID: jarID)
   guard members.contains(where: { $0.memberDID == myDID && $0.status == .active }) else {
       throw ShareError.notJarMember
   }
   ```

3. **Pass jar_id to encryption**:
   ```swift
   let encrypted = try await E2EEManager.shared.encryptMessage(
       receiptCID: memoryCID,
       rawCBOR: rawCBOR,
       jar_id: jarID,  // NEW
       recipientDevices: devices
   )
   ```

---

### Phase 3: Update RelayClient

**File**: `Core/RelayClient.swift`

1. **Update sendMessage() to include jar_id**:
   ```swift
   func sendMessage(_ message: EncryptedMessage) async throws {
       let body = [
           "recipient_did": message.recipientDID,
           "recipient_device_id": message.recipientDeviceId,
           "receipt_cid": message.receiptCID,
           "jar_id": message.jar_id,  // NEW
           "encrypted_payload": message.encryptedPayload.base64EncodedString(),
           ...
       ]
       // Send to relay
   }
   ```

---

### Phase 4: Update InboxManager

**File**: `Core/InboxManager.swift`

1. **Extract jar_id from incoming message**:
   ```swift
   guard let jarID = messageDict["jar_id"] as? String else {
       throw InboxError.missingJarID
   }
   ```

2. **Validate membership**:
   ```swift
   let myDID = try await IdentityManager.shared.currentDID
   let members = try await JarRepository.shared.getMembers(jarID: jarID)
   guard members.contains(where: { $0.memberDID == myDID && $0.status == .active }) else {
       print("⚠️  Not a member of jar \(jarID), ignoring bud")
       return  // Silently drop (not an error)
   }
   ```

3. **Save bud with correct jar_id**:
   ```swift
   try db.execute(sql: """
       INSERT INTO local_receipts (uuid, header_cid, jar_id, sender_did, ...)
       VALUES (?, ?, ?, ?, ...)
   """, arguments: [uuid, headerCID, jarID, senderDID, ...])
   ```

---

### Phase 5: Update JarSyncManager.applyBudShared()

**File**: `Core/JarSyncManager.swift`

**Current** (Module 3):
```swift
func applyBudShared(_ envelope: RelayEnvelope) async throws {
    let payload = try decodeJarBudSharedPayload(envelope.receiptData)

    // TODO: Store bud in jar
}
```

**Updated**:
```swift
func applyBudShared(_ envelope: RelayEnvelope) async throws {
    let payload = try decodeJarBudSharedPayload(envelope.receiptData)
    let jarID = envelope.jarID  // ✅ Extract from envelope

    print("📥 Processing bud shared: \(payload.budUUID) to jar \(jarID)")

    // Fetch bud receipt from relay
    let budReceipt = try await RelayClient.shared.getReceipt(cid: payload.budCID)

    // Store in local_receipts with jar_id
    try await db.writeAsync { db in
        try db.execute(sql: """
            INSERT OR IGNORE INTO local_receipts
            (uuid, header_cid, jar_id, sender_did, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
        """, arguments: [
            payload.budUUID,
            payload.budCID,
            jarID,  // ✅ Use jar_id from envelope
            payload.sharedByDID,
            Date().timeIntervalSince1970,
            Date().timeIntervalSince1970
        ])
    }

    // Store raw CBOR in ucr_headers
    try await db.writeAsync { db in
        try db.execute(sql: """
            INSERT OR IGNORE INTO ucr_headers
            (cid, raw_cbor, ...)
            VALUES (?, ?, ...)
        """, arguments: [payload.budCID, budReceipt, ...])
    }

    print("✅ Bud added to jar: \(jarID)")
}
```

---

### Phase 6: Update UI (Share Flow)

**Files**: ShareView or MemoryDetailView

1. **Add jar picker**:
   ```swift
   @State private var selectedJarID: String = "solo"

   Picker("Share to Jar", selection: $selectedJarID) {
       ForEach(jars) { jar in
           Text(jar.name).tag(jar.id)
       }
   }
   ```

2. **Filter contacts to jar members**:
   ```swift
   let jarMembers = try await JarRepository.shared.getMembers(jarID: selectedJarID)
   let memberDIDs = jarMembers.map { $0.memberDID }
   ```

3. **Pass jar_id to ShareManager**:
   ```swift
   try await ShareManager.shared.shareMemory(
       memoryCID: memoryCID,
       jarID: selectedJarID,
       with: selectedMemberDIDs
   )
   ```

---

## Files to Modify

1. **EncryptedMessage struct** (~10 lines):
   - Add `jar_id: String` field

2. **E2EEManager.swift** (~20 lines):
   - Add `jar_id` parameter to `encryptMessage()`
   - Include in message payload

3. **ShareManager.swift** (~30 lines):
   - Add `jarID` parameter
   - Validate membership before sharing
   - Pass jar_id to E2EE

4. **RelayClient.swift** (~10 lines):
   - Include jar_id in sendMessage() body

5. **InboxManager.swift** (~40 lines):
   - Extract jar_id from incoming message
   - Validate membership
   - Save with correct jar_id

6. **JarSyncManager.swift** (~50 lines):
   - Update `applyBudShared()` to use envelope.jarID
   - Fetch bud receipt from relay (or cache?)
   - Store in local_receipts with jar_id

7. **ShareView/MemoryDetailView** (~40 lines):
   - Add jar picker UI
   - Filter contacts to jar members
   - Pass jar_id to ShareManager

**Total**: ~200 lines of changes

---

## Relay Changes (Module 0.6 Review)

**Need to verify relay has**:
1. `encrypted_messages.jar_id` column (or add it)
2. Membership validation in POST /api/messages endpoint
3. jar_id in GET /api/inbox response

**If missing**: Create relay migration for jar_id support.

---

## Testing Strategy

### Unit Tests
1. Test ShareManager validates membership
2. Test InboxManager extracts jar_id correctly
3. Test applyBudShared() uses envelope.jarID

### Integration Tests
1. **Happy path**: Alice shares bud to jar → Bob receives in correct jar
2. **Membership validation**: Alice removed from jar → share fails
3. **Wrong jar**: Alice shares to jar A claiming jar B → rejected
4. **Multi-jar**: Bud in jar A stays in jar A, jar B has different buds

### Edge Cases
1. Share to Solo jar (should work)
2. Share to deleted jar (should fail)
3. Share to halted jar (should fail or queue?)
4. Receive bud for jar you left (should drop silently)

---

## Open Questions for User

1. **Relay Schema**: Does encrypted_messages table have jar_id column?
2. **Halted Jars**: Can you share to halted jars? (Probably not)
3. **Deleted Jars**: What if jar deleted after bud shared but before received?
4. **UI**: Where should jar picker go? (Share sheet? Memory detail?)
5. **Solo Jar**: Can you share to Solo jar? (Probably yes - still E2EE)

---

## Estimated Implementation Time

- Phase 1 (Message struct): 0.5 hours
- Phase 2 (ShareManager): 1 hour
- Phase 3 (RelayClient): 0.5 hours
- Phase 4 (InboxManager): 1.5 hours
- Phase 5 (JarSyncManager): 1 hour
- Phase 6 (UI): 1 hour
- Testing: 1 hour

**Total**: ~6.5 hours (original estimate was 2-3h, but more complex than expected)

---

## Conclusion

Module 7 is **architecturally straightforward** but touches many files. Main risks:
- ✅ jar_id schema already exists (migration v5)
- ✅ Receipt handlers exist (Module 3)
- ❌ E2EE message structure needs jar_id
- ❌ ShareManager needs membership validation
- ❌ InboxManager needs jar routing logic
- ❌ UI needs jar picker

**READY TO IMPLEMENT** pending user approval on:
1. jar_id in message envelope (not encrypted payload)
2. Both client + relay membership validation
3. jar_id from envelope.jarID (not in payload)
4. Relay schema confirmation

**RECOMMEND**: Get cofounder to register account first → test multi-device → then implement Module 7 with real data.
