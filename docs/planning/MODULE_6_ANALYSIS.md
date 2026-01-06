# Phase 10.3 Module 6: Member Invite Flow - Senior Systems Engineer Review

## Executive Summary

Module 6 transforms `JarManager.addMember()` from **client-local operation** to **receipt-based distributed operation**, following the same pattern established in Module 5b (jar creation).

**Current State**: `addMember()` directly inserts into `jar_members` table (local-only)
**Target State**: `addMember()` generates `jar.member_added` receipt → relay broadcasts → all jar members process

---

## Architecture Analysis

### Existing Code (Module 4 - Already Complete)

**JarSyncManager** already has receipt processors:
- `applyMemberAdded()` - Creates member with status="pending" (JarSyncManager.swift:396-419)
- `applyInviteAccepted()` - Updates status to "active" (JarSyncManager.swift:424-443)

**JarManager.addMember()** currently does (lines 222-264):
1. Phone → DID lookup via relay
2. Fetch ALL devices for invitee DID
3. TOFU pin ALL devices to local `devices` table
4. Direct INSERT into `jar_members` table
5. ❌ NO receipt generation

### Module 6 Implementation Goal

Transform `addMember()` to follow Module 5b pattern:

```swift
// BEFORE (Module 5):
func addMember(jarID: String, phoneNumber: String, displayName: String) async throws {
    // 1. Phone → DID lookup
    // 2. Pin devices (TOFU)
    // 3. Direct INSERT into jar_members
}

// AFTER (Module 6):
func addMember(jarID: String, phoneNumber: String, displayName: String) async throws {
    // 1. Phone → DID lookup (same)
    // 2. Pin devices (TOFU - same)
    // 3. Generate jar.member_added receipt payload
    // 4. Wrap in jar receipt envelope (NO sequence)
    // 5. Compute CID + sign
    // 6. Send to relay → relay assigns sequence + broadcasts
    // 7. Assert local CID == relay CID
    // 8. Update jar's lastSequenceNumber + parentCID
}
```

---

## 🚨 RED FLAGS IDENTIFIED

### RED FLAG #1: TOFU Device Pinning Broadcast Problem ⚠️  CRITICAL

**Problem**:
Current implementation pins devices when **inviter** adds member (JarManager.swift:238-251). But with receipt-based architecture:

1. **Inviter** adds member → pins invitee's devices → generates receipt → sends to relay
2. **Relay** broadcasts `jar.member_added` to all jar members
3. **Other jar members** receive receipt → process `applyMemberAdded()` → ❌ **DON'T have invitee's device keys**
4. **Invitee** can't send/receive E2EE messages because other members lack their X25519 pubkeys

**Current applyMemberAdded() implementation** (JarSyncManager.swift:402-416):
```swift
try db.execute(sql: """
    INSERT OR REPLACE INTO jar_members (jar_id, did, display_name, phone_number, ...)
    VALUES (?, ?, ?, ?, ...)
""", arguments: [envelope.jarID, payload.memberDID, ...])
```

❌ **Missing**: Device pinning logic
❌ **Missing**: X25519 pubkey for encryption

**Solutions**:

**Option A: Include Device Pubkeys in Receipt Payload** (RECOMMENDED)
- Pro: All jar members get devices when processing receipt
- Pro: No additional relay round-trips
- Con: Slightly larger receipt payload (~200 bytes per device)
- Con: Devices are public metadata (but already on relay)

**Option B: Fetch Devices On-Demand**
- Each jar member calls `DeviceManager.getDevices(for: [memberDID])` when processing receipt
- Pro: Smaller receipt payload
- Con: N parallel relay fetches (load spike)
- Con: Race condition if relay slow

**Option C: Lazy Device Pinning**
- Only pin devices when first E2EE message arrives
- Pro: Defers cost until needed
- Con: Complex error handling (send fails if not pinned yet)
- Con: Breaks existing architecture (TOFU = pin on add)

**RECOMMENDED: Option A** - Include device list in jar.member_added receipt payload.

---

### RED FLAG #2: jar_members Table Schema Mismatch ⚠️  CRITICAL

**Problem**:
`applyMemberAdded()` SQL doesn't match jar_members table schema.

