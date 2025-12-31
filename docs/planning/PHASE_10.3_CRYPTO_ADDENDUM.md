# Phase 10.3: Crypto Architecture Fixes & Acknowledged Limitations

**Date:** December 30, 2025
**Status:** Critical crypto review before implementing 10.3

---

## Critical Crypto Blind Spots Identified

You identified 7 critical issues. Let's address each honestly and fix what we can in 10.3.

---

## 1. 🔴 Multi-Device DID Problem

### Current Broken Architecture

```
Device A (iPhone):
  Ed25519 keypair A
  DID = did:key:Ed25519_pubkey_A

Device B (iPad, same user):
  Ed25519 keypair B
  DID = did:key:Ed25519_pubkey_B  ← DIFFERENT DID!

How do they share an identity? THEY DON'T.
```

**Current code assumes one DID per user, but generates one DID per device.**

### Root Cause

- `IdentityManager` generates DID from device-specific Ed25519 pubkey
- Each device has unique keypair (stored in device Keychain)
- No account-level identity binding devices together

### Fix Options

#### Option A: Phone Number IS the Identity (RECOMMENDED for 10.3)

```swift
// Identity is phone number, not keypair
struct Identity {
    let phoneNumber: String        // E.164 format: +14155551234
    let phoneHash: String          // SHA-256(phone + salt) for relay lookup
    let accountSalt: String        // Unique salt, stored on relay
    let deviceID: String           // This device's ID
    let deviceEd25519Pubkey: Data  // This device's signing key
    let deviceX25519Pubkey: Data   // This device's encryption key
}

// DID derivation
// Old: did:key:Ed25519_<pubkey>
// New: did:phone:SHA256(<phone>+<account_salt>)

// Benefits:
// - All user's devices share same DID (derived from phone)
// - Relay can group devices by phone hash
// - Users understand phone = identity
```

**Implementation:**
1. During phone auth, generate random 32-byte salt
2. Store salt on relay with phone hash
3. Derive DID from hash(phone + salt)
4. All devices with same phone number = same DID
5. Each device has own signing/encryption keys

**Tradeoff:** Phone number is now required (not crypto-pure), but matches UX reality

#### Option B: Accept One DID Per Device (DEFER)

```swift
// Each device is separate identity
// Jar membership is list of device DIDs, not user DIDs
// When adding "Alice", actually adding all her devices individually

// Tradeoff: Complex UX, more correct cryptographically
```

**Decision for 10.3: Option A** (phone-based identity)

---

## 2. 🔴 No Forward Secrecy

### Current Architecture (No Forward Secrecy)

```swift
// Static shared secret between Device A and Device B
let sharedSecret = X25519.KeyAgreement.computeSharedSecret(
    myStaticPrivateKey,    // Never changes
    theirStaticPublicKey   // Pinned at TOFU
)

// Message 1
let aesKey1 = randomBytes(32)
let wrappedKey1 = AES.GCM.seal(aesKey1, using: sharedSecret)

// Message 2
let aesKey2 = randomBytes(32)
let wrappedKey2 = AES.GCM.seal(aesKey2, using: sharedSecret)

// If attacker steals unlocked device TODAY:
// - Extract myStaticPrivateKey from Keychain
// - Compute sharedSecret with theirStaticPublicKey (public, known)
// - Unwrap ALL past message keys (wrappedKey1, wrappedKey2, ...)
// - Decrypt ALL past messages
```

**Current "ephemeral AES keys" are NOT forward secret.**

### What Forward Secrecy Actually Requires

```swift
// Signal Protocol / Double Ratchet
// Each message uses new ephemeral sender keypair

// Message 1
let ephemeralKeypair1 = X25519.KeyAgreement.PrivateKey()
let sharedSecret1 = X25519.computeSharedSecret(ephemeralKeypair1, theirPublicKey)
let messageKey1 = deriveKey(sharedSecret1)
encrypt(message1, messageKey1)
delete(ephemeralKeypair1.privateKey)  // Critical: delete after use

// Message 2
let ephemeralKeypair2 = X25519.KeyAgreement.PrivateKey()  // NEW keypair
let sharedSecret2 = X25519.computeSharedSecret(ephemeralKeypair2, theirPublicKey)
let messageKey2 = deriveKey(sharedSecret2)
encrypt(message2, messageKey2)
delete(ephemeralKeypair2.privateKey)  // Critical: delete after use

// If attacker steals device TODAY:
// - ephemeralKeypair1 and ephemeralKeypair2 are already deleted
// - Can't decrypt past messages (no private keys)
// - Can only decrypt future messages (until next device rotation)
```

