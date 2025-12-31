# CBOR Encoding Stability Policy

**Last Updated:** December 30, 2025
**Phase:** 10.3 Module 0.1
**Status:** 🔒 LOCKED - Changes require migration plan

---

## Critical Warning

**⚠️ DO NOT modify the CBOR encoding without a migration plan.**

The Buds app uses CBOR (Concise Binary Object Representation) to encode receipts before signing them with Ed25519. The exact CBOR bytes are what get signed - any change to the encoding will **break ALL existing signatures**.

### What happens if CBOR encoding changes?

1. ❌ **All existing receipts become unverifiable** (signatures fail)
2. ❌ **CIDs change** (content addressing breaks)
3. ❌ **Parent chains break** (causality ordering fails)
4. ❌ **User data becomes inaccessible** (cannot decrypt, verify, or trust)

**This is a catastrophic failure mode.** Do NOT change CBOR encoding lightly.

---

## Implementation Details

### CBOR Library: Custom Implementation

**File:** `Buds/Core/ChaingeKernel/CBORCanonical.swift`

We use a **custom CBOR encoder** (not an external library) ported from BudsKernelGolden. This gives us:

✅ Full control over encoding behavior
✅ No dependency on external library updates
✅ Deterministic canonical output (RFC 8949 compliant)
✅ Physics-tested performance (0.11ms p50)

**The implementation is frozen. Do not modify CBORCanonical.swift without:**
1. Reading this entire document
2. Creating a migration plan
3. Getting approval from project owner
4. Updating all golden tests

### Golden Tests: Canonicality Enforcement

**File:** `BudsTests/CBORCanonicalityTests.swift`

We maintain **golden test vectors** that freeze the exact CBOR bytes for known inputs:

```swift
func testSessionPayload_MinimalFields_GoldenBytes() throws {
    let payload = SessionPayload(/* fixed test data */)
    let cbor = try ReceiptCanonicalizer.encodeSessionPayload(payload)
    let hex = cbor.hexString

    // This hex value is captured once and MUST NEVER CHANGE
    XCTAssertEqual(hex, "a5...")
}
```

**If any golden test fails:**
1. ❌ DO NOT blindly update the expected hex value
2. ✅ Investigate WHY the encoding changed
3. ✅ Check git history for changes to CBORCanonical.swift or payload structs
4. ✅ If intentional, follow the migration plan below

---

## Canonical Encoding Rules

### Map Keys: Sorted by CBOR-Encoded Bytes

**Rule:** CBOR maps MUST have keys sorted by their encoded byte representation (lexicographic order).

**Why:** RFC 8949 canonical CBOR requirement. Ensures deterministic output.

**Example:**
```swift
// These keys are sorted by CBOR-encoded bytes, NOT alphabetically
{
  "claimed_time_ms": 1000,   // 0x6F + "claimed_time_ms"
  "effects": ["relaxed"],     // 0x67 + "effects"
  "product_name": "Test",     // 0x6C + "product_name"
  "rating": 5                 // 0x66 + "rating"
}
```

For typical English field names, CBOR byte ordering happens to match alphabetical order, but **the normative rule is byte ordering**.

### Integers: Smallest Representation

**Rule:** Use the smallest CBOR encoding for each integer value.

| Value Range | Encoding | Example |
|-------------|----------|---------|
| 0-23 | Single byte | `5` → `0x05` |
| 24-255 | Major type + 1 byte | `24` → `0x18 0x18` |
| 256-65535 | Major type + 2 bytes | `256` → `0x19 0x01 0x00` |
| 65536+ | Major type + 4 or 8 bytes | `100000` → `0x1A ...` |

**Why:** Canonical CBOR requires smallest encoding. Prevents `5` vs `0x18 0x05` ambiguity.

### Doubles: IEEE 754 Binary64 Only

**Rule:** All floating-point numbers MUST use CBOR major type 7, additional info 27 (0xFB) - IEEE 754 binary64 (8 bytes).

