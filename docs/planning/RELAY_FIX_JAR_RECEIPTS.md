# Relay Fix: POST /api/jars/:jar_id/receipts

## The Bug

Relay is looking up Ed25519 public key using **Firebase UID** instead of **DID extracted from receipt**.

**Error**: `❌ No Ed25519 public key found for FLrpCAH1RxV1EOqJuOmZZ3HgVvQ2`
**Root Cause**: `FLrpCAH1RxV1EOqJuOmZZ3HgVvQ2` is a Firebase UID, but `devices.owner_did` stores DIDs like `did:phone:347fd6a9...`

---

## Current Code (BROKEN)

```typescript
// File: src/endpoints/jarReceipts.ts (or similar)

export async function storeJarReceipt(request: Request, env: Env, ctx: Context) {
  // LAYER 1: Firebase authentication ✅ (correct)
  const user = ctx.user; // Firebase auth middleware
  const firebaseUID = user.uid;

  const { jar_id } = ctx.params;
  const { receipt_data, signature, parent_cid } = await request.json();

  // ❌ BUG: Looking up device by Firebase UID instead of DID
  const senderDevice = await env.DB.prepare(
    'SELECT pubkey_ed25519 FROM devices WHERE owner_did = ? AND status = ?'
  ).bind(firebaseUID, 'active').first();
  //       ^^^^^^^^^^^ WRONG! This is Firebase UID, not DID

  if (!senderDevice) {
    throw new Error(`❌ No Ed25519 public key found for ${firebaseUID}`);
  }

  // Signature verification would fail anyway because wrong key
  // ...
}
```

---

## Fixed Code (CORRECT)