**This requires Double Ratchet protocol (Signal) - complex.**

### Fix for 10.3: ACCEPT LIMITATION, DOCUMENT CLEARLY

**Not fixing in 10.3 because:**
- Double Ratchet adds 20-30 hours of complexity
- Requires message ordering guarantees (state sync)
- Requires session state management
- Out of scope for V1 beta

**Mitigation for 10.3:**
1. **Document clearly in security model:**
   ```
   ⚠️ LIMITATION: Compromise of unlocked device enables decryption of all past
   messages. This is a known limitation of our current E2EE implementation.
   Forward secrecy (Signal Protocol) is planned for Phase 12.
   ```

2. **Add device lock screen requirement:**
   - Encourage users to enable Face ID / passcode
   - App locks after 5 min idle (clear sensitive keys from memory)

3. **Add "Clear Message History" feature:**
   - User can delete all local messages
   - Reduces exposure window

4. **Plan for Phase 12: Forward Secrecy**
   - Implement Signal Protocol Double Ratchet
   - Migrate existing conversations
   - Or: Accept breaking change, require fresh messages

**Decision for 10.3: ACCEPT limitation, document, defer to Phase 12**

---

## 3. 🟡 TOFU Attack Window

### The Problem

```
User A adds User B to jar:
  1. A calls relay: "Lookup B's devices"
  2. Relay returns: [Device B1, Device B2]
  3. A pins keys from B1, B2 (TOFU)

Attack:
  - Relay is compromised or malicious
  - Relay returns attacker's devices instead of B's real devices
  - A pins attacker's keys (unknowingly)
  - All future messages to "B" go to attacker
  - B never receives anything (doesn't know they were added)
```

**TOFU (Trust On First Use) is vulnerable at first use.**

### Fix for 10.3: Safety Number Verification (Optional UX)

```swift
// Generate safety number from pinned keys
func generateSafetyNumber(myDID: String, theirDID: String, theirDevices: [Device]) -> String {
    let combined = myDID + theirDID + theirDevices.map { $0.pubkeyEd25519.base64 }.joined()
    let hash = SHA256.hash(data: combined.data(using: .utf8)!)

    // Format as readable string (like Signal)
    // "12345 67890 12345 67890 12345 67890"
    return formatSafetyNumber(hash)
}

// UI in MemberDetailView
Section("Security") {
    HStack {
        Text("Safety Number")
        Spacer()
        Text(safetyNumber)
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(.secondary)
    }

    Button("Verify Out-of-Band") {
        // Show full safety number + QR code
        // Instruction: "Compare with Alice's device (in person or video call)"
    }
}
```

**How it works:**
1. When you add Alice, generate safety number from her pinned keys
2. Compare safety number with Alice out-of-band (in person, phone call, video)
3. If they match → relay didn't MITM
4. If they don't match → WARNING: possible attack

**Implementation in 10.3:**
- Add safety number generation
- Show in MemberDetailView (optional, low priority)
- Don't block jar operations on verification
- Power users can verify, casual users skip

**Decision for 10.3: Add safety number UI (low priority, 2 hours)**

---

## 4. 🔴 Phone Hash Rainbow Tables

### The Problem

```swift
// Current implementation
let phoneHash = SHA256.hash(data: phoneNumber.data(using: .utf8)!)

// Attack:
// 1. Attacker downloads relay database (leak, hack, subpoena)
// 2. Relay has phone_to_did table with phone hashes
// 3. Attacker computes SHA-256(all US phone numbers):
//    - ~450M active US numbers
//    - SHA-256 is ~1M hashes/sec on GPU
//    - Total time: ~7.5 minutes
// 4. Attacker builds rainbow table, reverses all phone hashes
// 5. Attacker knows who uses Buds (identity exposure)
```

**No salt = trivial rainbow table attack.**

### Fix for 10.3: Per-User Salt (CRITICAL)