**Never use:**
- ❌ Float32 (0xFA) - not canonical
- ❌ Float16 (0xF9) - loses precision

**Forbidden values:**
- ❌ `NaN` (not deterministic)
- ❌ `+Infinity`, `-Infinity` (breaks signatures)

**Why:** Ensures consistent representation across platforms. IEEE 754 binary64 is the ONLY canonical float type.

### Nil Fields: Omitted, Not Null

**Rule:** Optional fields that are `nil` MUST be omitted from the CBOR map entirely.

**Correct:**
```swift
// rating is nil
let payload = SessionPayload(rating: nil, ...)
// CBOR map does NOT include "rating" key
```

**Incorrect:**
```swift
// ❌ NEVER encode nil as CBOR null (0xF6)
```

**Why:** Smaller payloads, clearer semantics, matches JSON convention.

### Arrays: Elements in Original Order

**Rule:** Array elements are encoded in the order provided.

**Exception:** If the payload struct specifies that an array should be sorted (e.g., `effects` sorted alphabetically), sort it **before** encoding.

**Example:**
```swift
struct SessionPayload {
    let effects: [String]  // Should be sorted alphabetically
}

// In the app:
let payload = SessionPayload(
    effects: ["relaxed", "creative", "euphoric"].sorted()
)
```

**Why:** Determinism. Same logical content → same bytes.

---

## Test Coverage

### Golden Tests (BudsTests/CBORCanonicalityTests.swift)

| Test | What It Validates |
|------|------------------|
| `testSessionPayload_MinimalFields_GoldenBytes` | Minimal SessionPayload CBOR output |
| `testSessionPayload_AllFields_GoldenBytes` | Full SessionPayload with all optionals |
| `testReactionAddedPayload_GoldenBytes` | ReactionAdded receipt CBOR |
| `testReactionRemovedPayload_GoldenBytes` | ReactionRemoved receipt CBOR |
| `testUnsignedReceiptPreimage_GoldenBytes` | Full unsigned receipt structure |
| `testCBORMapKeyOrdering_IsCanonical` | Map keys sorted by encoded bytes |
| `testDoubleEncoding_IEEE754Binary64` | Doubles use 0xFB encoding |
| `testIntegerEncoding_SmallestRepresentation` | Integers use canonical size |

**Run tests:**
```bash
xcodebuild test \
  -project Buds.xcodeproj \
  -scheme Buds \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:BudsTests/CBORCanonicalityTests
```

**Expected result:** ✅ All tests pass (golden values match exactly)

**If tests fail:**
1. Check what changed (git diff CBORCanonical.swift)
2. If intentional, follow migration plan (see below)
3. If accidental, revert the change

---

## Migration Plan (If Encoding Must Change)

### Phase 15: CBOR Migration (Future)

**Only proceed if absolutely necessary** (e.g., critical security fix, unavoidable library upgrade).

**Steps:**

1. **Create migration branch**
   ```bash
   git checkout -b phase-15-cbor-migration
   ```

2. **Implement dual verification**
   - Add `cbor_version` field to database
   - Support BOTH old and new encoding for verification
   - New receipts use new encoding
   - Old receipts verify with old encoding

3. **Update canonicalizer**
   ```swift
   enum CBORVersion: Int {
       case v1 = 1  // Original (frozen)
       case v2 = 2  // New encoding
   }

   static func canonicalCBOR(_ receipt: UnsignedReceipt, version: CBORVersion) throws -> Data {
       switch version {
       case .v1: return try canonicalCBORv1(receipt)  // Frozen implementation
       case .v2: return try canonicalCBORv2(receipt)  // New implementation
       }
   }
   ```

4. **Re-sign all receipts**
   - Background migration job
   - Create v2 receipts for all existing data
   - Keep v1 receipts for historical verification

5. **Update golden tests**
   - Keep v1 golden tests (frozen forever)
   - Add v2 golden tests
   - Document differences

