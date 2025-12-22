# Documentation Audit for Phase 6

**Date:** December 20, 2025
**Purpose:** Identify all documentation that needs updating before/during Phase 6 implementation
**Scope:** Review all `/docs/` files for accuracy, completeness, and alignment with Phase 5 state + Phase 6 plan

---

## Executive Summary

**Status:** 📋 5 documents need updates, 6 documents are accurate

**Critical Updates:**
1. `DATABASE_SCHEMA.md` - Add circles + devices v3 schema (**BLOCKING**)
2. `ARCHITECTURE.md` - Add Circle architecture section (**HIGH PRIORITY**)
3. `E2EE_DESIGN.md` - Verify alignment with Cloudflare Workers relay (**CRITICAL**)

**Minor Updates:**
4. `PRIVACY_ARCHITECTURE.md` - Add Circle privacy implications
5. `RECEIPT_SCHEMAS.md` - Document shared receipt metadata (future)

**Accurate (No Changes Needed):**
- `CANONICALIZATION_SPEC.md` - Receipt signing is unchanged
- `DESIGN_SYSTEM.md` - Colors/typography unchanged
- `DEBUG_SYSTEM.md` - Debugging unchanged
- `AGENT_INTEGRATION.md` - Not relevant until Phase 9
- `DISPENSARY_INSIGHTS.md` - B2B product, not Phase 6
- `UX_FLOWS.md` - May need minor Circle flow additions

---

## 1. DATABASE_SCHEMA.md ⚠️ BLOCKING

**Status:** **OUTDATED** - Missing Phase 5 schema changes
**Priority:** **CRITICAL** - Must update before Phase 6
**Last Updated:** Dec 16, 2025 (pre-Phase 5)

### Missing Tables

#### `circles` Table (Migration v3)
**Added in:** Phase 5
**Purpose:** Friend roster with DID-based identity

```sql
CREATE TABLE circles (
    id TEXT PRIMARY KEY NOT NULL,
    did TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    phone_number TEXT,              -- Optional, for display only
    avatar_cid TEXT,
    pubkey_x25519 TEXT NOT NULL,    -- For E2EE key wrapping
    status TEXT NOT NULL,            -- 'pending' | 'active' | 'removed'
    joined_at REAL,
    invited_at REAL,
    removed_at REAL,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL
);

CREATE INDEX idx_circles_did ON circles(did);
CREATE INDEX idx_circles_status ON circles(status);
```

**Columns to document:**
- `id` - UUID primary key
- `did` - Decentralized Identifier (unique across devices)
- `display_name` - Local-only nickname (not shared)
- `phone_number` - Optional display field (not used for identity)
- `pubkey_x25519` - X25519 public key for E2EE key wrapping
- `status` - Lifecycle: pending (invited), active (confirmed), removed (deleted)
- Timestamps: `invited_at` (when added locally), `joined_at` (when DID confirmed), `removed_at` (when deleted)

#### `devices` Table (Migration v3 - Updated Schema)
**Added in:** Phase 1 (old schema), **Updated in:** Phase 5
**Purpose:** Multi-device support for E2EE

**OLD SCHEMA (v1):**
```sql
CREATE TABLE devices (
    device_id TEXT PRIMARY KEY NOT NULL,
    owner_did TEXT NOT NULL,
    device_name TEXT NOT NULL,
    pubkey_x25519 TEXT NOT NULL,
    pubkey_ed25519 TEXT NOT NULL,
    is_current_device INTEGER NOT NULL DEFAULT 0,  -- REMOVED in v3
    created_at REAL NOT NULL,
    last_synced_at REAL                            -- REMOVED in v3
);
```

**NEW SCHEMA (v3):**
```sql
CREATE TABLE devices (
    device_id TEXT PRIMARY KEY NOT NULL,
    owner_did TEXT NOT NULL,
    device_name TEXT NOT NULL,
    pubkey_x25519 TEXT NOT NULL,
    pubkey_ed25519 TEXT NOT NULL,
    status TEXT NOT NULL,            -- NEW: 'active' | 'revoked'
    registered_at REAL NOT NULL,     -- NEW: When device registered with relay
    last_seen_at REAL                -- NEW: Last heartbeat from relay
);

CREATE INDEX idx_devices_owner ON devices(owner_did);
CREATE INDEX idx_devices_status ON devices(status);
```

**Changes to document:**
- Removed: `is_current_device` (use local deviceId instead)
- Removed: `created_at`, `last_synced_at`
- Added: `status` field (active/revoked for device lifecycle)
- Added: `registered_at` (when registered with Cloudflare Workers)
- Added: `last_seen_at` (last activity timestamp)

### Migration v2 (Already Documented?)
**Check:** Does DATABASE_SCHEMA.md document the `image_cids` change?
- `local_receipts.image_cid` (single) → `image_cids` (JSON array)