```typescript
// File: src/endpoints/jarReceipts.ts

import { decodeFirst } from 'cbor';

export async function storeJarReceipt(request: Request, env: Env, ctx: Context) {
  // LAYER 1: Firebase authentication ✅
  // This proves the HTTP caller is logged in (spam prevention)
  const user = ctx.user;
  const firebaseUID = user.uid;

  const { jar_id } = ctx.params;
  const { receipt_data, signature, parent_cid } = await request.json();

  // LAYER 2: Extract DID from signed receipt ✅
  // This proves WHO signed the receipt (cryptographic identity)
  const receiptCBOR = Buffer.from(receipt_data, 'base64');
  let decoded;
  try {
    decoded = decodeFirst(receiptCBOR);
  } catch (err) {
    throw new Error('Invalid CBOR encoding');
  }

  // Extract sender DID from receipt payload
  const senderDID = decoded.sender_did;
  if (!senderDID || !senderDID.startsWith('did:phone:')) {
    throw new Error('Invalid or missing sender_did in receipt');
  }

  console.log(`🔐 Receipt from DID: ${senderDID} (Firebase UID: ${firebaseUID})`);

  // ✅ FIXED: Look up device by DID (not Firebase UID)
  const senderDevice = await env.DB.prepare(`
    SELECT pubkey_ed25519, device_id
    FROM devices
    WHERE owner_did = ? AND status = ?
    ORDER BY last_seen_at DESC
    LIMIT 1
  `).bind(senderDID, 'active').first();
  //       ^^^^^^^^^^ CORRECT! DID from receipt signature

  if (!senderDevice) {
    console.error(`❌ No device found for DID: ${senderDID}`);
    throw new Error(`Sender device not registered or no public key found`);
  }

  // LAYER 3: Verify Ed25519 signature ✅
  const pubkeyBytes = Buffer.from(senderDevice.pubkey_ed25519, 'base64');
  const signatureBytes = Buffer.from(signature, 'base64');

  const isValid = await verifyEd25519Signature(
    receiptCBOR,
    signatureBytes,
    pubkeyBytes
  );

  if (!isValid) {
    console.error(`❌ Invalid signature for DID: ${senderDID}`);
    throw new Error('Invalid receipt signature');
  }

  console.log(`✅ Signature verified for DID: ${senderDID}`);

  // LAYER 4: Check jar membership (authorization)
  const isMember = await env.DB.prepare(`
    SELECT 1 FROM jar_members
    WHERE jar_id = ? AND member_did = ? AND status = 'active'
  `).bind(jar_id, senderDID).first();

  if (!isMember) {
    console.error(`❌ DID ${senderDID} not a member of jar ${jar_id}`);
    throw new Error('Not a member of this jar');
  }

  // LAYER 5: Compute CID and assign sequence number
  const receiptCID = await computeCID(receiptCBOR);

  // Get next sequence number (atomic increment)
  const result = await env.DB.prepare(`
    INSERT INTO jar_receipts (jar_id, receipt_cid, receipt_data, signature, sender_did, parent_cid, received_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    RETURNING sequence_number
  `).bind(
    jar_id,
    receiptCID,
    receipt_data,
    signature,
    senderDID,
    parent_cid,
    Date.now()
  ).first();

  const sequenceNumber = result.sequence_number;

  console.log(`✅ Stored jar receipt: seq=${sequenceNumber}, cid=${receiptCID}, jar=${jar_id}`);

  return Response.json({
    success: true,
    receipt_cid: receiptCID,
    sequence_number: sequenceNumber,
    jar_id: jar_id
  });
}

// Helper: Verify Ed25519 signature (use Web Crypto API)
async function verifyEd25519Signature(
  message: Uint8Array,
  signature: Uint8Array,
  publicKey: Uint8Array
): Promise<boolean> {
  try {
    const cryptoKey = await crypto.subtle.importKey(
      'raw',
      publicKey,
      { name: 'Ed25519' },
      false,
      ['verify']
    );

    return await crypto.subtle.verify(
      'Ed25519',
      cryptoKey,
      signature,
      message
    );
  } catch (err) {
    console.error('Ed25519 verification error:', err);
    return false;
  }
}

// Helper: Compute CID (use existing implementation)
async function computeCID(data: Uint8Array): Promise<string> {
  // Your existing CID computation from Module 0.6
  // Should match iOS: CIDv1, dag-cbor, sha2-256
  // ... (keep existing implementation)
}
```

---

## Key Changes

### 1. Extract DID from Receipt (Lines 15-27)
```typescript
// OLD (wrong):
const firebaseUID = user.uid; // "FLrpCAH1RxV1EOqJuOmZZ3HgVvQ2"

// NEW (correct):
const decoded = decodeFirst(receiptCBOR);
const senderDID = decoded.sender_did; // "did:phone:347fd6a9..."
```

**Why**: Receipt is signed by DID, not Firebase UID. Must extract from receipt payload.

### 2. Look Up Device by DID (Lines 29-37)
```typescript
// OLD (wrong):
WHERE owner_did = ? // Firebase UID - doesn't exist in devices table

// NEW (correct):
WHERE owner_did = ? // DID from receipt - matches devices.owner_did
```

**Why**: `devices.owner_did` column stores DIDs (e.g., `did:phone:...`), not Firebase UIDs.

### 3. Verify Signature (Lines 39-50)
```typescript
// Now uses correct public key (from DID lookup)
const isValid = await verifyEd25519Signature(
  receiptCBOR,
  signatureBytes,
  pubkeyBytes
);
```

**Why**: Ed25519 signature can only be verified with the matching public key.

### 4. Check Jar Membership by DID (Lines 52-60)
```typescript
// Use DID for membership check (not Firebase UID)
WHERE jar_id = ? AND member_did = ? AND status = 'active'
```

**Why**: jar_members table stores DIDs, not Firebase UIDs.

---

## Security Layers (Correct Architecture)

```
Request Flow:
────────────

1. HTTP Request arrives
   ↓
2. Firebase Auth Middleware (LAYER 1)
   ✅ Validates JWT token
   ✅ Extracts Firebase UID
   ✅ Prevents anonymous spam
   ↓
3. Extract DID from Receipt (LAYER 2)
   ✅ Decode CBOR
   ✅ Get sender_did from payload
   ✅ Proves cryptographic identity
   ↓
4. Look Up Device by DID (LAYER 2)
   ✅ Query: WHERE owner_did = <DID>
   ✅ Get Ed25519 public key
   ↓
5. Verify Signature (LAYER 2)
   ✅ Verify Ed25519(receipt, signature, pubkey)
   ✅ Proves receipt wasn't tampered with
   ✅ Proves sender owns this DID
   ↓
6. Check Jar Membership (LAYER 3)
   ✅ Query: WHERE jar_id = ? AND member_did = <DID>
   ✅ Proves sender is authorized for this jar
   ↓
7. Assign Sequence & Store (LAYER 4)
   ✅ Atomic sequence increment
   ✅ Store in jar_receipts table
   ✅ Return to client
```

**Physics**:
- **Firebase UID** = session auth (who is calling)
- **DID** = cryptographic identity (who signed the data)
- These are **separate namespaces** by design

---

## Dependencies

Add to `package.json` if not already present:
```json
{
  "dependencies": {
    "cbor": "^9.0.0"
  }
}
```

---

## Testing

After deploying:

```bash
# Test from iOS app
# Should see in relay logs:
🔐 Receipt from DID: did:phone:347fd6a9... (Firebase UID: FLrpCAH1RxV1EOqJuOmZZ3HgVvQ2)
✅ Signature verified for DID: did:phone:347fd6a9...
✅ Stored jar receipt: seq=2, cid=bafy..., jar=abc123
```

**Success criteria**:
- ✅ No more "No Ed25519 public key found" errors
- ✅ Jar receipts get stored with sequence numbers
- ✅ Members can add each other to jars
- ✅ Jar sync polling works

---

## Files to Update

1. **src/endpoints/jarReceipts.ts** (or wherever POST /api/jars/:jar_id/receipts is defined)
   - Extract DID from receipt payload
   - Look up device by DID (not Firebase UID)
   - Verify signature with correct public key

2. **src/utils/crypto.ts** (if Ed25519 verification helper doesn't exist)
   - Add verifyEd25519Signature() using Web Crypto API

3. **package.json**
   - Add cbor dependency if missing

---

## One More Thing: The iOS Side

**Verify iOS is sending correct data**:

In `RelayClient+JarReceipts.swift:38-65`, ensure:
```swift
var body: [String: Any] = [
    "receipt_data": receiptData.base64EncodedString(),  // ✅ Has sender_did inside
    "signature": signature.base64EncodedString(),
    "parent_cid": parentCID  // Optional
]
```

The `receipt_data` CBOR MUST include `sender_did` field. This was implemented in Module 5b.

**Verify with**:
```swift
// In JarManager.swift:110-118
let receiptCBOR = try ReceiptCanonicalizer.encodeJarReceiptPayload(
    jarID: jarID,
    receiptType: "jar.created",
    senderDID: ownerDID,  // ✅ This field is critical
    timestamp: Int64(Date().timeIntervalSince1970 * 1000),
    parentCID: nil,
    payload: payloadCBOR
)
```

If `senderDID` is missing from the CBOR, the relay fix won't work.

---

## Next Steps

1. Apply this fix to your relay code
2. Deploy to Cloudflare: `npm run deploy:dev`
3. Test adding member in TestFlight
4. Check Cloudflare logs for success messages
5. If it works → deploy to prod: `npm run deploy:prod`