6. **Deprecation timeline**
   - Version 1.x: Support both v1 and v2 verification
   - Version 2.x: Default to v2, support v1 verification
   - Version 3.x: v1 deprecated (warning), still works
   - Version 4.x: v1 removed (only v2 supported)

**Estimated effort:** 20-30 hours
**Complexity:** VERY HIGH (touches all receipt verification)
**Risk:** EXTREME (can lose user data if done wrong)

---

## What Changes Are Safe?

### ✅ Safe Changes (No Migration Needed)

1. **Add new receipt types**
   - Example: Add `app.buds.jar.created/v1`
   - Requires: New payload struct, new encoder function, new golden test
   - Impact: None (existing receipts unaffected)

2. **Add optional fields to payloads**
   - Example: Add `strainType` to SessionPayload
   - Requires: Update struct with optional field, regenerate golden test for NEW receipts
   - Impact: Existing receipts still verify (nil fields omitted)

3. **Add new payload structs**
   - Example: Create `JarCreatedPayload`
   - Requires: New struct, new encoder, new golden test
   - Impact: None (independent from existing types)

4. **Update comments or documentation**
   - Impact: None (comments don't affect CBOR output)

### ❌ Unsafe Changes (Require Migration)

1. **Modify CBORCanonical.swift encoding logic**
   - ❌ Change map key sorting algorithm
   - ❌ Change integer encoding rules
   - ❌ Change double encoding (IEEE 754 format)
   - ❌ Encode nil as CBOR null instead of omitting

2. **Rename existing payload fields**
   - ❌ Rename `product_name` to `productName`
   - ❌ Change CodingKeys
   - Reason: Field names are part of CBOR map keys

3. **Change field types in existing payloads**
   - ❌ Change `rating: Int` to `rating: Double`
   - ❌ Change `effects: [String]` to `effects: String`
   - Reason: CBOR type tag changes

4. **Remove fields from existing payloads**
   - ❌ Remove `notes` from SessionPayload
   - Reason: Breaks decoding of existing receipts

5. **Change array ordering semantics**
   - ❌ Stop sorting `effects` alphabetically
   - Reason: Same data would encode to different bytes

---

## Emergency Procedures

### If Golden Tests Fail Unexpectedly

1. **STOP** - Do not commit or merge
2. Run `git diff Buds/Core/ChaingeKernel/CBORCanonical.swift`
3. Run `git diff Buds/Core/Models/UCRHeader.swift`
4. Identify what changed
5. If change was accidental: `git checkout -- <file>`
6. If change was intentional: Follow migration plan

### If Encoding Bug Discovered in Production

1. **Assess severity:**
   - Does it affect signature verification? (CRITICAL)
   - Does it affect CID computation? (CRITICAL)
   - Does it only affect specific payload types? (HIGH)

2. **Immediate mitigation:**
   - If catastrophic: Roll back to previous version
   - If contained: Add workaround in verification layer

3. **Long-term fix:**
   - Create hotfix branch
   - Implement dual verification (support old + new)
   - Deploy migration (see Phase 15 plan)

---

## Related Documentation

- [CANONICALIZATION_SPEC.md](./architecture/CANONICALIZATION_SPEC.md) - Full canonical receipt spec
- [RECEIPT_SCHEMAS.md](./architecture/RECEIPT_SCHEMAS.md) - All receipt types and payloads
- [E2EE_DESIGN.md](./architecture/E2EE_DESIGN.md) - How receipts are encrypted and signed

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| v1.0 | 2025-12-30 | Initial freeze (Phase 10.3 Module 0.1) |

---

## Summary

**Three rules to remember:**

1. 🔒 **CBOR encoding is frozen** - Do not modify CBORCanonical.swift
2. ✅ **Golden tests must pass** - If they fail, investigate before updating
3. 📋 **Follow migration plan** - If encoding must change, use Phase 15 protocol

**When in doubt, ask first.** Changing CBOR encoding is a breaking change to the entire system.

---

**Next:** See [CBORCanonicalityTests.swift](../Buds/Buds/BudsTests/CBORCanonicalityTests.swift) for test implementation.
