# Buds Receipt Canonicalization Specification

**Last Updated:** December 30, 2025
**Version:** v0.1
**Critical:** This spec defines the exact bytes that are signed and hashed. Do not deviate.

---

## Overview

This document specifies the **exact canonical encoding** for Buds receipts to ensure:
1. **Deterministic CID computation** (same content → same CID)
2. **Verifiable signatures** (anyone can verify without ambiguity)
3. **No circularity** (CID and signature are computed from a canonical preimage)

---

## Core Principle: Unsigned Preimage

The receipt CID and signature are **computed from the same canonical preimage bytes**:

```
UnsignedReceipt → Canonical CBOR → preimage_bytes
  ↓
  ├─→ SHA256(preimage_bytes) → CID
  └─→ Ed25519.sign(preimage_bytes) → signature
```

The `UnsignedReceipt` **excludes** `cid` and `signature` fields.

### Critical Rule: rootCID Handling

**Rule:** The final signed `UCRHeader` MUST include `rootCID` (non-optional). For the first version of a receipt, `rootCID == cid`. For edits, `rootCID` references the original receipt's CID.

**In the unsigned preimage:** `rootCID` is optional (`String?`). It is `nil` when creating a new receipt and set to the root CID when creating an edit.

**When materializing the signed header:** If `rootCID` was `nil` in the unsigned preimage, set it to the newly computed `cid`.

---

## UnsignedReceipt Structure

**Causality-First Architecture:** The header contains only verifiable facts (parentCID chains, signatures) and authorship. Time is a claim in the payload, not a protocol primitive.

```swift
struct UnsignedReceipt: Codable {
    let did: String                    // Author DID
    let deviceId: String?              // Device identifier
    let parentCID: String?             // Edit chain parent (causal ordering)
    let rootCID: String?               // First version (nil for new receipts)
    let receiptType: String            // app.buds.session.created/v1
    let payload: CanonicalPayload      // Strongly-typed, includes claimed_time_ms
    let blobs: [BlobReference]         // Sorted by CID
    // NO timestamp field! Time is in payload as claimed_time_ms
}
```

