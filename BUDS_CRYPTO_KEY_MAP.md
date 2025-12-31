# BUDS CRYPTOGRAPHIC & KEY MAP
## Understanding E2EE Architecture & Potential Blind Spots

---

## 🔑 KEY HIERARCHY & RELATIONSHIPS

```
┌─────────────────────────────────────────────────────────────┐
│                    iOS KEYCHAIN (Encrypted)                 │
│                                                             │
│  ┌──────────────────┐        ┌──────────────────┐          │
│  │ Ed25519 Private  │        │ X25519 Private   │          │
│  │   (Signing)      │        │ (Key Agreement)  │          │
│  │   32 bytes       │        │   32 bytes       │          │
│  └────────┬─────────┘        └────────┬─────────┘          │
│           │                           │                     │
│           ▼                           ▼                     │
│  ┌──────────────────┐        ┌──────────────────┐          │
│  │ Ed25519 Public   │        │ X25519 Public    │          │
│  │ (Verification)   │        │ (Encryption)     │          │
│  └────────┬─────────┘        └────────┬─────────┘          │
│           │                           │                     │
└───────────┼───────────────────────────┼─────────────────────┘
            │                           │
            │                           │
            ▼                           ▼
    ┌──────────────┐          ┌────────────────┐
    │     DID      │          │ Device Public  │
    │ did:buds:... │──────────│ Keys on Relay  │
    └──────────────┘          └────────────────┘
```

### Key Relationships You Should Understand

**RELATIONSHIP 1: DID ≠ Identity**
```
Ed25519 Private Key (32 bytes)
    ↓ [Deterministic derivation]
Ed25519 Public Key (32 bytes)
    ↓ [Take first 20 bytes → Base58]
DID = "did:buds:ABC123..."
```

**⚠️ BLIND SPOT**: Your DID is pseudonymous, not anonymous. If someone learns your DID and can correlate it with other metadata (phone hash, timing patterns), they can potentially de-anonymize you.

**RELATIONSHIP 2: One DID → Many Devices**
```
DID: "did:buds:ABC123"
  ├─ Device 1: (Ed25519_pub1, X25519_pub1, device_id_1)
  ├─ Device 2: (Ed25519_pub2, X25519_pub2, device_id_2)
  └─ Device 3: (Ed25519_pub3, X25519_pub3, device_id_3)
```

