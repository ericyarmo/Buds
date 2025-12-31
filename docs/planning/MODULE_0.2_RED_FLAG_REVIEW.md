# Module 0.2: Phone-Based Identity - Red Flag Review

**Date:** December 30, 2025
**Reviewer:** Claude Sonnet 4.5
**Status:** Pre-implementation review

---

## Summary

**Overall Assessment:** ✅ **SAFE TO PROCEED** with 3 important caveats

**Estimated Time:** 4-6 hours (plan is reasonable)
**Complexity:** Medium-High
**Breaking Changes:** Yes (DID format changes)

---

## What Module 0.2 Does

### Current (Broken)
```swift
// Each device = different DID
Device A (iPhone): DID = did:buds:hash(Ed25519_pubkey_A)
Device B (iPad):   DID = did:buds:hash(Ed25519_pubkey_B)
// Two different identities for same user!
```

### After Module 0.2 (Fixed)
```swift
// Phone = identity, devices share DID
User (phone +1234567890):
  Device A: DID = did:phone:SHA256(phone + account_salt)
  Device B: DID = did:phone:SHA256(phone + account_salt)
// Same DID, both devices share identity!
```

---

## Red Flags Identified

### 🟡 RED FLAG #1: Breaking Change for Existing Users

**Problem:**
- Changing DID format means existing DIDs stop working
- All existing receipts have old `did:buds:xyz` format
- All existing jar memberships use old DIDs

**Impact:**
- Existing users will appear as "new" users
- Old receipts won't verify (DID mismatch)
- Jar memberships break (old DID ≠ new DID)

**Mitigation Options:**

**Option A: Accept Break (V1 Beta)**
```swift
// Simplest: Just break for beta users
// - Delete old data
// - Generate new DID
// - Re-register device
// - Fresh start

// Pros: Simple, clean slate
// Cons: Lose beta user data (acceptable for beta)
```

**Option B: Dual DID Support (More Complex)**
```swift
// Support both old and new DIDs temporarily
// Migration flow:
// 1. Generate new phone-based DID
// 2. Keep old device-based DID in database
// 3. Re-sign all receipts with new DID
// 4. Update jar memberships
// 5. Sync to relay

// Pros: No data loss
// Cons: 10-15 hours of migration work
```

**RECOMMENDATION:** Option A (accept break) for V1 beta
- We're in beta, users expect changes
- Clean slate is better than complex migration
- Option B deferred to V2 if needed

**Action Required:**
- ✅ Add migration notice in app ("Data will be reset for security upgrade")
- ✅ Add data export feature before migration (optional)
- ✅ Document breaking change in release notes

---

### 🟢 RED FLAG #2: Relay Dependency for Account Salt

**Problem:**
```swift
// DID = SHA256(phone + account_salt)
// Where does account_salt come from?
// Answer: Relay stores it

// This means:
// 1. First login: Generate salt, send to relay
// 2. Second device: Fetch salt from relay
// 3. Offline? Can't derive DID without salt
```

**Impact:**
- Can't derive DID when offline (salt not cached locally)
- Relay outage = can't add new devices
- Relay must be trusted to not lose salts

**Mitigation:**

**Cache salt locally after first fetch:**
```swift
func getAccountSalt() async throws -> String {
    // Check local cache first
    if let cached = try loadStringFromKeychain(key: "account_salt") {
        return cached
    }

    // Fetch from relay
    let phone = Auth.auth().currentUser?.phoneNumber
    let salt = try await RelayClient.shared.getAccountSalt(phone: phone)

    // Cache locally
    try saveStringToKeychain(key: "account_salt", value: salt)
    return salt
}
```

**RECOMMENDATION:** Cache salt locally
- First device generates and uploads salt
- Subsequent devices fetch and cache salt
- Offline works after first sync

**Action Required:**
- ✅ Add `account_salt` to keychain storage
- ✅ Add relay endpoint `/api/account/salt` (get or create)
- ✅ Handle salt fetch during registration

---

### 🟡 RED FLAG #3: Phone Number Privacy

**Problem:**
```swift
// Phone number is now part of identity
// DID = SHA256(phone + salt)

// Privacy concerns:
// - Phone is PII (personally identifiable)
// - Salt prevents rainbow tables, but...
// - Relay sees plaintext phone during registration
// - If relay is compromised, phones are exposed
```

**Impact:**
- Phone numbers stored on relay (encrypted in Module 0.3)
- Relay operator can see phone numbers
- Law enforcement can subpoena phone list

