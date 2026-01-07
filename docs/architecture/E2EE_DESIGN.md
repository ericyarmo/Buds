# Buds End-to-End Encryption Design

**Last Updated:** January 6, 2026
**Version:** v0.2 (Phase 10.3 Modules 0.1-6.5 - Jar Infrastructure Complete)
**Security Level:** Private Jar Sharing (12 max)
**Status:** Multi-device jar sync working in production ✅

---

## Overview

Buds uses **hybrid encryption** to share memories with your Circle:
1. **X25519 key agreement** for recipient key wrapping (using stable device keys)
2. **AES-256-GCM** for payload encryption
3. **Per-message ephemeral AES keys** (each message uses a unique AES-256 key)
4. **Multi-device support** (wrap keys per device, not per DID)

---

## Threat Model

### In Scope

| Threat | Mitigation |
|--------|-----------|
| **Relay server compromise** | E2EE: server sees only ciphertext |
| **Network interception** | HTTPS + encrypted payloads |
| **Malicious Circle member** | They can decrypt + screenshot (trust model) |
| **Device theft (locked)** | iOS encryption + biometric auth |

### Out of Scope (v0.1)

- Forward secrecy (stable device X25519 keys, no per-message ephemeral X25519 keypairs)
- Post-compromise security (no key rotation, no Signal-style ratchet)
- Deniability (signatures prove authorship)
- Nation-state adversaries
- Post-quantum cryptography

**Note on key model:** v0.1 uses **stable device X25519 keys** for key wrapping (not per-message ephemeral X25519 keypairs). Each message uses a unique ephemeral AES-256 key, but the X25519 key agreement happens with long-lived device keys. This means no forward secrecy for key wrapping (but simpler device discovery). Future versions may add per-message ephemeral X25519 keys + key deletion for forward secrecy.

---

## Multi-Device Model

### Problem: DIDs vs Devices

**User scenario:**
- Alice has iPhone + iPad
- Both devices need to decrypt Circle messages
- Each device has its own keypair

**Solution: Device-based key wrapping**

Each device gets:
- `device_id`: UUID (stable across app launches)
- `owner_did`: User's DID (same across all their devices)
- `pubkey_x25519`: Device-specific X25519 public key
- `privkey_x25519`: Device-specific X25519 private key (keychain)

### Device Registration

**Database table:**

```sql
CREATE TABLE devices (
    device_id TEXT PRIMARY KEY NOT NULL,        -- UUID
    owner_did TEXT NOT NULL,                    -- User's DID (no FK - DIDs are self-sovereign)
    device_name TEXT NOT NULL,                  -- "Alice's iPhone"
    pubkey_x25519 TEXT NOT NULL,                -- Base64 public key
    pubkey_ed25519 TEXT NOT NULL,               -- Base64 signing key (for verification)
    status TEXT NOT NULL,                       -- 'active' | 'revoked'
    registered_at REAL NOT NULL,
    last_seen_at REAL
);

CREATE INDEX idx_devices_owner ON devices(owner_did);
CREATE INDEX idx_devices_status ON devices(status);
```

**Note:** No foreign key constraint on `owner_did` because DIDs are self-sovereign identifiers (not rows in a users table). The `circles` table tracks Circle members by DID, but devices can exist before/after Circle membership.

**Device registration flow:**

```swift
// On first launch or after sign-in
func registerDevice() async throws {
    let deviceId = try IdentityManager.shared.deviceId
    let ownerDID = try IdentityManager.shared.currentDID
    let deviceName = await UIDevice.current.name  // "Alice's iPhone"

    let x25519Keys = try IdentityManager.shared.getX25519Keypair()
    let ed25519Keys = try IdentityManager.shared.getEd25519Keypair()

    let device = Device(
        device_id: deviceId,
        owner_did: ownerDID,
        device_name: deviceName,
        pubkey_x25519: x25519Keys.publicKey.base64,
        pubkey_ed25519: ed25519Keys.publicKey.base64,
        status: "active",
        registered_at: Date()
    )

    // Send to relay server
    try await RelayClient.shared.registerDevice(device)

    // Broadcast to Circle (so they can encrypt for your new device)
    try await CircleManager.shared.broadcastDeviceRegistration(device)
}
```

---

## Encryption Flow

### Step 1: Sender Prepares Message

**Important:** We encrypt the **raw canonical CBOR bytes** from `ucr_headers.raw_cbor`, NOT a JSON re-encoding. This ensures:
1. Recipients can verify the signature (needs exact signed bytes)
2. No non-deterministic JSON encoding issues
3. Smaller payloads (CBOR is more compact than JSON)