**⚠️ BLIND SPOT**: Each device has DIFFERENT keypairs but the SAME DID (derived from device 1's Ed25519 key?). Wait... how are multiple devices getting the same DID if DID is derived from pubkey?

**🚨 CRITICAL ARCHITECTURAL QUESTION**:
- Is DID derived from the FIRST device's Ed25519 key?
- Or is there a primary key that syncs across devices?
- How do new devices register with the same DID?

---

## 🔐 ENCRYPTION FLOW DIAGRAM

### Message Encryption (Step-by-Step)

```
┌──────────────────────────────────────────────────────────────┐
│ STEP 1: Content Encryption (Per-Message)                    │
└──────────────────────────────────────────────────────────────┘

    Original Receipt (CBOR)
            │
            ▼
    [Generate Random AES-256 Key]  ◄──── EPHEMERAL (destroyed after wrapping)
            │
            ▼
    [AES-256-GCM Encrypt]
      • Nonce: 12 bytes (random)
      • AAD: receipt_cid (for integrity)
            │
            ▼
    Encrypted Payload
    (nonce || ciphertext || tag)
            │
            ▼
    Base64 → Store in R2

┌──────────────────────────────────────────────────────────────┐
│ STEP 2: Key Wrapping (Per Recipient Device)                 │
└──────────────────────────────────────────────────────────────┘

    FOR EACH recipient device:

    Recipient's X25519 Public Key (from relay DB)
            │
            ▼
    [X25519 Key Agreement]
      • Sender Private × Recipient Public
      • Produces: Shared Secret (32 bytes)
            │
            ▼
    [HKDF-SHA256 Derivation]
      • Salt: empty
      • Info: "buds.wrap.v1"
      • Output: 32 bytes
            │
            ▼
    Wrapping Key (AES-256)
            │
            ▼
    [AES-GCM Wrap]
      • Encrypt the ephemeral AES key
      • Result: nonce || wrapped_key || tag
            │
            ▼
    Base64 → Store in wrapped_keys[device_id]

┌──────────────────────────────────────────────────────────────┐
│ STEP 3: Signature (Authenticity)                            │
└──────────────────────────────────────────────────────────────┘

    Original CBOR bytes
            │
            ▼
    [Ed25519 Sign]
      • Using sender's signing key
            │
            ▼
    Signature (64 bytes)
            │
            ▼
    Base64 → Store in message metadata
```

---

## 🚨 BLIND SPOTS YOU NEED TO UNDERSTAND

### BLIND SPOT #1: The DID Multi-Device Problem

**Current Understanding (Likely Incorrect)**:
```
User has one DID → derived from Ed25519 public key
User has multiple devices → each with different keypairs
DID is derived from public key → deterministic

PROBLEM: If each device has different Ed25519 keypairs,
they would generate DIFFERENT DIDs!
```

**Reality Check**:
Looking at the code, I see:
1. `IdentityManager.getDID()` derives DID from Ed25519 pubkey
2. Each device generates its own Ed25519 keypair
3. But the relay stores `owner_did` for each device

**🔍 What's Actually Happening**:
- Option A: First device creates DID, other devices manually specify same DID?
- Option B: Primary key syncs across devices via iCloud Keychain?
- Option C: Something else entirely?

**⚠️ RISK**: If you don't understand this correctly, you might have:
- DID collision issues
- Device registration failures
- Identity fragmentation across devices

**ACTION REQUIRED**: Clarify the multi-device DID architecture. This is a foundational piece you may be misunderstanding.

---

### BLIND SPOT #2: The Key Wrapping Symmetry Illusion

**What You Think Happens**:
```
Sender wraps AES key with Recipient's X25519 public key
Recipient unwraps with their X25519 private key
```

**What Actually Happens (X25519 ECDH)**:
```
Sender:
  sharedSecret = SenderPrivate × RecipientPublic
  wrapKey = HKDF(sharedSecret, "buds.wrap.v1")
  wrappedKey = AES-GCM(contentKey, wrapKey)

Recipient:
  sharedSecret = RecipientPrivate × SenderPublic  ◄── NEEDS sender's public!
  wrapKey = HKDF(sharedSecret, "buds.wrap.v1")
  contentKey = AES-GCM.unwrap(wrappedKey, wrapKey)
```

**🚨 CRITICAL REALIZATION**:
The recipient needs the **sender's X25519 public key** to derive the shared secret!

**Where is the sender's X25519 public key stored?**
1. In the message metadata? (Not seen in schema)
2. Looked up from relay's `devices` table using `sender_device_id`?
3. Hardcoded somewhere?

**⚠️ RISK**: If sender's X25519 pubkey isn't properly included:
- Unwrapping will fail silently
- Messages become permanently undecryptable
- No way to derive shared secret

**Looking at the code analysis, I see**:
- `E2EEManager.unwrapKey()` queries local devices table
- Sender's device must be in Circle (device discovery happened)
- If sender revokes device → old messages undecryptable?

**ACTION REQUIRED**: Document the dependency on sender device public keys being available at unwrap time.

---

### BLIND SPOT #3: The TOFU Attack Window

**What TOFU Means**:
```
First message from Alice's device → pins her Ed25519 public key
Subsequent messages → verify against pinned key
```

**The Attack Window**:
```
TIME 0: Alice registers device on relay
  ↓
  Relay stores: (device_id, Ed25519_pub, X25519_pub)
  ↓
TIME 1: Alice sends first message to Bob
  ↓
  Bob receives message, verifies signature, PINS Ed25519_pub
  ↓
TIME 2: Attacker compromises relay
  ↓
  Attacker CANNOT change Alice's pinned key (already pinned)
  ✅ Bob is protected from relay MITM

BUT...

TIME 0: Alice registers device on relay
  ↓
  ⚠️ Attacker (evil relay) swaps Ed25519_pub with attacker_pub
  ↓
TIME 1: Alice sends first message to Bob
  ↓
  Bob receives message with attacker's signature
  ↓
  Bob PINS attacker_pub thinking it's Alice!
  ↓
  🚨 Attacker can now impersonate Alice forever
```

**⚠️ BLIND SPOT**: You're trusting the relay during initial device registration!

**Mitigation Strategies**:
1. **Out-of-band verification**: QR code fingerprint exchange
2. **Transparency logs**: Publicly auditable device registry
3. **Gossip protocols**: Cross-verify with other Circle members
4. **Key history**: Show when device was registered

**What You're Currently Doing**: Nothing (pure TOFU)

**ACTION REQUIRED**: Add device verification UI for high-security users.

---

### BLIND SPOT #4: The Forward Secrecy Misunderstanding

**What You Think Forward Secrecy Means**:
```
Each message encrypted with different AES key ✅
Old messages can't be decrypted if key is lost ❌
```

**What Forward Secrecy Actually Means**:
```
Compromise of long-term private keys CANNOT decrypt past messages
```

**Your Current Architecture**:
```
Message 1 encrypted with: HKDF(SenderX25519 × RecipientX25519)
Message 2 encrypted with: HKDF(SenderX25519 × RecipientX25519)
                                 ↑ SAME KEYS USED!

If attacker steals X25519 private key:
  → Compute shared secret
  → Derive all wrapping keys
  → Unwrap all AES keys
  → Decrypt ALL messages (past and future)

🚨 NO FORWARD SECRECY!
```

**Why Your "Ephemeral AES Key" Doesn't Help**:
```
Ephemeral AES key is wrapped with static X25519 shared secret
  ↓
Attacker can unwrap it using compromised X25519 key
  ↓
Ephemeral key is recovered
  ↓
Message decrypted
```

**True Forward Secrecy Requires**:
```
Message 1: Generate ephemeral X25519 keypair → use once → DELETE
Message 2: Generate NEW ephemeral X25519 keypair → use once → DELETE

Now: Compromise of long-term key doesn't help decrypt past messages
     (ephemeral keys are already deleted)
```

**What Signal/WhatsApp Do (Double Ratchet)**:
```
1. DH ratchet: New ephemeral keypair per message
2. KDF ratchet: Derive one-time keys, delete after use
3. Session ratchet: Ratchet forward on every exchange

Result: Perfect Forward Secrecy + Post-Compromise Security
```

**⚠️ BLIND SPOT**: You don't have forward secrecy in v0.1. Document this clearly.

**ACTION REQUIRED**:
1. Add UI warning: "If your device is unlocked and stolen, past messages may be compromised"
2. Plan for v0.2 with ephemeral keypairs
3. Consider storing wrapped keys separately (delete after unwrap)

---

### BLIND SPOT #5: The Phone Hash Rainbow Table

**What You Think SHA-256 Gives You**:
```
Phone Number: +1-555-0100
              ↓ [SHA-256]
Phone Hash:   abc123...def  (64 hex chars)
              ↓
Privacy: ✅ Relay can't reverse hash to get phone number
```

**What Actually Happens**:
```
Attacker builds rainbow table:
  SHA-256("+1-201-555-0001") = hash1
  SHA-256("+1-201-555-0002") = hash2
  ...
  SHA-256("+1-999-999-9999") = hashN

Total US phone numbers: ~1 billion (10^9)
SHA-256 computation time: ~1 microsecond
Total rainbow table time: ~15 minutes on laptop
Storage: ~64 GB (1 billion × 64 bytes)

Now attacker can reverse ANY phone hash instantly!
```

**Why Rate Limiting Doesn't Help**:
```
Rate limit: 20 requests/min for DID lookup
Workaround: Attacker runs lookup offline after DB breach
           OR uses 1000 Cloudflare IPs → 20,000 req/min
           OR slowly builds database over months
```

**Real-World Attack Scenario**:
```
1. Attacker breaches relay database
2. Dumps phone_to_did table (phone_hash → DID)
3. Runs rainbow table offline
4. Recovers all phone numbers
5. Cross-references with social media
6. De-anonymizes all users
```

**⚠️ BLIND SPOT**: SHA-256 without salt is NOT privacy-preserving!

**What You Should Use Instead**:
```
Argon2id (password hash, resistant to GPUs)
  • Designed to be SLOW (prevents rainbow tables)
  • Memory-hard (prevents ASIC attacks)
  • Salted (each hash unique even for same input)

OR

HMAC-SHA256 with server-side secret
  • Relay stores HMAC(phone, secret_key)
  • Attacker needs secret_key to build rainbow table
  • Secret rotation possible
```

**Trade-off**:
```
Current (SHA-256):
  + Fast lookup
  + Stateless (no secret to manage)
  - Rainbow table vulnerable

Argon2id:
  + Resistant to rainbow tables
  - Slower lookup (100ms vs 1ms)
  - Still deterministic (same phone → same hash)

HMAC with rotation:
  + Rainbow table requires secret theft
  + Secret rotation invalidates old rainbow tables
  - Requires secret management
  - Relay compromise still exposes current secret
```

**ACTION REQUIRED**:
1. Document privacy model clearly ("privacy against relay, not against attackers with DB dump")
2. Consider HMAC with server-secret for v0.2
3. Add optional "privacy mode" with Argon2 for high-security users

---

### BLIND SPOT #6: The Metadata Leakage Graph

**What You Think The Relay Sees**:
```
Encrypted ciphertext ✅ (can't read)
Sender DID ❌ (pseudonymous but not private)
Recipient DIDs ❌ (knows social graph)
Timestamps ❌ (knows when you message)
Message sizes ❌ (can infer content type)
```

**What An Adversary Can Infer**:
```
┌─────────────────────────────────────────────────┐
│  Relay Database After 1 Month of Messages      │
├─────────────────────────────────────────────────┤
│                                                 │
│  did:buds:Alice → did:buds:Bob (500 messages)  │
│  did:buds:Alice → did:buds:Carol (50 messages) │
│  did:buds:Bob → did:buds:Alice (450 messages)  │
│                                                 │
│  INFERENCE: Alice and Bob are close            │
│             (high message volume, symmetric)   │
│                                                 │
│  did:buds:Alice → Circle[Bob, Carol, Dave]     │
│  Timestamp: Every Friday 8pm                   │
│                                                 │
│  INFERENCE: Weekly group hangout/meeting       │
│                                                 │
│  Message size: 2KB (typical receipt)           │
│  Message size: 50KB (unusual)                  │
│                                                 │
│  INFERENCE: Likely contains media/image        │
└─────────────────────────────────────────────────┘
```

**Traffic Analysis Attacks**:
```
1. Social Graph Mapping
   → Who messages whom, how often
   → Identify central nodes (influencers)
   → Detect new relationships (first message)

2. Timing Correlation
   → Message sent at 2am → likely important/urgent
   → Regular schedule → routine communication
   → Burst of messages → event/crisis

3. Size Correlation
   → Large messages → media sharing
   → Tiny messages → quick reactions
   → Identical sizes → automated/template

4. Intersection Attacks
   → Cross-reference with other metadata sources
   → "User who messaged at 2:15am from NYC IP"
   → Narrow down identity
```

**⚠️ BLIND SPOT**: E2EE protects content, NOT metadata!

**Mitigation Strategies**:
1. **Padding**: Pad all messages to fixed size (e.g., 4KB blocks)
2. **Cover traffic**: Send dummy messages randomly
3. **Delayed delivery**: Random delays before relay forwarding
4. **Anonymizing network**: Route through Tor/mixnet
5. **Group messages**: Send to random group, not individuals

**What Signal Does**:
- Sealed sender: Hides sender from relay
- Fixed message sizes: Prevents size analysis
- Regular dummy traffic: Prevents timing analysis

**What You're Doing**: Nothing (metadata fully visible)

**ACTION REQUIRED**:
1. Document: "Relay knows who messages whom and when"
2. Consider sealed sender (relay doesn't see sender_did)
3. Add padding to fixed size buckets
4. For ultra-high-security: Offer Tor relay option

---

### BLIND SPOT #7: The Relay Compromise Scenarios

**Scenario 1: Read-Only Database Breach**
```
Attacker gets D1 database dump:
  ✅ Can't read message contents (encrypted in R2)
  ❌ Can see all DIDs, social graph, timestamps
  ❌ Can reverse phone hashes (rainbow table)
  ❌ Can see all device public keys
  ✅ Can't impersonate users (no private keys)

Risk Level: MEDIUM
Impact: Privacy violation, de-anonymization
Mitigation: Encrypt phone_to_did table with server key?
```

**Scenario 2: Full Relay Compromise (Code Execution)**
```
Attacker controls relay server:
  ✅ Can't read message contents (still E2EE)
  ❌ Can MitM new device registrations (TOFU attack)
  ❌ Can block/drop messages selectively
  ❌ Can inject fake messages (but can't sign them)
  ❌ Can correlate traffic patterns
  ⚠️ Can't decrypt OLD messages (no private keys)
  ⚠️ Can't decrypt NEW messages (no private keys)

Risk Level: MEDIUM-HIGH
Impact: Can disrupt service, MitM new users
Mitigation: Device verification, transparency logs
```

**Scenario 3: Relay + R2 Compromise**
```
Attacker controls relay + R2 bucket:
  ✅ Can't decrypt payloads (need device private keys)
  ❌ Can delete messages (denial of service)
  ❌ Can analyze message sizes/counts
  ✅ Can't modify ciphertext (signature verification fails)

Risk Level: MEDIUM
Impact: DoS, metadata analysis
Mitigation: Client-side caching, signature verification
```

**Scenario 4: Relay + Client Device Theft (Unlocked)**
```
Attacker controls relay + steals unlocked iPhone:
  ❌ Can read ALL messages (past and future)
  ❌ Can impersonate user
  ❌ Can decrypt new messages
  ❌ Has private keys in iOS Keychain

Risk Level: CRITICAL
Impact: Full compromise
Mitigation: Device auto-lock, remote wipe, forward secrecy (v0.2)
```

**⚠️ BLIND SPOT**: You're optimizing for relay compromise, but device theft is equally dangerous!

**ACTION REQUIRED**:
1. Enforce device auto-lock (max 5 minutes)
2. Require biometric auth for message viewing
3. Add remote wipe capability
4. Consider storing keys in Secure Enclave (hardware-backed)

---

### BLIND SPOT #8: The Canonical CBOR Dependency

**What You Think Happens**:
```
Create receipt → Encode to CBOR → Sign bytes → Store
Receive receipt → Decode CBOR → Verify signature → ✅
```

**What Actually Happens**:
```
Create receipt → Encode to CANONICAL CBOR → Sign → Store
                       ↑ Order matters!
Receive receipt → Decode → Re-encode to CANONICAL CBOR → Verify
                                    ↑ MUST match original!
```

**The Canonicalization Rules**:
```
1. Keys sorted by CBOR-encoded byte order
2. No duplicate keys
3. Deterministic encoding (no map with array)
4. Nil fields OMITTED (not encoded as null)
```

**Failure Scenario**:
```
Sender (iOS):
  Encodes with canonical order: { "a": 1, "b": 2 }
  Signs: Ed25519.sign(cbor_bytes)

Recipient (iOS):
  Receives: { "a": 1, "b": 2 }
  Re-encodes with DIFFERENT order: { "b": 2, "a": 1 }
  Verifies: Ed25519.verify(signature, cbor_bytes) → ❌ FAIL!
```

**Why This Is Critical**:
```
Signature is over RAW CBOR BYTES, not semantic content!

If encoding changes:
  - Different byte representation
  - Different signature
  - Verification fails
  - Message rejected
```

**⚠️ BLIND SPOT**: Your E2EE depends on CBOR staying canonical forever!

**Risks**:
1. **Library update**: New CBOR library changes encoding
2. **Platform difference**: iOS vs Android encode differently
3. **Version skew**: Old client vs new client mismatch
4. **Manual edits**: Developer modifies CBOR encoder

**Mitigation**:
- You're storing `raw_cbor` bytes (good!)
- Never re-encode for verification (good!)
- Test suite with golden vectors (good!)

**What You're Missing**:
- Version tag in CBOR format (e.g., `{"__version": "1.0", ...}`)
- Fallback verification (try multiple encodings?)
- Compatibility testing across platforms

**ACTION REQUIRED**:
1. Add version field to CBOR format
2. Document: "Never modify CBOR encoder without migration"
3. Test cross-platform (iOS ↔ Android when you add Android)

---

## 🎯 TRUST BOUNDARY MAP

```
┌─────────────────────────────────────────────────────────────────┐
│                     TRUST BOUNDARIES                            │
└─────────────────────────────────────────────────────────────────┘

[iOS Device - TRUSTED]
  │
  │ Private keys stored here
  │ E2EE encryption/decryption happens here
  │
  ▼
[iOS Keychain - HARDWARE BACKED]
  │
  │ Encrypted at rest
  │ Requires device unlock
  │
  ▼
[HTTPS Connection - ENCRYPTED TRANSPORT]
  │
  │ Protects against network eavesdropping
  │ Does NOT protect against relay
  │
  ▼
[Cloudflare Relay - UNTRUSTED]
  │
  │ Can see: DIDs, social graph, timestamps, sizes
  │ Cannot see: Message contents (encrypted)
  │ Can attack: TOFU (first message), metadata analysis
  │
  ├──────────────────┬──────────────────┐
  ▼                  ▼                  ▼
[D1 Database]    [R2 Storage]    [KV Cache]
  │                  │                  │
  │ Device pubkeys   │ Ciphertexts      │ Firebase keys
  │ Phone hashes     │ Base64 encoded   │ Temporary
  │ Social graph     │                  │
  ▼                  ▼                  ▼
[COMPROMISE = Privacy Loss] [COMPROMISE = DoS] [COMPROMISE = Auth bypass]

┌─────────────────────────────────────────────────────────────────┐
│                     ATTACK SURFACE                              │
└─────────────────────────────────────────────────────────────────┘

1. Device Theft (unlocked) → CRITICAL (full compromise)
2. Relay Compromise → MEDIUM (metadata, TOFU attack)
3. Network MitM → LOW (HTTPS protects)
4. Database Breach → MEDIUM (phone hash, social graph)
5. Malicious Circle Member → MEDIUM (can screenshot/leak)
6. Rainbow Table (phone) → MEDIUM (de-anonymization)
```

---

## 📊 KEY LIFECYCLE FLOWCHART

```
┌──────────────────────────────────────────────────────────┐
│              KEY LIFECYCLE (FULL FLOW)                   │
└──────────────────────────────────────────────────────────┘

DEVICE SETUP (Once per device)
├─ 1. Generate Ed25519 keypair → Store in Keychain
├─ 2. Generate X25519 keypair → Store in Keychain
├─ 3. Generate Device ID (UUID) → Store in Keychain
├─ 4. Derive DID from Ed25519 pubkey
└─ 5. Register device on relay (send pubkeys)

SENDING MESSAGE (Per message)
├─ 1. Load receipt CBOR from local DB
├─ 2. Generate ephemeral AES-256 key
├─ 3. Encrypt CBOR with AES-GCM
│     ├─ Nonce: random 12 bytes
│     └─ AAD: receipt_cid
├─ 4. For each recipient device:
│     ├─ Look up X25519 pubkey
│     ├─ Perform X25519 key agreement
│     ├─ Derive wrapping key (HKDF)
│     └─ Wrap AES key with AES-GCM
├─ 5. Sign original CBOR with Ed25519
└─ 6. Send to relay (ciphertext + wrapped keys + signature)

RELAY PROCESSING (Per message)
├─ 1. Verify Firebase auth token
├─ 2. Validate Zod schemas
├─ 3. Check sender device ownership
├─ 4. Upload ciphertext to R2
├─ 5. Store metadata in D1
└─ 6. Send silent push to recipients

RECEIVING MESSAGE (Per message)
├─ 1. Fetch from relay inbox
├─ 2. Download ciphertext from R2
├─ 3. Look up wrapped key for my device
├─ 4. Look up sender's X25519 pubkey
├─ 5. Perform X25519 key agreement
├─ 6. Derive wrapping key (HKDF)
├─ 7. Unwrap AES key
├─ 8. Decrypt ciphertext with AES-GCM
├─ 9. Verify signature with sender's Ed25519 pubkey
└─10. Store in local DB (pin sender's pubkey if first time)

DEVICE REVOCATION (Optional)
├─ 1. User marks device as revoked on relay
├─ 2. Relay updates device status to "revoked"
├─ 3. New messages no longer wrapped for revoked device
└─ 4. Old messages still readable (NO forward secrecy!)
```

---

## 🚨 CRITICAL QUESTIONS YOU NEED TO ANSWER

### Question 1: Multi-Device DID Derivation
**How do multiple devices share the same DID if DID is derived from Ed25519 pubkey?**

Possible answers:
- A) Primary device creates DID, secondary devices manually specify it
- B) iCloud Keychain Sync shares the Ed25519 private key
- C) DID is derived from phone number hash, not pubkey
- D) Each device has different DID (no multi-device support)