**Current applyMemberAdded() INSERT** (JarSyncManager.swift:403-415):
```sql
INSERT OR REPLACE INTO jar_members
(jar_id, did, display_name, phone_number, role, status, added_at, added_by_did)
VALUES (?, ?, ?, ?, ?, ?, ?, ?)
```

**Actual jar_members table schema** (from JarMember.swift):
```swift
struct JarMember {
    var jarID: String
    var memberDID: String           // ❌ SQL uses "did" not "member_did"
    var displayName: String
    var phoneNumber: String?
    var avatarCID: String?          // ❌ Missing from SQL
    var pubkeyX25519: String        // ❌ Missing from SQL (CRITICAL for E2EE!)
    var role: Role
    var status: Status
    var joinedAt: Date?             // ❌ Missing from SQL
    var invitedAt: Date?            // ❌ Missing from SQL
    var removedAt: Date?
    var createdAt: Date             // ❌ Missing from SQL
    var updatedAt: Date             // ❌ Missing from SQL
}
```

**Issues**:
1. SQL uses `did` but table expects `member_did`
2. Missing `pubkey_x25519` (CRITICAL - can't encrypt!)
3. Missing `avatar_cid`, `joined_at`, `invited_at`, `created_at`, `updated_at`
4. SQL has `added_by_did` but table doesn't (column doesn't exist?)

**Solution**: Fix `applyMemberAdded()` SQL to match actual schema:
```sql
INSERT OR REPLACE INTO jar_members
(jar_id, member_did, display_name, phone_number, pubkey_x25519, avatar_cid,
 role, status, joined_at, invited_at, created_at, updated_at)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
```

---

### RED FLAG #3: Missing Receipt Encoder ⚠️  IMPLEMENTATION REQUIRED

**Problem**:
No `encodeJarMemberAddedPayload()` in ReceiptCanonicalizer.swift.

**What exists**: `encodeJarCreatedPayload()` (Module 5b)
**What's missing**: `encodeJarMemberAddedPayload()`

**Required implementation**:
```swift
// ReceiptCanonicalizer.swift
static func encodeJarMemberAddedPayload(
    memberDID: String,
    memberDisplayName: String,
    memberPhoneNumber: String,
    memberDevices: [DeviceInfo],  // NEW: Device list for TOFU
    addedByDID: String,
    addedAtMs: Int64
) throws -> Data {
    let enc = CBORCanonical()

    // Encode device list
    let devicesArray: [CBORValue] = memberDevices.map { device in
        .map([
            (.text("device_id"), .text(device.deviceId)),
            (.text("pubkey_ed25519"), .text(device.pubkeyEd25519)),
            (.text("pubkey_x25519"), .text(device.pubkeyX25519))
        ])
    }

    var pairs: [(CBORValue, CBORValue)] = [
        (.text("added_at_ms"), .int(addedAtMs)),
        (.text("added_by_did"), .text(addedByDID)),
        (.text("member_devices"), .array(devicesArray)),  // SOLUTION to Red Flag #1
        (.text("member_did"), .text(memberDID)),
        (.text("member_display_name"), .text(memberDisplayName)),
        (.text("member_phone_number"), .text(memberPhoneNumber))
    ]

    return try enc.encode(.map(pairs))
}
```

---

### RED FLAG #4: Unregistered User Handling 🚩  DESIGN DECISION NEEDED

**Problem**:
Current code throws `userNotRegistered` if invitee has no devices (JarManager.swift:234).

**Questions**:
1. Should we allow invites to users who haven't installed Buds yet?
2. If yes, what's the UX? (pending forever until they register?)
3. If no, how do we communicate this to inviter?

**Current behavior**:
```swift
guard !devices.isEmpty else {
    throw JarError.userNotRegistered  // ❌ Hard failure
}
```

**Options**:

**Option A: Keep Current Behavior** (RECOMMENDED for Module 6)
- Only registered users can be added
- Clean error message: "User hasn't registered with Buds yet"
- Simplifies implementation (no offline invite queue)

**Option B: Support Offline Invites**
- Create jar_member with status="unregistered"
- Periodic polling to check if user registered
- Auto-upgrade to "pending" when devices appear
- Complex: notification system, polling overhead

**RECOMMENDED: Option A** - Require registration first. Defer offline invites to future module.

---