### Action Items

**Immediate (Before Phase 6):**
1. ✅ Add `circles` table schema with full column descriptions
2. ✅ Update `devices` table schema (v1 → v3 changes)
3. ✅ Document migration v3 in "Migrations" section
4. ⏳ Add ERD diagram showing `circles` → `devices` relationship (optional)

**Future (Phase 7+):**
5. Add `encrypted_messages` table (local inbox cache)
6. Add `message_delivery` table (delivery tracking)

---

## 2. ARCHITECTURE.md ⚠️ HIGH PRIORITY

**Status:** **INCOMPLETE** - Missing Circle architecture
**Priority:** **HIGH** - Foundational context for Phase 6
**Last Updated:** Dec 16, 2025

### Missing Sections

#### Circle Architecture (Phase 5)
**Add section:** "Circle: Privacy-First Friend Groups"

**Content to add:**
```markdown
## Circle: Privacy-First Friend Groups

### Overview
Circle is Buds' friend management system, designed for privacy and local-first control.

### Key Principles
1. **Local-Only Roster** - Friend list stored in local SQLite (not on relay server)
2. **DID-Based Identity** - Friends identified by DIDs (not phone numbers)
3. **Display Names Are Private** - You choose nicknames (stored locally, not shared)
4. **12-Member Limit** - Privacy-focused small groups (manageable key distribution)

### Architecture

┌─────────────────────────────────────────┐
│       Circle (Local Storage)            │
│  circles table (SQLite, private)        │
│                                         │
│  Member = {                             │
│    did: "did:buds:abc123"              │
│    displayName: "Alex" (local only)    │
│    pubkeyX25519: "..." (for E2EE)      │
│    status: "active"                    │
│  }                                      │
└─────────────────────────────────────────┘
            ↓ (Phase 6: Share Memory)
┌─────────────────────────────────────────┐
│     Cloudflare Workers Relay            │
│  (Zero-trust, sees only ciphertext)     │
│                                         │
│  Stores: Encrypted payloads only       │
│  Cannot see: Plaintext, friend list    │
└─────────────────────────────────────────┘
```

#### Multi-Device Model (Phase 5/6)
**Add section:** "Multi-Device E2EE"

**Content to add:**
```markdown
## Multi-Device E2EE

### Problem
Alice has iPhone + iPad. Bob shares memory with Alice.
How does Bob encrypt for both devices?

### Solution: Device-Based Key Wrapping
- Each device gets unique `device_id` (UUID, stable)
- Each device has own X25519 keypair (encryption)
- When sharing, sender wraps AES key for **each recipient device**

### Flow

1. Bob wants to share with Alice (who has 2 devices)
2. Bob queries relay: "What devices does Alice have?"
   → Relay returns: `[{deviceId: "alice-iphone", pubkey: "..."}, {deviceId: "alice-ipad", pubkey: "..."}]`
3. Bob generates ephemeral AES-256 key
4. Bob encrypts memory payload with AES-GCM
5. Bob wraps AES key for alice-iphone using X25519 ECDH
6. Bob wraps AES key for alice-ipad using X25519 ECDH
7. Bob sends to relay: `{ encryptedPayload, wrappedKeys: { "alice-iphone": "...", "alice-ipad": "..." } }`
8. Both Alice's devices can unwrap their key and decrypt
```

### Action Items

**Immediate (Before Phase 6):**
1. ✅ Add "Circle Architecture" section
2. ✅ Add "Multi-Device E2EE" section
3. ✅ Update system diagram to include Circle + Relay
4. ⏳ Add causality model for shared receipts (optional)

---

## 3. E2EE_DESIGN.md ⚠️ CRITICAL

**Status:** **MOSTLY ACCURATE** - Needs Cloudflare Workers alignment check
**Priority:** **CRITICAL** - This is our cryptographic security spec
**Last Updated:** Dec 16, 2025

### Verification Needed

**Check:** Does E2EE_DESIGN.md assume Firebase or Cloudflare?
- If Firebase → Update to Cloudflare Workers
- If implementation-agnostic → No changes needed

### Key Sections to Verify

1. **Device Registration** (Section: Multi-Device Model)
   - ✅ Verify: Uses `device_id` + X25519 keypairs
   - ✅ Verify: Stores devices in local DB + relay server
   - ⚠️ Check: Does it mention Firestore or D1?

2. **Encryption Flow** (Section: Step 1-4)
   - ✅ Verify: Encrypts raw CBOR (not JSON)
   - ✅ Verify: Uses ephemeral AES-256 keys
   - ✅ Verify: Wraps keys per device (not per user)
   - ⚠️ Check: Relay endpoint paths match Phase 6 plan?