**If you can't answer this definitively, your architecture has a gap.**

---

### Question 2: Sender Public Key Distribution
**How does the recipient get the sender's X25519 public key for unwrapping?**

Possible answers:
- A) Included in message metadata (not seen in schema)
- B) Looked up from relay using sender_device_id (requires prior device discovery)
- C) Cached locally after first Circle member discovery
- D) Hardcoded or derived somehow

**If you can't answer this definitively, message decryption will fail.**

---

### Question 3: CBOR Canonicalization Guarantee
**What happens if the CBOR library changes encoding rules?**

Possible answers:
- A) Version field in CBOR allows migration
- B) Raw bytes are stored, never re-encoded (but what about new messages?)
- C) Golden test suite prevents accidental changes
- D) No mitigation (breaking change)

**If you can't answer this definitively, you risk breaking all signatures.**

---

### Question 4: Forward Secrecy Plan
**When will you add ephemeral keypairs for forward secrecy?**

Possible answers:
- A) v0.2 (planned, timeline TBD)
- B) Not planned (accepted limitation)
- C) Waiting for user demand
- D) Requires protocol breaking change (hesitant)

**If you can't answer this definitively, users are vulnerable to device theft.**

---

### Question 5: Phone Hash Privacy Model
**Do you accept that SHA-256(phone) is reversible via rainbow tables?**