### RED FLAG #5: Missing acceptInvite() API ⚠️  IMPLEMENTATION REQUIRED

**Problem**:
`applyInviteAccepted()` exists in JarSyncManager (receipt processor) but there's no user-facing API to **accept an invite**.

**What exists**:
- `applyInviteAccepted()` - Receipt processor (JarSyncManager.swift:424-443)

**What's missing**:
- `acceptInvite(jarID:)` - User-facing API in JarManager

**Required implementation**:
```swift
// JarManager.swift
func acceptInvite(jarID: String) async throws {
    let myDID = try await IdentityManager.shared.currentDID

    // 1. Verify invite exists and is pending
    let member = try await Database.shared.readAsync { db in
        try JarMember
            .filter(JarMember.Columns.jarID == jarID)
            .filter(JarMember.Columns.memberDID == myDID)
            .filter(JarMember.Columns.status == "pending")
            .fetchOne(db)
    }

    guard member != nil else {
        throw JarError.inviteNotFound
    }

    // 2. Generate jar.invite_accepted receipt
    let payloadCBOR = try ReceiptCanonicalizer.encodeJarInviteAcceptedPayload(
        memberDID: myDID,
        acceptedAtMs: Int64(Date().timeIntervalSince1970 * 1000)
    )

    // 3. Wrap in jar receipt envelope (NO sequence)
    let receiptCBOR = try ReceiptCanonicalizer.encodeJarReceiptPayload(
        jarID: jarID,
        receiptType: "jar.invite_accepted",
        senderDID: myDID,
        timestamp: Int64(Date().timeIntervalSince1970 * 1000),
        parentCID: nil,  // TODO: Should be jar's current parent_cid?
        payload: payloadCBOR
    )

    // 4. Compute CID + sign
    let receiptCID = CanonicalCBOREncoder.computeCID(from: receiptCBOR)
    let signature = try await IdentityManager.shared.sign(data: receiptCBOR)

    // 5. Send to relay → relay broadcasts
    let response = try await RelayClient.shared.storeJarReceipt(
        jarID: jarID,
        receiptData: receiptCBOR,
        signature: signature,
        parentCID: nil
    )

    // 6. Assert CID match
    guard receiptCID == response.receiptCID else {
        throw JarError.cidMismatch(local: receiptCID, relay: response.receiptCID)
    }

    print("✅ Invite accepted for jar: \(jarID)")
}
```

**Also need**: `encodeJarInviteAcceptedPayload()` in ReceiptCanonicalizer.

---

### RED FLAG #6: Multi-Device Race Condition 🚩  MINOR

**Problem**:
User has 2 devices. Adds member on Device A:
1. Device A: Generates jar.member_added → sends to relay
2. Relay: Broadcasts to Device A and Device B
3. Device A: Processes receipt → pins invitee devices
4. Device B: Processes receipt → pins invitee devices (duplicate work)

**Solution**:
Use `INSERT OR IGNORE` when pinning devices (already done in current code, JarManager.swift:246):
```swift
if !exists {
    try device.insert(db)  // ✅ Already idempotent
}
```

**Status**: ✅ Already handled correctly, not a critical issue.

---

### RED FLAG #7: Receipt Payload Size ⚠️  MINOR

**Problem**:
Including device list in jar.member_added receipt increases payload size.

**Calculation**:
- Base receipt: ~200 bytes
- Per device: ~150 bytes (deviceId=36, pubkey_ed25519=44, pubkey_x25519=44, overhead=26)
- 3 devices = 200 + (3 × 150) = **650 bytes per invite**

**Is this acceptable?**
- ✅ Yes - still tiny compared to bud receipts (images = KB-MB)
- ✅ Relay already stores full device list anyway
- ✅ Prevents N additional relay fetches

**Status**: ✅ Acceptable tradeoff.

---

## Implementation Plan

### Phase 1: Fix Existing Receipt Processors (JarSyncManager)

**File**: `JarSyncManager.swift`

1. **Fix applyMemberAdded() SQL** (lines 402-416):
   - Change `did` → `member_did`
   - Add `pubkey_x25519`, `avatar_cid`, `created_at`, `updated_at`
   - Add device pinning logic (fetch from payload, insert into devices table)