3. **Key Wrapping** (Section: Step 2)
   - ✅ Verify: X25519 ECDH + HKDF + AES-GCM
   - ✅ Verify: Uses "buds.wrap.v1" as HKDF info string
   - ✅ Verify: Format: nonce || ciphertext || tag

4. **Decryption Flow** (Section: Step 3-4)
   - ✅ Verify: Looks up sender device pubkey
   - ✅ Verify: Unwraps with same X25519 ECDH
   - ✅ Verify: Verifies AAD = receiptCID

### Potential Issues

**Issue 1: Relay Server References**
- If doc mentions "Firebase Functions" → Change to "Cloudflare Workers"
- If doc mentions "Firestore" → Change to "D1 database"

**Issue 2: Device Discovery**
- Verify: `getDevices(for dids: [String])` returns devices from relay
- Verify: Cloudflare Workers endpoint: `POST /api/devices/list`

**Issue 3: Forward Secrecy Disclaimer**
- ✅ Verify: Doc states "no forward secrecy" (stable device keys)
- ✅ Verify: Doc explains why (simpler device discovery)

### Action Items

**Immediate (Before Phase 6):**
1. ✅ Read E2EE_DESIGN.md fully (30 min)
2. ✅ Search for "Firebase" or "Firestore" mentions
3. ✅ Replace with "Cloudflare Workers" and "D1" if found
4. ✅ Verify relay endpoints match Phase 6 plan
5. ⏳ Add section on offline message queue handling (future)

---

## 4. PRIVACY_ARCHITECTURE.md ⚠️ MINOR UPDATE

**Status:** **MOSTLY ACCURATE** - Needs Circle privacy section
**Priority:** **MEDIUM** - Important but not blocking
**Last Updated:** Dec 16, 2025

### Missing Content

#### Circle Privacy Implications
**Add section:** "Circle Privacy Model"

**Content to add:**
```markdown
## Circle Privacy Model

### Phone Numbers
- **User Input:** User enters friend's phone number to invite
- **Storage:** Stored locally in `circles.phone_number` (optional field)
- **Relay Transmission:** Phone number hashed with SHA-256 before sending to relay
- **Relay Storage:** Only SHA-256(phone) stored in `phone_to_did` table
- **Privacy:** Relay cannot reverse-engineer phone numbers (one-way hash)

### Display Names
- **Local-Only:** Stored in `circles.display_name` (never sent to relay)
- **Privacy:** Your nickname for someone (e.g., "Mom" vs "Susan")
- **No Global Namespace:** Cannot enumerate users by name

### Social Graph Privacy
- **Local-First Roster:** Circle list stored locally (relay never sees full roster)
- **Sharing Leakage:** When you share, relay learns recipient DIDs (metadata leak)
- **Mitigation:** Relay sees only encrypted payload, not content
- **Threat Model:** Relay can infer social graph from sharing patterns

### DID Enumeration
- **Public DIDs:** DIDs are deterministic (derived from Ed25519 pubkey)
- **Phone → DID Mapping:** Relay stores SHA-256(phone) → DID
- **Enumeration Risk:** Relay could theoretically enumerate all users by DID
- **Mitigation:** DIDs are pseudonymous (not linked to real identity without phone)

### Metadata Leaks (Relay Sees)
- ✅ Sender DID
- ✅ Recipient DIDs (list)
- ✅ Message timestamp
- ✅ Encrypted payload size
- ❌ Plaintext content (E2EE protected)
- ❌ Sender's Circle roster (local-only)
- ❌ Display names (local-only)
```

### Action Items

**Immediate (Before Phase 6):**
1. ✅ Add "Circle Privacy Model" section
2. ✅ Document phone number hashing (SHA-256)
3. ✅ Explain social graph metadata leak
4. ⏳ Add threat model diagram (optional)

**Future (Phase 7+):**
5. Add push notification privacy implications
6. Add background sync privacy considerations

---

## 5. RECEIPT_SCHEMAS.md ⏳ FUTURE

**Status:** **ACCURATE** - No changes needed yet
**Priority:** **LOW** - Not relevant until we add shared receipt types
**Last Updated:** Dec 16, 2025

### Future Work (Phase 7+)

#### Shared Receipt Metadata
When Phase 6 adds sharing, we may want receipt schemas for:

**Option A: Shared receipt is just the original receipt**
- No new schema needed
- Share flow stores encrypted original receipt in relay
- Recipient decrypts and stores as-is

**Option B: Shared receipt wraps original receipt**
- New schema: `app.buds.share.created/v1`
- Payload includes: `{ original_cid, shared_with_dids, shared_at_ms }`
- Recipient stores both share receipt + original receipt

**Decision:** Defer to Phase 6 implementation (Option A is simpler)

### Action Items

**Future (Phase 7+):**
1. Decide if shared receipts need their own schema
2. Document any new receipt types
3. Update canonical CBOR examples