```swift
func shareMemory(_ memoryCID: String, to circleDIDs: [String]) async throws {
    // 1. Load receipt's raw CBOR bytes (canonical form from DB)
    let receipt = try await ReceiptManager.shared.fetch(cid: memoryCID)
    let payloadData = receipt.raw_cbor  // Encrypt the canonical CBOR, not JSON

    // 2. Generate ephemeral AES key
    let aesKey = SymmetricKey(size: .bits256)

    // 3. Encrypt payload with AES-GCM
    let nonce = AES.GCM.Nonce()
    let sealed = try AES.GCM.seal(
        payloadData,
        using: aesKey,
        nonce: nonce,
        authenticating: memoryCID.data(using: .utf8)!  // AAD = receipt CID
    )

    // 4. Get all devices for recipient DIDs
    let recipientDevices = try await getDevicesFor(dids: circleDIDs)

    // 5. Wrap AES key for each device
    var wrappedKeys: [String: String] = [:]  // deviceId -> base64 wrapped key

    for device in recipientDevices {
        let wrapped = try wrapKey(
            aesKey,
            forRecipient: device.pubkey_x25519,
            senderPrivateKey: myX25519PrivateKey
        )
        wrappedKeys[device.device_id] = wrapped.base64EncodedString()
    }

    // 6. Create encrypted message
    let message = EncryptedMessage(
        message_id: UUID().uuidString,
        receipt_cid: memoryCID,
        encrypted_payload: sealed.combined,  // Combined: nonce || ciphertext || tag
        wrapped_keys: wrappedKeys,
        sender_did: myDID,
        sender_device_id: myDeviceId,
        relay_sent_at_ms: Int64(Date().timeIntervalSince1970 * 1000)  // Relay metadata only
    )

    // 7. Send to relay
    try await RelayClient.shared.postMessage(message)
}
```

### Step 2: Key Wrapping (X25519 + HKDF + AES-GCM)

```swift
func wrapKey(
    _ aesKey: SymmetricKey,
    forRecipient recipientPubkey: String,
    senderPrivateKey: Curve25519.KeyAgreement.PrivateKey
) throws -> Data {
    // 1. Parse recipient public key
    let recipientKey = try Curve25519.KeyAgreement.PublicKey(
        rawRepresentation: Data(base64Encoded: recipientPubkey)!
    )

    // 2. Perform X25519 key agreement
    let sharedSecret = try senderPrivateKey.sharedSecretFromKeyAgreement(
        with: recipientKey
    )

    // 3. Derive wrapping key with HKDF
    let wrappingKey = sharedSecret.hkdfDerivedSymmetricKey(
        using: SHA256.self,
        salt: Data(),
        sharedInfo: "buds.wrap.v1".data(using: .utf8)!,
        outputByteCount: 32
    )

    // 4. Wrap AES key with AES-GCM
    let wrapNonce = AES.GCM.Nonce()
    let sealed = try AES.GCM.seal(
        aesKey.withUnsafeBytes { Data($0) },
        using: wrappingKey,
        nonce: wrapNonce
    )

    // 5. Return: nonce || ciphertext || tag
    var result = Data()
    result.append(wrapNonce.withUnsafeBytes { Data($0) })
    result.append(sealed.ciphertext)
    result.append(sealed.tag)

    return result
}
```

### Step 3: Recipient Decrypts

```swift
func receiveMessage(_ encryptedMessage: EncryptedMessage) async throws -> Memory {
    // 1. Find wrapped key for my device
    guard let wrappedKeyB64 = encryptedMessage.wrapped_keys[myDeviceId] else {
        throw E2EEError.noKeyForDevice
    }

    let wrappedKeyData = Data(base64Encoded: wrappedKeyB64)!

    // 2. Unwrap AES key
    let aesKey = try unwrapKey(
        wrappedKeyData,
        fromSender: encryptedMessage.sender_device_id,
        myPrivateKey: myX25519PrivateKey
    )

    // 3. Decrypt payload
    let sealedBox = try AES.GCM.SealedBox(combined: encryptedMessage.encrypted_payload)

    let rawCBOR = try AES.GCM.open(
        sealedBox,
        using: aesKey,
        authenticating: encryptedMessage.receipt_cid.data(using: .utf8)!  // AAD = receipt CID
    )

    // 4. Decode receipt from CBOR and verify signature
    let receipt = try ReceiptManager.shared.parseAndVerify(
        raw_cbor: rawCBOR,
        expected_cid: encryptedMessage.receipt_cid
    )

    // 5. Store in local DB
    try await Database.shared.saveReceipt(receipt, raw_cbor: rawCBOR)

    return receipt
}
```