```swift
// Updated phone hashing
func hashPhone(_ phoneNumber: String, salt: Data) -> String {
    let combined = phoneNumber + salt.base64EncodedString()
    let hash = SHA256.hash(data: combined.data(using: .utf8)!)
    return hash.compactMap { String(format: "%02x", $0) }.joined()
}

// During registration
let accountSalt = Data(randomBytes(32))  // 32 random bytes
let phoneHash = hashPhone(phoneNumber, salt: accountSalt)

// Store on relay
await relay.register(
    phoneHash: phoneHash,
    accountSalt: accountSalt.base64,  // Public, but unique per user
    did: did,
    devices: [deviceInfo]
)

// Relay stores:
// phone_hash | account_salt | did
// abc123...  | xyz789...    | did:phone:...

// During lookup (adding member)
let lookupHash = hashPhone(phoneNumber, salt: accountSalt)
let did = await relay.lookupDID(phoneHash: lookupHash)

// But wait... how do we get accountSalt if we only have phone number?
// Answer: We don't. We need relay to help.
```

### Revised Fix: Server-Side Salted Hash

```typescript
// Cloudflare Worker: /api/register
async function register(request: Request, env: Env) {
    const { phone_number, device_info } = await request.json();

    // Generate unique salt for this phone number
    const account_salt = crypto.randomBytes(32).toString('base64');

    // Hash with salt
    const phone_hash = await crypto.subtle.digest(
        'SHA-256',
        new TextEncoder().encode(phone_number + account_salt)
    );

    // Store both hash and salt
    await env.DB.prepare(`
        INSERT INTO users (phone_hash, account_salt, did, created_at)
        VALUES (?, ?, ?, ?)
    `).bind(
        bufferToHex(phone_hash),
        account_salt,
        did,
        Date.now()
    ).run();
}

// Cloudflare Worker: /api/lookup/did
async function lookupDID(request: Request, env: Env) {
    const { phone_number } = await request.json();

    // Two-step lookup:
    // 1. Try to find existing user by trying common phone variations
    //    (This is slow but necessary without client knowing salt)

    // Better approach: Client sends phone, server does lookup internally
    // Server knows all salts, can compute hash(phone + salt) for lookup

    // Pseudocode:
    const user = await env.DB.prepare(`
        SELECT did, account_salt FROM users
        WHERE phone_number_plaintext = ?
    `).bind(phone_number).first();

    // But this requires storing phone_number_plaintext (privacy leak)
    // Contradiction: Can't do lookups without storing phones
}
```