Possible answers:
- A) Yes, acceptable trade-off for UX (fast lookup)
- B) No, will migrate to Argon2/HMAC in v0.2
- C) Unaware of this issue (needs urgent fix)
- D) Relay is trusted (not worried about breach)

**If you can't answer this definitively, your privacy model is unclear.**

---

## 🎓 RECOMMENDATIONS (Priority Order)

### URGENT (Fix Before Public Launch)

1. **Document Multi-Device DID Architecture**
   - Clarify how multiple devices share a DID
   - Test device registration flow thoroughly
   - Add error handling for DID conflicts

2. **Add Device Verification UI**
   - QR code fingerprint exchange
   - "Verify Device" button in Circle settings
   - Show when device was first seen (TOFU warning)

3. **Document Privacy Model Clearly**
   - "Relay can see who messages whom and when"
   - "Phone numbers can be reverse-engineered from hash"
   - "Device theft (unlocked) compromises all messages"

### HIGH PRIORITY (v0.2)

4. **Implement Forward Secrecy**
   - Ephemeral X25519 keypairs per message
   - Delete wrapped keys after unwrapping
   - Protocol version bump (breaking change)

5. **Improve Phone Hash Privacy**
   - Migrate to HMAC-SHA256 with server secret
   - Add secret rotation mechanism
   - Optional Argon2 mode for high-security users