2. **Update decodeJarMemberAddedPayload()** (lines 1228-1248):
   - Add `member_devices` field (array of device objects)
   - Return devices in payload struct

### Phase 2: Add Receipt Encoders (ReceiptCanonicalizer)

**File**: `ReceiptCanonicalizer.swift`

1. **Add encodeJarMemberAddedPayload()**:
   - Include: memberDID, displayName, phoneNumber, devices[], addedByDID, addedAtMs
   - Sort devices by deviceId (canonical ordering)

2. **Add encodeJarInviteAcceptedPayload()**:
   - Include: memberDID, acceptedAtMs

### Phase 3: Update JarManager API

**File**: `JarManager.swift`

1. **Update addMember()** (lines 222-264):
   - Keep phone → DID lookup
   - Keep TOFU device pinning
   - Generate jar.member_added receipt
   - Send to relay → verify CID → update jar sequence

2. **Add acceptInvite()**:
   - Generate jar.invite_accepted receipt
   - Send to relay → verify CID

### Phase 4: Update JarRepository

**File**: `JarRepository.swift`

**No changes needed** - schema already supports all fields.

---

## Database Considerations

### Migration Required?

Check if `jar_members` table has all columns:
```sql
PRAGMA table_info(jar_members);
```

Expected columns:
- jar_id
- member_did
- display_name
- phone_number
- avatar_cid
- pubkey_x25519
- role
- status
- joined_at
- invited_at
- removed_at
- created_at
- updated_at

**If missing**: Create migration v9 to add missing columns.

---

## Testing Strategy

### Unit Tests
1. Test `encodeJarMemberAddedPayload()` produces canonical CBOR
2. Test `decodeJarMemberAddedPayload()` round-trip
3. Test device pinning idempotency

### Integration Tests
1. User A adds User B → verify receipt generated
2. User B receives jar.member_added → verify devices pinned
3. User B accepts invite → verify receipt generated
4. User A receives jar.invite_accepted → verify status updated

### Edge Cases
1. Add member who's already in jar (idempotency)
2. Accept invite twice (idempotency)
3. Add member with 0 devices (should fail with userNotRegistered)
4. Add member with 10 devices (stress test payload size)

---

## Files to Modify

1. **JarSyncManager.swift** (~100 lines):
   - Fix `applyMemberAdded()` SQL
   - Add device pinning in `applyMemberAdded()`
   - Update `decodeJarMemberAddedPayload()`
   - Add payload structs for device info

2. **ReceiptCanonicalizer.swift** (~80 lines):
   - Add `encodeJarMemberAddedPayload()`
   - Add `encodeJarInviteAcceptedPayload()`

3. **JarManager.swift** (~120 lines):
   - Update `addMember()` to generate receipt
   - Add `acceptInvite()` method

4. **JarError.swift** (~2 lines):
   - Add `.inviteNotFound` error case

**Total**: ~300 lines of changes

---

## Dependency Chain

```
Module 5b (jar creation) ✅ COMPLETE
    ↓
Module 6 (member invite flow) ← WE ARE HERE
    ↓
Module 7 (bud sharing in jars)
```

---

## Open Questions for User

1. **Device List in Receipt**: Confirm Option A (include devices in receipt payload) is acceptable?
2. **Offline Invites**: Confirm we skip offline invite support for Module 6?
3. **Parent CID**: Should `jar.invite_accepted` include the jar's current parent_cid, or leave it nil?

---

## Estimated Implementation Time

- Phase 1 (Fix processors): 1.5 hours
- Phase 2 (Add encoders): 1 hour
- Phase 3 (Update JarManager): 2 hours
- Phase 4 (Testing): 1 hour

**Total**: ~5.5 hours

---

## Conclusion

Module 6 is **architecturally sound** with the red flags addressed:
- ✅ Device pinning solved by including devices in receipt payload
- ✅ Schema mismatch fixed with proper SQL updates
- ✅ Missing encoders added to ReceiptCanonicalizer
- ✅ Unregistered users handled by requiring registration first
- ✅ acceptInvite() API added to complete invite flow
- ✅ Multi-device races already handled with idempotent inserts

**READY TO IMPLEMENT** pending user approval on:
1. Device list in receipt payload (recommended)
2. Skip offline invites for now (recommended)
3. Parent CID handling for jar.invite_accepted