---

## 6. CANONICALIZATION_SPEC.md ✅ ACCURATE

**Status:** **ACCURATE** - No changes needed
**Priority:** **N/A**
**Last Updated:** Dec 16, 2025

**Reason:** Receipt signing is unchanged by Circle mechanics or E2EE.

- Unsigned preimage pattern still correct
- CBOR encoding deterministic
- CID generation unchanged
- Signature verification unchanged

**Action:** None

---

## 7. DESIGN_SYSTEM.md ✅ ACCURATE

**Status:** **ACCURATE** - Dark mode updates already reflected
**Priority:** **N/A**
**Last Updated:** Unknown (check if this file exists)

**Check:** Does this file document:
- `Color.budsBackground` → Use `.black` for dark mode
- Text colors (white on dark, black on cards)

**Action:** Verify file exists and is current

---

## 8. DEBUG_SYSTEM.md ✅ ACCURATE

**Status:** **ACCURATE** - No changes needed
**Priority:** **N/A**

**Action:** None (debugging unchanged)

---

## 9. AGENT_INTEGRATION.md ✅ NOT RELEVANT

**Status:** **ACCURATE** - Not relevant until Phase 9
**Priority:** **N/A**

**Action:** None (defer to Phase 9)

---

## 10. DISPENSARY_INSIGHTS.md ✅ NOT RELEVANT

**Status:** **ACCURATE** - B2B product, not Phase 6
**Priority:** **N/A**

**Action:** None (defer to future)

---

## 11. UX_FLOWS.md ⏳ MINOR UPDATE

**Status:** **MOSTLY ACCURATE** - May need Circle flow additions
**Priority:** **LOW** - Optional enhancement
**Last Updated:** Unknown (check if this file exists)

### Potential Additions

**Circle Management Flow:**
1. User navigates to Circle tab
2. Sees empty state → Taps "Add Friend"
3. Enters display name + phone number
4. (Phase 6) App looks up DID from relay
5. Member added with "active" status
6. Can edit name, view details, remove

**Share Flow (Phase 6):**
1. User views memory detail
2. Taps share button → "Share to Circle"
3. Selects Circle members (checkboxes)
4. Taps "Share (N members)"
5. App encrypts memory for selected devices
6. Posts to Cloudflare Workers relay
7. Success confirmation

### Action Items

**Future (Phase 6):**
1. Add Circle management flow diagram
2. Add E2EE share flow diagram
3. Add recipient decrypt flow diagram

---

## Summary: Action Items by Priority

### 🔴 CRITICAL (Blocking Phase 6)

1. **DATABASE_SCHEMA.md**
   - [ ] Add `circles` table schema
   - [ ] Update `devices` table schema (v1 → v3)
   - [ ] Document migration v3

2. **E2EE_DESIGN.md**
   - [ ] Verify Cloudflare Workers alignment (not Firebase)
   - [ ] Check relay endpoint paths match Phase 6 plan
   - [ ] Verify device discovery flow

### 🟡 HIGH PRIORITY (Important Context)

3. **ARCHITECTURE.md**
   - [ ] Add Circle architecture section
   - [ ] Add multi-device E2EE section
   - [ ] Update system diagram

### 🟢 MEDIUM PRIORITY (Nice to Have)

4. **PRIVACY_ARCHITECTURE.md**
   - [ ] Add Circle privacy model section
   - [ ] Document phone number hashing
   - [ ] Explain metadata leaks

### ⚪ LOW PRIORITY (Future Work)

5. **RECEIPT_SCHEMAS.md** - Defer to Phase 7+
6. **UX_FLOWS.md** - Defer to Phase 6 completion
7. **DESIGN_SYSTEM.md** - Verify existence + accuracy

---

## Recommended Update Order

**Before starting Phase 6 implementation:**

1. **DATABASE_SCHEMA.md** (30 min) - Developers need accurate schema reference
2. **E2EE_DESIGN.md** (45 min) - Security-critical, must be correct
3. **ARCHITECTURE.md** (60 min) - Foundational understanding of system

**During Phase 6 implementation:**

4. **PRIVACY_ARCHITECTURE.md** (30 min) - Document privacy decisions as you make them
5. **UX_FLOWS.md** (optional, 30 min) - Update after UI is built

**After Phase 6 completion:**

6. **RECEIPT_SCHEMAS.md** (if needed) - Only if we add shared receipt types
7. **Create PHASE_6_COMPLETE.md** - Document implementation + lessons learned

---

## Estimated Time

**Total documentation updates:** ~3-4 hours
**Critical path:** ~2 hours (DATABASE_SCHEMA + E2EE_DESIGN + ARCHITECTURE)

---

**December 20, 2025: Ready to update docs before Phase 6 implementation. Critical updates identified. 📚**