### Step 4: Key Unwrapping

```swift
func unwrapKey(
    _ wrappedData: Data,
    fromSender senderDeviceId: String,
    myPrivateKey: Curve25519.KeyAgreement.PrivateKey
) throws -> SymmetricKey {
    // 1. Get sender's public key
    let senderDevice = try await getDevice(deviceId: senderDeviceId)
    let senderPubkey = try Curve25519.KeyAgreement.PublicKey(
        rawRepresentation: Data(base64Encoded: senderDevice.pubkey_x25519)!
    )

    // 2. Perform X25519 key agreement (same shared secret)
    let sharedSecret = try myPrivateKey.sharedSecretFromKeyAgreement(
        with: senderPubkey
    )

    // 3. Derive wrapping key with HKDF
    let wrappingKey = sharedSecret.hkdfDerivedSymmetricKey(
        using: SHA256.self,
        salt: Data(),
        sharedInfo: "buds.wrap.v1".data(using: .utf8)!,
        outputByteCount: 32
    )

    // 4. Parse wrapped data: nonce (12) || ciphertext || tag (16)
    let nonce = try AES.GCM.Nonce(data: wrappedData.prefix(12))
    let ciphertext = wrappedData.dropFirst(12).dropLast(16)
    let tag = wrappedData.suffix(16)

    let sealedBox = try AES.GCM.SealedBox(
        nonce: nonce,
        ciphertext: ciphertext,
        tag: tag
    )

    // 5. Unwrap AES key
    let unwrappedData = try AES.GCM.open(sealedBox, using: wrappingKey)

    return SymmetricKey(data: unwrappedData)
}
```

---

## Message Format

### Encrypted Message Schema

```swift
struct EncryptedMessage: Codable {
    let message_id: String                      // UUID (relay storage ID)
    let receipt_cid: String                     // CID of original receipt being shared
    let encrypted_payload: Data                 // AES-GCM sealed.combined (nonce || ciphertext || tag)
    let wrapped_keys: [String: String]          // deviceId -> base64 wrapped key
    let sender_did: String                      // Sender's DID (pseudonymous)
    let sender_device_id: String                // Sender's device ID
    let relay_sent_at_ms: Int64                 // Relay metadata only (not used for receipt ordering)
}
```

**Note on `encrypted_payload` format:** Contains the full `AES.GCM.SealedBox.combined` representation: nonce (12 bytes) || ciphertext (variable) || authentication tag (16 bytes). On decryption, use `AES.GCM.SealedBox(combined:)` initializer.

**Relay storage (D1 table):**

```sql
CREATE TABLE messages (
    message_id TEXT PRIMARY KEY NOT NULL,
    receipt_cid TEXT NOT NULL,                  -- CID of receipt being shared
    encrypted_payload BLOB NOT NULL,            -- sealed.combined (nonce || ciphertext || tag)
    wrapped_keys_json TEXT NOT NULL,            -- JSON map: deviceId -> base64 wrapped key
    sender_did TEXT NOT NULL,                   -- Pseudonymous sender DID
    sender_device_id TEXT NOT NULL,
    relay_sent_at_ms INTEGER NOT NULL,          -- Relay metadata (NOT used for receipt ordering)
    relay_received_at_ms INTEGER NOT NULL,      -- When relay received the message

    -- Delivery tracking
    delivered_to_json TEXT,                     -- JSON array of device_ids that fetched this
    expires_at_ms INTEGER                       -- Optional expiration (milliseconds)
);

CREATE INDEX idx_messages_receipt_cid ON messages(receipt_cid);
CREATE INDEX idx_messages_relay_sent_at ON messages(relay_sent_at_ms DESC);
```

**Note:** The relay stores **ciphertext only**. It cannot decrypt payloads or wrapped keys. Timestamps are relay metadata for housekeeping, NOT used for receipt ordering (receipts use causality via `parentCID` chains).

---

## Circle Device Discovery

### Problem: How to find all devices for a DID?

**Solution: Query relay's device registry**

Phase 6 uses a **privacy-preserving device discovery** model:
- Circle rosters are local-only (relay never sees your friend list)
- User adds friend by phone number
- Client hashes phone and queries relay for DID
- Client queries relay for all devices for that DID