**Mitigation:**

Module 0.3 adds deterministic encryption (already planned):
```typescript
// Relay never stores plaintext phones
const encryptedPhone = await encryptPhone(phone, key);
// Deterministic: same phone → same ciphertext (for lookups)

// DB stores encrypted_phone, not phone
// Requires both DB leak AND secret key to expose phones
```

**RECOMMENDATION:** Proceed with Module 0.2, rely on Module 0.3 for full protection
- Module 0.2: Phone-based DID (functional)
- Module 0.3: Encrypted phone storage (privacy)
- Both needed for complete solution

**Action Required:**
- ✅ Document privacy model in security docs
- ✅ Ensure Module 0.3 completed before V1 release
- ✅ Add "Privacy: E2EE + Phone Encryption" to marketing

---

## Technical Review

### Changes Required (IdentityManager.swift)

**Current DID generation:**
```swift
func getDID() throws -> String {
    let signingKey = try getSigningKeypair()
    let pubkeyBytes = signingKey.publicKey.rawRepresentation
    let first20 = pubkeyBytes.prefix(20)
    let base58 = Base58.encode(Data(first20))
    return "did:buds:\(base58)"
}
```

**New DID generation:**
```swift
func getDID() async throws -> String {
    // Get phone from Firebase Auth
    guard let phone = Auth.auth().currentUser?.phoneNumber else {
        throw IdentityError.phoneNotAvailable
    }

    // Get or create account salt
    let salt = try await getAccountSalt()

    // Derive DID
    return deriveDID(phoneNumber: phone, accountSalt: salt)
}

private func deriveDID(phoneNumber: String, accountSalt: String) -> String {
    let combined = phoneNumber + accountSalt
    let hash = SHA256.hash(data: combined.data(using: .utf8)!)
    let hashHex = hash.map { String(format: "%02x", $0) }.joined()
    return "did:phone:\(hashHex)"
}

private func getAccountSalt() async throws -> String {
    // Check cache
    if let cached = try loadStringFromKeychain(key: "account_salt") {
        return cached
    }

    // Fetch from relay
    guard let phone = Auth.auth().currentUser?.phoneNumber else {
        throw IdentityError.phoneNotAvailable
    }

    let salt = try await RelayClient.shared.getOrCreateAccountSalt(phone: phone)

    // Cache locally
    try saveStringToKeychain(key: "account_salt", value: salt)
    return salt
}
```

**Changes:**
- ✅ `getDID()` becomes async (needs relay call)
- ✅ Add phone number validation (E.164 format)
- ✅ Add account_salt keychain storage
- ✅ Add relay API call for salt management

### Changes Required (RelayClient.swift)

**New endpoint:**
```swift
func getOrCreateAccountSalt(phone: String) async throws -> String {
    // POST /api/account/salt
    // Body: { "phone": "+1234567890" }
    // Response: { "salt": "abc123..." }

    // Relay logic:
    // 1. Look up salt by phone
    // 2. If exists, return it
    // 3. If not, generate random 32-byte salt, store, return
}
```

**Changes:**
- ✅ Add new endpoint to RelayClient
- ✅ Add Cloudflare Worker route `/api/account/salt`
- ✅ Add D1 table: `account_salts (phone_hash TEXT PRIMARY KEY, salt TEXT)`

### Changes Required (DeviceManager.swift)

**Current registration:**
```swift
let did = try await identity.currentDID
// Uses old did:buds:xyz format
```

**New registration:**
```swift
let did = try await identity.getDID()
// Now async, uses did:phone:hash format
```

**Changes:**
- ✅ Update all `currentDID` calls to handle async
- ✅ Update relay registration to use new DID format

---

## Database Migration

**No schema changes required!**

DIDs are just strings - `did:buds:xyz` and `did:phone:abc` both fit in existing VARCHAR columns.

**However, for beta users:**
```sql
-- Clear old data (beta users only)
DELETE FROM ucr_headers;
DELETE FROM memories;
DELETE FROM jars;
DELETE FROM jar_memberships;
DELETE FROM devices;

-- No schema changes needed
```

**For production migration (deferred to V2):**
```sql
-- Add new column for DID version
ALTER TABLE ucr_headers ADD COLUMN did_version INTEGER DEFAULT 1;

-- Mark old receipts as v1 (device-based DID)
UPDATE ucr_headers SET did_version = 1 WHERE did LIKE 'did:buds:%';

-- New receipts use v2 (phone-based DID)
-- did LIKE 'did:phone:%' → did_version = 2
```