6. **Add Message Padding**
   - Pad all messages to 4KB boundaries
   - Prevents size-based correlation
   - Minimal overhead (<10% typical)

### MEDIUM PRIORITY (Future)

7. **Sealed Sender (Hide Sender from Relay)**
   - Relay doesn't see sender_did
   - Only recipient can decrypt sender identity
   - Requires protocol redesign

8. **Transparency Logs for Device Registry**
   - Publicly auditable log of device registrations
   - Detect relay MITM attacks
   - Cross-verify with other users

9. **Post-Quantum Readiness**
   - Research hybrid schemes (Kyber + X25519)
   - Plan migration path
   - Not urgent for current threat model

---

## ✅ FINAL ASSESSMENT

**What You're Doing RIGHT**:
- ✅ End-to-end encryption (relay can't read messages)
- ✅ Hybrid encryption (X25519 + AES-256-GCM)
- ✅ Per-message ephemeral AES keys
- ✅ Canonical CBOR for deterministic signing
- ✅ Multi-device support (per-device key wrapping)
- ✅ TOFU pinning (prevents key swaps after first message)
- ✅ Storing raw CBOR bytes (prevents re-encoding issues)
- ✅ Strong input validation (Zod schemas)
- ✅ Modern crypto primitives (CryptoKit)

**What You're Doing WRONG (or not at all)**:
- ❌ No forward secrecy (device theft = full compromise)
- ❌ SHA-256 phone hash (rainbow table vulnerable)
- ❌ Metadata leakage (relay sees social graph)
- ❌ TOFU attack window (first message can be MitM'd)
- ❌ No device verification (trust on first use)
- ❌ No sealed sender (relay sees who messages whom)
- ❌ No message padding (size-based correlation)

**Overall Grade**: B+ (Solid E2EE implementation with known limitations)

**Recommendation**: Document limitations clearly, plan v0.2 with forward secrecy and improved privacy.

---

## 📚 FURTHER READING

- [Signal Protocol](https://signal.org/docs/)
- [Double Ratchet Algorithm](https://signal.org/docs/specifications/doubleratchet/)
- [TOFU and Key Verification](https://www.eff.org/deeplinks/2016/05/key-verification-is-not-optional)
- [Metadata Privacy in Messaging](https://signal.org/blog/sealed-sender/)
- [Rainbow Tables Explained](https://en.wikipedia.org/wiki/Rainbow_table)
- [Canonical CBOR RFC 8949](https://datatracker.ietf.org/doc/html/rfc8949#name-deterministically-encoded-c)