**Adding a Circle member flow:**

```swift
func addCircleMember(phoneNumber: String, displayName: String) async throws {
    // 1. Hash phone number (SHA-256)
    let phoneHash = SHA256.hash(data: phoneNumber.data(using: .utf8)!)
        .map { String(format: "%02x", $0) }
        .joined()

    // 2. Lookup DID from relay
    let response = try await RelayClient.shared.lookupDID(phoneHash: phoneHash)
    guard let did = response.did else {
        throw CircleError.memberNotFound
    }

    // 3. Fetch all devices for DID
    let devices = try await RelayClient.shared.getDevices(did: did)

    // 4. Store member in local Circle (with real DID, status = active)
    let member = CircleMember(
        did: did,
        displayName: displayName,  // Local nickname
        phoneNumber: phoneNumber,  // Local display only
        pubkeyX25519: devices.first?.pubkey_x25519 ?? "",  // Primary device pubkey
        status: .active
    )
    try await Database.shared.saveCircleMember(member)

    // 5. Store all devices locally (for multi-device E2EE)
    for device in devices {
        try await Database.shared.saveDevice(device)
    }
}
```

**Relay API endpoints:**

```
POST /api/lookup/did
Body: { phoneHash: "sha256..." }
Response: { did: "did:buds:abc123" }

GET /api/devices/list?dids=did:buds:abc123,did:buds:xyz789
Headers: Authorization: Bearer <firebase_id_token>
Response: [Device]
```

**Security requirements:**
- **Authentication required**: Must include valid Firebase ID token
- **Rate limiting**: Max 20 requests/minute per user to prevent DID enumeration
- **Phone hash privacy**: Phone numbers are hashed client-side (relay never sees plaintext)

**Database query (Cloudflare D1):**

```sql
-- Lookup DID by hashed phone
SELECT did FROM phone_to_did
WHERE phone_hash = ?
LIMIT 1;

-- Fetch all devices for DID
SELECT device_id, owner_did, device_name, pubkey_x25519, pubkey_ed25519
FROM devices
WHERE owner_did = ?
  AND status = 'active'
ORDER BY last_seen_at DESC;
```

**Privacy note:**
- Relay sees hashed phone numbers (not plaintext)
- Relay sees which devices are queried (metadata leakage), but doesn't know *why* (no Circle roster on server)
- DID enumeration is rate-limited but not prevented (public device registry by design)

---

## Key Rotation & Revocation

### Revoking a Device

```swift
func revokeDevice(_ deviceId: String) async throws {
    // 1. Mark device as revoked locally
    try await Database.shared.updateDevice(deviceId, status: "revoked")

    // 2. Notify relay
    try await RelayClient.shared.revokeDevice(deviceId)

    // 3. Broadcast revocation to Circle
    try await CircleManager.shared.broadcastDeviceRevocation(deviceId)
}
```

**Implications:**
- Device can no longer decrypt new messages
- Old messages remain readable (no forward secrecy in v0.1)
- Circle members stop wrapping keys for this device

---

## Security Properties

### What We Achieve

✅ **Confidentiality**: Only intended recipients can decrypt
✅ **Authenticity**: Signatures prove authorship
✅ **Integrity**: AEAD (GCM) detects tampering
✅ **Multi-device**: Each device can decrypt independently

### What We Don't Achieve (v0.1)

❌ **Forward secrecy**: Compromised key reveals all past messages
❌ **Post-compromise security**: No key rotation/ratcheting
❌ **Deniability**: Signatures are non-repudiable
❌ **Anti-screenshot**: Circle members can screenshot/copy

---

## Attack Scenarios & Mitigations

### 1. Relay Server Compromise

**Attack:** Attacker gains access to Cloudflare D1 database

**What they see:**
- Encrypted payloads (ciphertext)
- Wrapped keys (ciphertext)
- Pseudonymous identifiers (DIDs, device IDs)
- Metadata graph (who messages whom, when)
- Timestamps

**What they can't see:**
- Plaintext message contents
- Unwrapped AES keys
- Real-world identities (DIDs are not directly linked to names/phones)

**Important distinction:** Relay sees **pseudonymous** identifiers and metadata, NOT plaintext contents. Pseudonymous ≠ anonymous. The relay can build a social graph (DID A messages DIDs B, C, D frequently) but cannot read message contents or definitively link DIDs to real identities (unless combined with external data).

**Mitigation:** Strong E2EE ensures relay is untrusted for content confidentiality.