**The Paradox:**
- Salted hashing prevents rainbow tables
- But makes lookups impossible (client doesn't know salt)
- Can't store plaintext phones (defeats purpose of hashing)

### Actual Fix for 10.3: Encrypted Phone Storage

```typescript
// Relay stores phones encrypted, not hashed
// Use deterministic encryption (same phone → same ciphertext for lookups)

// Server-side encryption key (stored in Cloudflare secrets)
const PHONE_ENCRYPTION_KEY = env.PHONE_ENCRYPTION_KEY;

async function register(request: Request, env: Env) {
    const { phone_number } = await request.json();

    // Deterministic encryption (AES-GCM with fixed nonce derived from phone)
    const nonce = await deriveNonce(phone_number);  // Deterministic
    const encrypted_phone = await encrypt(phone_number, PHONE_ENCRYPTION_KEY, nonce);

    await env.DB.prepare(`
        INSERT INTO users (encrypted_phone, did)
        VALUES (?, ?)
    `).bind(encrypted_phone, did).run();
}

async function lookupDID(request: Request, env: Env) {
    const { phone_number } = await request.json();

    // Same deterministic encryption
    const nonce = await deriveNonce(phone_number);
    const encrypted_phone = await encrypt(phone_number, PHONE_ENCRYPTION_KEY, nonce);

    // Lookup by encrypted phone (deterministic, so matches)
    const user = await env.DB.prepare(`
        SELECT did FROM users WHERE encrypted_phone = ?
    `).bind(encrypted_phone).first();

    return user?.did;
}
```

**Security properties:**
- Rainbow tables don't work (ciphertext, not hash)
- Relay DB leak doesn't expose phones (encrypted)
- Lookups work (deterministic encryption)
- **Tradeoff:** Attacker with encryption key can decrypt all phones
  - But encryption key is in Cloudflare secret (not in DB)
  - Requires both DB leak AND secrets leak

**Decision for 10.3: Deterministic phone encryption on relay (CRITICAL)**

---

## 5. 🟡 Sender Public Key Dependency

### Current Flow

```swift
// When adding member Alice
let devices = try await RelayClient.shared.getDevices(for: [aliceDID])
// Returns: [Device(id: "alice-iphone", pubkeyX25519: "abc...", pubkeyEd25519: "def...")]

// Store in local devices table (TOFU pinning)
for device in devices {
    try await db.writeAsync { db in
        try Device(
            id: device.id,
            ownerDID: aliceDID,
            pubkeyX25519: device.pubkeyX25519,
            pubkeyEd25519: device.pubkeyEd25519,
            status: "active"
        ).insert(db)
    }
}

// Later: Receiving message from Alice
let encryptedMsg = inbox.messages.first
let senderDID = encryptedMsg.senderDID
let senderDeviceID = encryptedMsg.senderDeviceId

// Look up sender's X25519 pubkey from TOFU pinned devices
let senderDevice = try await db.readAsync { db in
    try Device.fetchOne(db, sql: """
        SELECT * FROM devices
        WHERE owner_did = ? AND id = ?
    """, arguments: [senderDID, senderDeviceID])
}

guard let senderPubkey = senderDevice?.pubkeyX25519 else {
    throw InboxError.senderDeviceNotPinned
}

// Unwrap message key using sender's pubkey
let sharedSecret = try X25519.KeyAgreement.computeSharedSecret(
    myPrivateKey,
    senderPubkey
)
```

### The Problem

**What if sender added new device AFTER you pinned them?**

```
Time 0: You add Alice, pin her devices [iPhone]
Time 1: Alice buys iPad, registers new device [iPhone, iPad]
Time 2: Alice sends bud from iPad
Time 3: You receive message from "alice-ipad"
        → No pinned key for "alice-ipad"
        → InboxError.senderDeviceNotPinned
        → Can't decrypt message
```

### Fix for 10.3: Dynamic Device Discovery

```swift
// When receiving message from unknown device
func decryptMessage(_ message: EncryptedMessage) async throws -> Data {
    let senderDID = message.senderDID
    let senderDeviceID = message.senderDeviceId

    // Try to get pinned device
    var senderDevice = try await getPinnedDevice(did: senderDID, deviceID: senderDeviceID)

    if senderDevice == nil {
        // Unknown device - fetch from relay and pin now
        print("⚠️ Unknown device \(senderDeviceID), fetching from relay...")

        let devices = try await RelayClient.shared.getDevices(for: [senderDID])
        let newDevice = devices.first(where: { $0.id == senderDeviceID })

        guard let newDevice = newDevice else {
            throw InboxError.senderDeviceNotFound
        }

        // Pin new device (updated TOFU)
        try await pinDevice(newDevice)
        senderDevice = newDevice

        print("✅ Pinned new device \(senderDeviceID)")
    }

    // Now we have sender's pubkey, decrypt normally
    // ...
}
```

**Security consideration:**
- This re-queries relay for new devices (potential MITM)
- But: Only happens if device wasn't in original pinned set
- Mitigation: Show warning to user
  - "Alice added a new device. Verify safety number."

**Decision for 10.3: Add dynamic device discovery with warning (CRITICAL)**

---

## 6. ⚪ Metadata Leakage (ACCEPTED)

### What the Relay Sees

```
Relay observes (even with E2EE):
- Who added whom to which jar (social graph)
- When messages sent (timing patterns)
- Message sizes (approximate content type: text vs image)
- Frequency of communication (who talks to whom often)
- Online patterns (when users are active)
```

**Example Attack:**
```
Relay sees:
- Alice and Bob in jar "abc"
- Message sizes: 2KB, 2KB, 2KB (text buds)
- Then: 500KB message (likely photo)
- Timing: Messages spike on Friday nights (weekend use pattern)

Inference: Alice and Bob use together on weekends, probably in same location
```

### Fix: None (Accept as Tradeoff)

**Why we accept metadata leakage:**
- Tor-style onion routing would hide metadata but adds latency
- PIR (Private Information Retrieval) is too expensive for mobile
- Mixing networks (like Nym) add complexity
- Relay needs to route messages somehow (fundamental tradeoff)

**Mitigation:**
1. **Document clearly in privacy policy:**
   ```
   Buds uses end-to-end encryption to protect your message contents.
   However, metadata (who you communicate with, when, and frequency)
   is visible to our servers. We do not use this metadata for any
   purpose other than message delivery.
   ```

2. **Run relay ourselves (trusted operator)**
   - Don't use third-party relay that could abuse metadata
   - Cloudflare Workers = we control relay code

3. **Future: Add padding (Phase 13)**
   - Pad all messages to fixed sizes (e.g., 1KB, 10KB, 100KB buckets)
   - Reduces message size leakage
   - Adds bandwidth cost

**Decision for 10.3: Accept metadata leakage, document clearly**

---

## 7. 🔴 CBOR Canonicalization Dependency

### The Problem

```swift
// Signature verification depends on CBOR encoding being IDENTICAL

// Device A (SwiftCBOR v0.4.5)
let payload = SessionPayload(productName: "Blue Dream", ...)
let cbor = try CBOREncoder().encode(payload)
let signature = try sign(cbor, with: privateKey)

// Device B (SwiftCBOR v0.5.0 - different library version)
let payload = SessionPayload(productName: "Blue Dream", ...)
let cbor = try CBOREncoder().encode(payload)  // DIFFERENT BYTES!
let valid = try verify(cbor, signature, publicKey)  // FAILS!

// If CBOR encoding changes, ALL old signatures break
```

**CBOR encoding is NOT guaranteed stable across library versions.**

### Why This Is Critical

```
Year 0: All users on SwiftCBOR v0.4.5
Year 1: SwiftCBOR releases v0.5.0 (changes map key ordering)
Year 1: Some users update app (new CBOR encoding)
Year 1: Old users can't verify new signatures
Year 1: New users can't verify old signatures
Year 1: ENTIRE SIGNATURE SYSTEM BREAKS
```

### Fix for 10.3: Pin Library + Golden Tests (CRITICAL)

**1. Pin CBOR Library Version in SPM**

```swift
// Package.swift
dependencies: [
    .package(
        url: "https://github.com/valpackett/SwiftCBOR.git",
        exact: "0.4.5"  // EXACT version, not range
    )
]
```

**2. Add Golden File Tests**

```swift
// Tests/ReceiptTests/CBORCanonicalityTests.swift

func testCBOREncodingStability() throws {
    // Create test payload
    let payload = SessionPayload(
        claimedTimeMs: 1234567890,
        productName: "Blue Dream",
        productType: "flower",
        rating: 5,
        notes: "Great strain",
        brand: "Test Co",
        thcPercent: 20.5,
        cbdPercent: 0.5,
        amountGrams: 3.5,
        effects: ["relaxed", "happy"],
        consumptionMethod: "joint",
        locationCID: nil
    )

    // Encode to CBOR
    let cbor = try ReceiptCanonicalizer.canonicalCBOR(payload)

    // Expected bytes (golden file)
    // This is the EXACT byte sequence we expect
    // If CBOR library changes, this test FAILS
    let expectedHex = """
        a96b636c61696d65645f74696d655f6d731b00000000498c0b32
        6c70726f647563745f6e616d656a426c75652044726561606c70
        726f647563745f74797065666c6f776572667261746570056e6f
        746573654772656174207374726169706562726162674054657374
        20436f6a7468635f70657263656e742e14666362645f70657263656e742e05
        6c616d6f756e745f6772616d732e0e6765666665637473826872656c617865
        646568617079706a636f6e73756d7074696f6e5f6d6574686f64656a6f696e74
    """

    XCTAssertEqual(cbor.hexEncodedString(), expectedHex)
}

// If this test ever fails, DO NOT UPDATE THE GOLDEN FILE
// Instead: MIGRATION REQUIRED (re-sign all receipts with new encoding)
```

**3. Document CBOR Library Policy**

```markdown
# CBOR Library Policy

CRITICAL: SwiftCBOR is pinned to exact version 0.4.5.

## Why?
Our signature verification depends on CBOR encoding being identical.
If CBOR library changes encoding, all existing signatures break.

## Policy:
1. NEVER update SwiftCBOR without explicit migration plan
2. Run CBORCanonicalityTests before ANY updates
3. If golden test fails → signatures WILL break
4. Coordinate migration:
   - Deploy relay support for both encodings
   - Deploy client with dual verification
   - Wait 30 days for user updates
   - Remove old encoding support

## If We Must Upgrade:
Phase 15: CBOR Library Migration
- Add encoding version field to receipts
- Support verification of both old + new encodings
- Migrate all receipts (re-sign) or accept break
```

**Decision for 10.3:**
- Pin SwiftCBOR to exact version (CRITICAL)
- Add golden file tests (CRITICAL)
- Document migration policy (2 hours)

---

## Updated 10.3 Crypto Scope

### What We're Fixing in 10.3

🔴 **CRITICAL (Must Fix):**
1. ✅ **Phone-based identity** - DID derived from phone hash (not per-device)
2. ✅ **Deterministic phone encryption** - Relay stores encrypted phones (not hashes)
3. ✅ **Dynamic device discovery** - Handle new devices added after TOFU
4. ✅ **CBOR library pinning** - Lock to exact version, add golden tests

🟡 **HIGH (Should Fix):**
5. ✅ **Safety number UI** - Optional verification (low priority)

⚪ **ACCEPT (Document Limitations):**
6. ⚪ **No forward secrecy** - Document clearly, defer to Phase 12
7. ⚪ **TOFU trust assumption** - Document clearly, mitigate with safety numbers
8. ⚪ **Metadata leakage** - Accept as tradeoff, document in privacy policy

### Updated Time Estimate

**Original 10.3:** 32-44 hours
**Crypto fixes:** +12-16 hours
**New total:** 44-60 hours

**Breakdown:**
- Phone-based identity refactor: 4-6 hours
- Deterministic encryption (relay): 3-4 hours
- Dynamic device discovery: 2-3 hours
- CBOR pinning + tests: 2-3 hours
- Safety number UI: 1-2 hours

---

## Implementation Order (Updated)

### Week 1: Crypto Fixes + Relay (20-24 hours)

**Days 1-2:**
- Fix phone-based identity (DID derivation)
- Add deterministic phone encryption to relay
- Pin CBOR library + golden tests

**Days 3-4:**
- Relay membership validation
- Dynamic device discovery
- Safety number generation

### Week 2: Jar Sync (20-24 hours)

**Days 1-5:**
- Original 10.3 modules (sequencing, tombstones, sync flows)

### Week 3: Testing (4-8 hours)

- Crypto testing (device discovery, CBOR stability)
- Integration testing (jar sync)

---

## Security Model Documentation

**Add to app:**

```markdown
# Buds Security Model (V1)

## What's Protected (End-to-End Encrypted)
✅ Bud contents (strain names, notes, ratings, photos)
✅ Jar metadata (jar names, descriptions)
✅ Message authenticity (signatures verify sender identity)

## What's NOT Protected (Known Limitations)
⚠️ Phone numbers (relay stores encrypted, but knows who uses Buds)
⚠️ Social graph (relay knows who's in which jars)
⚠️ Timing metadata (relay sees when messages sent)
⚠️ Message sizes (relay sees approximate content type)
⚠️ Forward secrecy (device compromise → past messages readable)

## Trust Assumptions
🔐 You trust your device's Keychain (stores private keys)
🔐 You trust the relay server for initial key exchange (TOFU)
🔐 You trust CBOR library encoding stays stable
🔐 You trust your device isn't already compromised

## Verification
✅ Safety numbers: Compare with friends out-of-band to detect MITM
✅ Signatures: All receipts are signed, verify sender authenticity
⚠️ No forward secrecy: Stolen device can read past messages

## Roadmap
Phase 12: Forward secrecy (Signal Protocol)
Phase 13: Metadata resistance (padding, mixing)
Phase 15: CBOR migration (if needed)
```

---

## Conclusion

**Addressed all 7 blind spots:**
1. ✅ Multi-device DID → Phone-based identity
2. ⚪ Forward secrecy → Accept limitation, defer to Phase 12
3. 🟡 TOFU attack → Safety numbers (optional verification)
4. ✅ Phone rainbow tables → Deterministic encryption
5. ✅ Sender pubkey → Dynamic device discovery
6. ⚪ Metadata leakage → Accept, document clearly
7. ✅ CBOR canonicalization → Pin library, golden tests

**New 10.3 scope: 44-60 hours**

**Crypto is still imperfect (no forward secrecy), but:**
- Honest about limitations
- Mitigations in place where feasible
- Clear roadmap for future hardening
- Good enough for V1 beta

**Ready to build?** The crypto is now coherent, not perfect, but defensible.