---

## Testing Checklist

**Unit Tests:**
- [ ] DID derivation from phone + salt
- [ ] Account salt caching (keychain)
- [ ] Account salt fetch from relay
- [ ] Phone number validation (E.164)

**Integration Tests:**
- [ ] Register device with new DID format
- [ ] Second device gets same DID
- [ ] Relay salt persistence
- [ ] Offline DID derivation (after cache)

**Manual Tests:**
- [ ] Delete app, reinstall → same DID
- [ ] Add second device → same DID
- [ ] Relay salt lookup works
- [ ] Jar invite with new DID

---

## Relay Work Required

**New Cloudflare Worker Route:**

File: `buds-relay/src/handlers/accountSalt.ts`

```typescript
export async function handleGetOrCreateAccountSalt(
  request: Request,
  env: Env
): Promise<Response> {
  const { phone } = await request.json();

  // Hash phone for lookup (privacy)
  const phoneHash = await sha256(phone);

  // Look up existing salt
  const existing = await env.DB.prepare(
    'SELECT salt FROM account_salts WHERE phone_hash = ?'
  ).bind(phoneHash).first();

  if (existing) {
    return jsonResponse({ salt: existing.salt });
  }

  // Generate new salt (32 bytes, base64)
  const salt = base64Encode(crypto.getRandomValues(new Uint8Array(32)));

  // Store salt
  await env.DB.prepare(
    'INSERT INTO account_salts (phone_hash, salt, created_at) VALUES (?, ?, ?)'
  ).bind(phoneHash, salt, Date.now()).run();

  return jsonResponse({ salt });
}
```

**New D1 Table:**

```sql
CREATE TABLE account_salts (
  phone_hash TEXT PRIMARY KEY,
  salt TEXT NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE INDEX idx_account_salts_created_at ON account_salts(created_at);
```

**Changes:**
- ✅ Add route to `src/index.ts`
- ✅ Create migration `0004_account_salts.sql`
- ✅ Deploy to Workers

---

## Security Review

### ✅ STRENGTHS
1. **Multi-device identity works** - Same DID across devices
2. **Salt prevents rainbow tables** - Can't reverse DID → phone
3. **Phone already authenticated** - Firebase verified phone ownership
4. **Relay can group devices** - Lookup all devices for a DID

### ⚠️ WEAKNESSES (Addressed in Module 0.3)
1. **Relay sees plaintext phone** - Fixed by deterministic encryption
2. **Relay controls salt** - Acceptable (relay is semi-trusted)
3. **No forward secrecy** - Deferred to Phase 12 (known limitation)

### 🔴 RISKS
1. **Breaking change for beta users** - Mitigated by data reset notice
2. **Relay outage = can't add devices** - Mitigated by salt caching
3. **Phone required for identity** - Acceptable tradeoff (UX matches reality)

---

## Decision: Proceed or Revise?

**✅ PROCEED WITH MODULE 0.2**

**Conditions:**
1. ✅ Accept beta user data reset (no migration)
2. ✅ Implement salt caching (keychain)
3. ✅ Complete Module 0.3 before V1 release (phone encryption)

**Estimated Time:** 4-6 hours (unchanged)

**Implementation Order:**
1. Relay work first (account salt endpoint) - 1h
2. IdentityManager changes (DID derivation) - 2h
3. DeviceManager updates (registration) - 1h
4. Testing (unit + manual) - 1-2h

---

## Final Checklist Before Starting

- [ ] Relay deployed with `/api/account/salt` endpoint
- [ ] D1 migration `0004_account_salts.sql` applied
- [ ] Beta users notified about data reset
- [ ] Module 0.3 plan reviewed (next after 0.2)

---

## Recommendation

**SHIP IT. Module 0.2 is well-designed and ready to implement.**

The phone-based identity model is the right architectural choice:
- Solves multi-device DID problem (critical)
- Aligns with user expectations (phone = identity)
- Enables relay to group devices (needed for jar sync)
- Privacy preserved by Module 0.3 encryption (next)

Breaking change is acceptable for beta. Migration plan exists for production.

**Next:** Implement Module 0.2, then immediately follow with Module 0.3 (phone encryption) before any beta release.

---

**Status:** ✅ APPROVED - Ready to implement