**Key Architectural Decisions:**
- **Causality = Truth:** `parentCID` chains are verifiable, cryptographic ordering
- **Time = Claim:** `claimed_time_ms` lives in payload (author's assertion, not validated)
- **Strongly-typed payloads:** `CanonicalPayload` protocol, not `[String: AnyCodable]`
- **rootCID handling:** Optional in unsigned preimage (`nil` for new receipts), required in final header (see Critical Rule above)

### Receipt Type Registry

The `receiptType` field uses versioned string identifiers (e.g., `app.buds.session.created/v1`).

**Canonical Source of Truth:** See [RECEIPT_SCHEMAS.md](./RECEIPT_SCHEMAS.md) for the complete registry of all receipt types and their payload schemas.

**Examples:**
- `app.buds.session.created/v1` - New session
- `app.buds.session.updated/v1` - Edit to existing session
- `app.buds.memory.shared/v1` - Share to Circle
- `app.buds.memory.reaction.created/v1` - Add reaction to memory (Phase 10.1)
- `app.buds.memory.reaction.removed/v1` - Remove reaction from memory (Phase 10.1)
- `app.buds.circle.invite.accepted/v1` - Accept Circle invite

**Note:** This spec focuses on the canonical encoding mechanism. Refer to RECEIPT_SCHEMAS.md for payload field definitions and validation rules.

---

## Canonical Payload Encoding

### Problem: `[String: AnyCodable]` is non-deterministic

Issues:
- Type ambiguity: `1` vs `1.0` vs `"1"`
- Float representation: `0.1` may encode differently
- Map key ordering: not guaranteed in Swift dicts

### Solution: Strongly-Typed Per-Receipt Payloads

**Define a canonical struct for each receipt type:**

```swift
// Base protocol for all payloads
protocol ReceiptPayload: Codable {
    var claimed_time_ms: Int64 { get }  // Required: "I claim this happened at..."
}

// Example: Session receipt payload
struct SessionPayload: ReceiptPayload, Canonical {
    // REQUIRED: Time claim (author's assertion)
    let claimed_time_ms: Int64         // Unix milliseconds

    // Optional fields sorted alphabetically
    let amount_grams: Double?          // Canonical: IEEE 754 double
    let cbd_percent: Double?
    let dispensary_name: String?
    let effects: [String]?             // Sorted alphabetically
    let friends_present: [String]?     // Sorted by DID
    let location_cid: String?
    let method: String?                // "joint" | "bong" | "vape" | "edible"
    let mood_after: [String]?          // Sorted alphabetically
    let mood_before: [String]?         // Sorted alphabetically
    let notes: String?
    let photo_cids: [String]?          // Sorted by CID
    let product_brand: String?
    let product_name: String?
    let product_type: String?          // "flower" | "vape" | "edible" | "concentrate"
    let rating: Int?                   // 1-5
    let session_duration_mins: Int?
    let strain_name: String?
    let strain_type: String?           // "hybrid" | "sativa" | "indica"
    let thc_percent: Double?

    // Canonical encoding rules
    func canonicalCBOR() throws -> Data {
        // Encode with keys sorted by CBOR-encoded bytes
        // Omit nil fields (CBOR map only includes present keys)
        // Sort arrays of strings
        // Use IEEE 754 for doubles
        // claimed_time_ms is included as Int64
    }
}
```

**Encoding Rules:**
1. **Map keys**: Sorted by CBOR-encoded key bytes (canonical CBOR map ordering)
2. **Nil fields**: Omitted from CBOR map (not encoded as null)
3. **Arrays of strings**: Sorted alphabetically before encoding
4. **Arrays of DIDs/CIDs**: Sorted by string value
5. **Floats/Doubles**:
   - **Always use `Double`** (IEEE 754 binary64, CBOR major type 7, value 0xFB)
   - **Never use `Float`** (binary32) - always promote to `Double`
   - **Forbidden values**: `NaN`, `+Infinity`, `-Infinity` (these break determinism and MUST be rejected)
   - Use finite floating-point values only
6. **Integers**: Canonical CBOR integer encoding (smallest representation)
7. **Strings**: UTF-8 encoded

**Note:** For typical string keys in English, CBOR-encoded byte ordering usually produces alphabetical order, but the normative rule is to sort by encoded bytes, not lexicographic string comparison.

### Normative Algorithm

The canonical CBOR encoding follows these steps:

1. **Build a CBOR map** of all present (non-nil) fields from the `UnsignedReceipt`
2. **Encode each key** as a CBOR text string (major type 3)
3. **Sort keys** by their CBOR-encoded bytes (canonical map ordering per RFC 8949 §4.2.1)
4. **Encode values** canonically:
   - Integers: Smallest CBOR representation
   - Doubles: IEEE 754 binary64 (CBOR 0xFB)
   - Strings: UTF-8 text strings
   - Arrays: Encoded in order
   - Nested maps: Recursively apply canonical encoding

**Implementation Requirements:**

Use any CBOR library that supports:
- Canonical map key ordering (sorted by encoded bytes)
- Deterministic numeric encoding (smallest integer representation, IEEE 754 for floats)
- Omission of absent fields (not encoding as CBOR null)

**Recommended Swift Libraries:**
- [PotentCodables](https://github.com/outfoxx/PotentCodables) with canonical mode enabled
- [SwiftCBOR](https://github.com/valpackett/SwiftCBOR) with manual sorting
- Any RFC 8949-compliant library with canonical encoding support

---

## Canonical CBOR Encoding Algorithm

### Step 1: Build UnsignedReceipt

```swift
// Payload includes time claim
let sessionPayload = SessionPayload(
    claimed_time_ms: Date().millisecondsSince1970,
    product_name: "Blue Dream",
    strain_type: "hybrid",
    // ... other fields
)

let unsigned = UnsignedReceipt(
    did: myDID,
    deviceId: myDeviceId,
    parentCID: nil,              // Or parent CID for edits
    rootCID: nil,                // Or root CID for edits
    receiptType: "app.buds.session.created/v1",
    payload: sessionPayload,     // Payload contains claimed_time_ms
    blobs: sortedBlobs           // Pre-sorted by CID
)
```

### Step 2: Encode to Canonical CBOR

```swift
func canonicalCBOR(_ receipt: UnsignedReceipt) throws -> Data {
    var encoder = CBOREncoder(canonical: true)

    // Build map with keys sorted by CBOR-encoded bytes
    var map: OrderedMap<String, CBORValue> = [:]

    // Add fields (final ordering determined by CBOR-encoded key bytes)
    if !receipt.blobs.isEmpty {
        map["blobs"] = .array(receipt.blobs.sorted(by: { $0.cid < $1.cid }).map { $0.toCBOR() })
    }

    if let deviceId = receipt.deviceId {
        map["deviceId"] = .string(deviceId)
    }

    map["did"] = .string(receipt.did)

    if let parentCID = receipt.parentCID {
        map["parentCID"] = .string(parentCID)
    }

    map["payload"] = try receipt.payload.canonicalCBOR()  // Payload contains claimed_time_ms

    map["receiptType"] = .string(receipt.receiptType)

    if let rootCID = receipt.rootCID {
        map["rootCID"] = .string(rootCID)
    }

    // Note: timestamp removed from header - now in payload as claimed_time_ms

    return try encoder.encode(map)
}
```

**CBOR Map Encoding:**
- Major type 5 (map)
- Keys sorted by **CBOR-encoded key bytes** (canonical CBOR ordering)
- Values encoded canonically per CBOR spec

---

## CID Computation

### CIDv1 Format

```
<multibase><version><codec><multihash>
```

**Buds Standard:**
- Multibase: `base32` (prefix `b`)
- Version: `0x01` (CIDv1)
- Codec: `0x71` (dag-cbor)
- Multihash: `0x12` (sha2-256) + `0x20` (32 bytes) + SHA256 hash

### Algorithm

```swift
func computeCID(_ preimageBytes: Data) -> String {
    // 1. Hash with SHA256
    let hash = SHA256.hash(data: preimageBytes)
    let hashBytes = Data(hash)

    // 2. Build multihash: <hash-type><length><hash>
    var multihash = Data()
    multihash.append(0x12)  // SHA2-256
    multihash.append(0x20)  // 32 bytes
    multihash.append(contentsOf: hashBytes)

    // 3. Build CID: <version><codec><multihash>
    var cidBytes = Data()
    cidBytes.append(0x01)   // CIDv1
    cidBytes.append(0x71)   // dag-cbor
    cidBytes.append(contentsOf: multihash)

    // 4. Encode as base32 with 'b' prefix
    return "b" + base32Encode(cidBytes).lowercased()
}
```

**Example CID:**
```
bafyreihqfloa6x3xnqtxa7xewgbqfhvzlqq3pjj7kxaijhj4zyvzkm5zfe
```

---

## Signature Computation

### Ed25519 Signature

```swift
func signReceipt(_ preimageBytes: Data, privateKey: Curve25519.Signing.PrivateKey) throws -> String {
    let signature = try privateKey.signature(for: preimageBytes)
    return signature.base64EncodedString()
}
```

**What is signed:** The exact same `preimageBytes` used for CID computation.

---

## Complete Receipt Creation Flow

```swift
func createReceipt(payload: SessionPayload) throws -> UCRHeader {
    // 1. Payload already includes claimed_time_ms
    // e.g., SessionPayload(claimed_time_ms: Date().millisecondsSince1970, ...)

    // 2. Build unsigned receipt (no timestamp in header)
    let unsigned = UnsignedReceipt(
        did: try IdentityManager.shared.currentDID,
        deviceId: try IdentityManager.shared.deviceId,
        parentCID: nil,
        rootCID: nil,
        receiptType: "app.buds.session.created/v1",
        payload: payload,  // Payload contains claimed_time_ms
        blobs: []
    )

    // 3. Encode to canonical CBOR
    let preimage = try canonicalCBOR(unsigned)

    // 4. Compute CID
    let cid = computeCID(preimage)

    // 5. Sign preimage
    let privateKey = try IdentityManager.shared.getPrivateKey()
    let signature = try signReceipt(preimage, privateKey: privateKey)

    // 6. Build full header (includes cid + signature)
    let header = UCRHeader(
        cid: cid,
        did: unsigned.did,
        deviceId: unsigned.deviceId,
        parentCID: unsigned.parentCID,
        rootCID: cid,  // First version: rootCID = cid
        receiptType: unsigned.receiptType,
        payload: payload,
        blobs: unsigned.blobs,
        signature: signature
    )

    // 7. Store with received_at timestamp (local DB time)
    try Database.save(header: header, rawCBOR: preimage, receivedAt: Date())

    return header
}
```

---

## Signature Verification

```swift
func verifyReceipt(_ header: UCRHeader, rawCBOR: Data) throws -> Bool {
    // 1. Extract public key from DID
    let publicKey = try extractPublicKey(from: header.did)

    // 2. Decode signature
    guard let signatureData = Data(base64Encoded: header.signature) else {
        return false
    }

    // 3. Verify signature over raw CBOR
    return publicKey.isValidSignature(signatureData, for: rawCBOR)
}
```

**Critical Invariant:** Implementations MUST store the raw canonical preimage bytes (`rawCBOR`) alongside the receipt in the database. Verification MUST be performed against these stored bytes, never by re-encoding the header (which could introduce non-determinism).

**Database Requirement:** The `raw_cbor` column is required in the `ucr_headers` table (see DATABASE_SCHEMA.md). Without it, signature verification is impossible.

---

## Edit Chains

### Creating an Edit (Updated Receipt)

```swift
func updateReceipt(original: UCRHeader, newPayload: SessionPayload) throws -> UCRHeader {
    // newPayload already includes updated claimed_time_ms

    let unsigned = UnsignedReceipt(
        did: try IdentityManager.shared.currentDID,
        deviceId: try IdentityManager.shared.deviceId,
        parentCID: original.cid,        // Link to previous version (causality)
        rootCID: original.rootCID,      // Preserve root CID (causal chain)
        receiptType: "app.buds.session.updated/v1",
        payload: newPayload,            // Contains new claimed_time_ms
        blobs: []
    )

    let preimage = try canonicalCBOR(unsigned)
    let cid = computeCID(preimage)
    let signature = try signReceipt(preimage, privateKey: getPrivateKey())

    return UCRHeader(
        cid: cid,
        did: unsigned.did,
        deviceId: unsigned.deviceId,
        parentCID: original.cid,        // Causal parent
        rootCID: original.rootCID,      // Same root (verifiable chain)
        receiptType: unsigned.receiptType,
        payload: newPayload,
        blobs: unsigned.blobs,
        signature: signature
    )
}
```

**Edit chain structure:**
```
root (v1) → parent=nil, rootCID=root_cid
  ↓
edit_1 (v2) → parent=root_cid, rootCID=root_cid
  ↓
edit_2 (v3) → parent=edit_1_cid, rootCID=root_cid
```

---

## Canonical Type Mappings

### Swift Type → CBOR Type

| Swift Type | CBOR Type | Notes |
|------------|-----------|-------|
| `String` | Major type 3 (text string) | UTF-8 encoded |
| `Int`, `Int64` | Major type 0/1 (integer) | Canonical: smallest encoding |
| `Double` | Major type 7, value 0xFB (float64) | IEEE 754 binary64 |
| `Bool` | Major type 7, value 0xF4/0xF5 | false=0xF4, true=0xF5 |
| `[T]` | Major type 4 (array) | Elements encoded in order |
| `[String: T]` | Major type 5 (map) | Keys sorted by CBOR-encoded bytes |
| `nil` | **Omitted** | Do not encode as CBOR null |

### Special Cases

**Dates:**
- Store as `Int64` (Unix milliseconds)
- **Not** ISO 8601 strings (non-deterministic timezones)

**DIDs:**
- Always strings (e.g., `"did:buds:local-5dGHK7P9mN"`)

**CIDs:**
- Always strings (e.g., `"bafyreihqfloa..."`)

**Enums:**
- Always strings (e.g., `"hybrid"`, not integer codes)

---

## Test Vectors

### Test Vector 1: Minimal Session

**Input:**
```swift
let payload = SessionPayload(
    claimed_time_ms: 1704844800000,  // 2024-01-10 00:00:00 UTC (in payload)
    product_name: "Blue Dream",
    strain_type: "hybrid",
    notes: "Great for focus",
    rating: 5
)

let unsigned = UnsignedReceipt(
    did: "did:buds:local-ABC123",
    deviceId: "device-001",
    parentCID: nil,
    rootCID: nil,
    receiptType: "app.buds.session.created/v1",
    payload: payload,  // Payload contains claimed_time_ms
    blobs: []          // No timestamp in header
)
```

**Expected Output:**

**TODO:** Test vectors need to be generated for the causality-first architecture (with `claimed_time_ms` in payload, no timestamp in header). Golden test files will be maintained in `/Tests/` with:
- Input `UnsignedReceipt` structure (JSON representation)
- Expected canonical CBOR bytes (hex-encoded)
- Expected CID string
- Expected Ed25519 signature (for a known test keypair)

---

## Implementation Checklist

- [ ] Implement `CanonicalCBOR` encoder with sorted keys
- [ ] Create strongly-typed payload structs for each receipt type
- [ ] Implement `canonicalCBOR()` method for each payload type
- [ ] Update `IdentityManager.signHeader()` to use new flow
- [ ] Store `rawCBOR` in database for verification
- [ ] Write unit tests with test vectors
- [ ] Document any deviations from this spec (requires approval)

---

## Appendix: Why These Choices?

**Causality-first (parentCID chains) instead of timestamps:**
- Causality is verifiable (cryptographically signed)
- Timestamps are unverifiable (device can lie, clock drift, offline)
- Parent CID creates provable ordering across devices
- Time is still captured as `claimed_time_ms` in payload (UI hint, not truth)

**Int64 claimed_time_ms in payload (not header):**
- Keeps protocol layer pure (only verifiable facts)
- Millisecond precision is sufficient
- Still queryable via JSON extraction in SQLite

**Omit nil instead of encoding null:**
- Smaller payloads
- Clearer semantics (field absent vs field present but null)
- Matches JSON convention

**Base32 CIDs instead of Base58:**
- Case-insensitive (URL-safe)
- Standard multibase for CIDv1
- Matches IPFS/IPLD conventions

**Sorted arrays of strings:**
- Deterministic ordering (independent of insertion order)
- Enables structural comparisons

---

**Next:** See [E2EE_DESIGN.md](./E2EE_DESIGN.md) for encryption details.