---

### 2. Stolen Device (Unlocked)

**Attack:** Attacker has physical access to unlocked device

**What they can access:**
- All local receipts (plaintext in GRDB)
- Private keys (from keychain, if device unlocked)
- Decrypt incoming messages

**Mitigation:**
- iOS auto-lock timeout
- Biometric re-auth for sensitive operations
- Remote device revocation

---

### 3. Malicious Circle Member

**Attack:** Alice invites Bob, Bob decrypts her messages and screenshots them

**What Bob can do:**
- Decrypt all messages Alice shares with Circle
- Screenshot, copy, re-share outside Buds
- Cannot forge Alice's signature (he doesn't have her private key)

**Mitigation:**
- Trust model: Circle = trusted friends
- UI warns: "Bob can screenshot or copy this"
- Unshare + revoke removes future access (not past access)

---

### 4. Key Wrapping Replay Attack

**Attack:** Attacker replays old wrapped key

**Mitigation:**
- Each message has unique AES key (no key reuse)
- Replay of old message just delivers old content (harmless)
- Timestamps help detect stale messages

---

## Performance Characteristics

### Encryption Overhead

**NOTE:** The following are **rough estimates** based on typical CryptoKit performance on modern iOS devices. Actual performance will vary based on device, iOS version, and payload size. These numbers have **not been benchmarked** in the Buds implementation and should be verified before making performance claims.

**Single message to 12 Circle members (2 devices each = 24 wraps):**

| Operation | Estimated Time (iPhone 14) |
|-----------|------------------|
| AES-256-GCM encrypt (5KB payload) | ~0.5 ms |
| X25519 key agreement (1x) | ~0.2 ms |
| HKDF derivation (1x) | ~0.1 ms |
| AES-256-GCM wrap (24x) | ~12 ms |
| **Total** | **~13 ms** |

**Decryption (single recipient):**

| Operation | Estimated Time |
|-----------|------|
| X25519 key agreement | ~0.2 ms |
| HKDF derivation | ~0.1 ms |
| AES-256-GCM unwrap | ~0.5 ms |
| AES-256-GCM decrypt | ~0.5 ms |
| **Total** | **~1.3 ms** |

**Expected conclusion:** E2EE overhead should be negligible (< 15ms for full Circle share), but **must be benchmarked** in production code to confirm.

---

## Implementation Checklist

- [ ] Implement device registration flow
- [ ] Create `devices` table in GRDB
- [ ] Add X25519 keypair generation to `IdentityManager`
- [ ] Implement `wrapKey()` and `unwrapKey()`
- [ ] Create `EncryptedMessage` struct and database schema
- [ ] Add relay API endpoints (`/v1/messages`, `/v1/devices`)
- [ ] Test with 2+ devices per user
- [ ] Add device revocation UI
- [ ] Write unit tests for key wrapping
- [ ] Audit crypto implementation with external review (before production)

---

## Reactions E2EE (Phase 10.1)

### Overview

Reactions are lightweight E2EE receipts that allow jar members to react to shared memories. Each reaction is a signed receipt encrypted and shared across all jar members using the same E2EE infrastructure as memory sharing.

### Reaction Receipt Types

```
app.buds.memory.reaction.created/v1 - User adds a reaction
app.buds.memory.reaction.removed/v1 - User removes a reaction
```

### Reaction Payload Structure

```swift
struct ReactionPayload: ReceiptPayload {
    let claimed_time_ms: Int64          // Required: when reaction was created
    let memory_cid: String              // CID of memory being reacted to
    let reaction_type: String           // 'heart' | 'fire' | 'laughing' | 'mind_blown' | 'chilled'
    let jar_id: String                  // Jar context for E2EE distribution
}
```

### Encryption Flow

**Creating a Reaction:**

```
1. User taps reaction emoji (e.g., ❤️) on a shared memory
2. Create ReactionPayload with memory_cid, reaction_type, jar_id
3. Generate UCRHeader receipt (signed with user's Ed25519 key)
4. Encrypt receipt using same E2EE flow as memory sharing:
   - Generate ephemeral AES-256 key
   - Encrypt raw_cbor with AES-GCM
   - Wrap AES key for each jar member's devices
5. Send encrypted reaction via relay
6. Each jar member's device receives + decrypts reaction
7. Insert into local `reactions` table
```

### Toggle Behavior

Reactions use **toggle semantics**:
- Tap once → Add reaction (create `reaction.created/v1` receipt)
- Tap again → Remove reaction (create `reaction.removed/v1` receipt)
- Each user can have one reaction per type per memory
- Removed reactions are tombstoned (not deleted from database)

### Performance Optimization

Reactions are **small payloads** (~200 bytes), making E2EE overhead minimal:

| Operation | Estimated Time (12 members, 2 devices each) |
|-----------|---------------------------------------------|
| Encrypt reaction payload | ~0.3 ms |
| Wrap AES key (24x) | ~12 ms |
| Total encryption | **~12.3 ms** |

**Decryption** per recipient: ~1.3 ms (same as memory decryption)

### UI Aggregation

**Summary Display:**
```swift
struct ReactionSummary {
    let type: ReactionType              // .heart, .fire, etc.
    let count: Int                      // Number of users who reacted
    let senderDIDs: [String]            // List of DIDs (for future "who reacted" feature)
}
```

The UI fetches all reactions for a memory and aggregates by type to show counts (e.g., "❤️ 3  🔥 2").

### Future Enhancement: "Who Reacted"

**Press and hold reaction bubble** to see which jar members reacted:
- Query `reactions` table for `memory_id` + `reaction_type`
- Join with `circles` table to get display names
- Show list of members who reacted (E2EE preserving)

---

## Future Enhancements (Post-v0.1)

### Forward Secrecy

**Goal:** Compromised key doesn't reveal past messages

**Approach:** Double Ratchet (Signal-style)
- Ephemeral keypairs per message
- Key deletion after use

### Post-Compromise Security

**Goal:** Recover from key compromise

**Approach:** Periodic key rotation
- Generate new device keypair every 30 days
- Re-wrap old messages (optional)

### Deniability

**Goal:** Plausible deniability for authorship

**Approach:** Ring signatures or group signatures
- Prove "someone in Circle" sent it, not specifically Alice

---

## Core Architecture Truth

**The one paragraph every developer must internalize:**

Receipts are truth (CID + Ed25519 signature over canonical CBOR bytes). E2EE is just a transport envelope: we encrypt the **raw receipt CBOR** (from `ucr_headers.raw_cbor`) using AES-256-GCM, wrap the ephemeral AES key per recipient device using X25519 key agreement, relay stores ciphertext + wrapped keys + metadata, recipients decrypt the CBOR then verify the underlying receipt signature. The relay is untrusted (sees only ciphertext and pseudonymous identifiers), and receipts remain verifiable end-to-end because we never re-encode or transform the signed bytes.

**Key invariants:**
- Encrypt `raw_cbor` (canonical form), NOT JSON
- Use `sealed.combined` (nonce || ciphertext || tag), NOT separate fields
- Relay timestamps are metadata only, NOT used for receipt ordering (causality = `parentCID` chains)
- Device keys are stable (v0.1), NOT per-message ephemeral X25519 keypairs
- DIDs are pseudonymous, NOT anonymous (relay sees social graph metadata)

---

## Deployment Status (Phase 10.3 Modules 0.1-6.5)

### ✅ Working in Production (TestFlight Verified)

**Jar Infrastructure:**
- Multi-device jar sync (30s polling + automatic discovery)
- Jar creation with relay-assigned sequences
- Member management (add, remove, TOFU device pinning)
- Gap detection & queueing (handles out-of-order receipts)
- Background inbox polling (keychain access fixed)

**Crypto & Security:**
- Phone-based DID (same DID across devices)
- Deterministic phone encryption (AES-256-GCM)
- CBOR library pinned (SwiftCBOR 0.4.5 - prevents signature breaks)
- CID verification (relay matches iOS exactly)
- 4-layer security (CID + signature + auth + membership)
- DID namespace separation (Firebase UID for auth, DID for crypto)

**Relay Fixes:**
- Fixed DID extraction from receipt CBOR
- Fixed receipt processor (was stub, now fully implemented)
- Fixed BigInt → Number conversion for D1 database
- Fixed nested CBOR payload decoding
- Fixed jar_members SQL schema mismatches

### 🔜 Next: Module 7 (E2EE Bud Sharing)

**What's Left:**
- Add `jar_id` to bud receipt schema
- Validate jar membership before sharing buds
- Route incoming buds to correct jar
- UI: Share bud to specific jar (picker)

**Expected:** 2-3 hours → Complete E2EE jar sharing end-to-end!

**After Module 7:** E2EE will be fully functional for multi-device jar sharing.

---

**Next:** See [RELAY_SERVER.md](./RELAY_SERVER.md) for Cloudflare Workers API spec.
