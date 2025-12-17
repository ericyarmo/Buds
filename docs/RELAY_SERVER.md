# Buds Relay Server API (Cloudflare Workers)

**Last Updated:** December 16, 2025
**Version:** v0.1
**Runtime:** Cloudflare Workers + D1
**Deployment:** Edge compute (global distribution)

---

## Overview

The Buds relay server is a **thin, untrusted intermediary** for E2EE message delivery. It stores only encrypted payloads and metadata—never plaintext.

### Design Principles

1. **Zero-knowledge**: Server never sees plaintext messages
2. **Stateless**: Workers are stateless (state in D1)
3. **Rate-limited**: Prevent abuse without breaking privacy
4. **Ephemeral**: Messages auto-expire after delivery
5. **Auditable**: All operations logged (encrypted CIDs only)

---

## API Endpoints

### Base URL

```
https://relay.getbuds.app
```

**Environments:**
- Production: `https://relay.getbuds.app`
- Staging: `https://staging-relay.getbuds.app`
- Dev: `http://localhost:8787` (wrangler dev)

---

## 1. Device Management

### 1.1 Register Device

**POST** `/v1/devices`

**Purpose:** Register a new device for receiving messages

**Request:**
```json
{
    "device_id": "F3A7C2B1-8D4E-4F9A-B2C6-7E8F9A0B1C2D",
    "owner_did": "did:buds:5dGHK7P9mN",
    "device_name": "Alice's iPhone",
    "pubkey_x25519": "Wy0xMjM0NTY3ODkwMTIzNDU2Nzg5MDEyMzQ1Njc4OTA=",
    "pubkey_ed25519": "Xy0xMjM0NTY3ODkwMTIzNDU2Nzg5MDEyMzQ1Njc4OTA=",
    "firebase_token": "f3a7c2b1...",  // FCM push token
    "signature": "base64_sig"  // Ed25519 signature over (device_id + owner_did + pubkeys)
}
```

**Response:**
```json
{
    "success": true,
    "device_id": "F3A7C2B1-8D4E-4F9A-B2C6-7E8F9A0B1C2D",
    "registered_at": 1704844800000  // Milliseconds
}
```

**Errors:**
- `400`: Invalid signature or missing fields
- `409`: Device already registered
- `429`: Rate limit exceeded

---

### 1.2 Get Devices for DID

**GET** `/v1/devices?did=<did>`

**Purpose:** Fetch all active devices for a Circle member

**Authentication:** Required. Must provide Ed25519 signature proving you own the requesting DID OR that the target DID has authorized you (Circle member).

**Request Headers:**
```
Authorization: Bearer <base64_signature>
X-Requester-DID: did:buds:xyz123
X-Request-Timestamp: 1704844800000
```

**Signature payload:** `GET:/v1/devices:did=<target_did>:timestamp=<timestamp>`

**Response:**
```json
{
    "devices": [
        {
            "device_id": "F3A7C2B1...",
            "owner_did": "did:buds:5dGHK7P9mN",
            "device_name": "Alice's iPhone",
            "pubkey_x25519": "Wy0x...",
            "pubkey_ed25519": "Xy0x...",
            "status": "active",
            "last_seen_at": 1704844800000  // Milliseconds
        }
    ]
}
```

**Errors:**
- `400`: Missing `did` parameter
- `401`: Missing or invalid authentication
- `403`: Requester not authorized to access this DID's devices
- `404`: No devices found for DID

---

### 1.3 Revoke Device

**DELETE** `/v1/devices/:device_id`

**Purpose:** Mark device as revoked (stop accepting new messages)

**Request:**
```json
{
    "owner_did": "did:buds:5dGHK7P9mN",
    "signature": "base64_sig"  // Ed25519 signature over (device_id + owner_did + current_time)
}
```

**Response:**
```json
{
    "success": true,
    "device_id": "F3A7C2B1...",
    "revoked_at": 1704844800000  // Milliseconds
}
```

**Errors:**
- `403`: Invalid signature or not owner
- `404`: Device not found

---

## 2. Message Delivery

### 2.1 Send Message

**POST** `/v1/messages`

**Purpose:** Send encrypted message to Circle members

**Request:**
```json
{
    "message_id": "msg_abc123",
    "receipt_cid": "bafyreiabc123...",  // CID of the receipt being shared
    "encrypted_payload": "<base64_sealed_combined>",  // AES.GCM.SealedBox.combined (nonce || ciphertext || tag)
    "wrapped_keys": {
        "F3A7C2B1-8D4E-4F9A-B2C6-7E8F9A0B1C2D": "wrapped_key_base64_1",  // deviceId → wrapped key
        "A1B2C3D4-5E6F-7G8H-9I0J-1K2L3M4N5O6P": "wrapped_key_base64_2"
    },
    "sender_did": "did:buds:5dGHK7P9mN",
    "sender_device_id": "F3A7C2B1...",
    "recipient_dids": ["did:buds:ABC", "did:buds:XYZ"],
    "expires_at": 1704931200000,  // Optional milliseconds, default 7 days
    "signature": "base64_sig"  // Ed25519 signature over (message_id + receipt_cid + sender_did + relay_sent_at_ms)
}
```

**Response:**
```json
{
    "success": true,
    "message_id": "msg_abc123",
    "delivered_to": ["F3A7C2B1-8D4E-4F9A-B2C6-7E8F9A0B1C2D", "A1B2C3D4-5E6F-7G8H-9I0J-1K2L3M4N5O6P"],
    "push_sent": true,
    "relay_sent_at_ms": 1704844800000  // Milliseconds when relay processed the message
}
```

**Errors:**
- `400`: Invalid signature, missing fields, or empty wrapped_keys
- `401`: Invalid signature
- `413`: Payload too large (max 10MB)
- `429`: Rate limit exceeded (max 100 messages/hour per DID)

**Note:** `encrypted_payload` must be the full `AES.GCM.SealedBox.combined` representation (nonce || ciphertext || tag), NOT separate fields.

**Rate Limits:**
- 100 messages/hour per sender DID
- 10MB max payload size
- Max 24 recipients (12 Circle members × 2 devices)

---

### 2.2 Fetch Messages

**GET** `/v1/messages?device_id=<device_id>&since=<relay_sent_at_ms>`

**Purpose:** Fetch encrypted messages for a device

**Query Params:**
- `device_id`: Required
- `since`: Optional Unix milliseconds (fetch messages sent after this timestamp)
- `limit`: Optional (default 50, max 200)

**Response:**
```json
{
    "messages": [
        {
            "message_id": "msg_abc123",
            "receipt_cid": "bafyreiabc123...",  // CID of the receipt being shared
            "encrypted_payload": "<base64_sealed_combined>",  // Full AES.GCM.SealedBox.combined
            "wrapped_key": "wrapped_key_base64",  // Only YOUR wrapped key (for this device_id)
            "sender_did": "did:buds:5dGHK7P9mN",
            "sender_device_id": "F3A7C2B1...",
            "relay_sent_at_ms": 1704844800000  // Milliseconds when relay processed message
        }
    ],
    "has_more": false,
    "next_cursor": null
}
```

**Notes:**
- Each device only receives its own `wrapped_key` (not all keys)
- Messages auto-deleted after 7 days or after first fetch (configurable)

**Errors:**
- `400`: Missing `device_id`
- `404`: No messages found

---

### 2.3 Acknowledge Message

**DELETE** `/v1/messages/:message_id?device_id=<device_id>`

**Purpose:** Mark message as received (optional, for cleanup)

**Response:**
```json
{
    "success": true,
    "message_id": "msg_abc123",
    "deleted": true
}
```

---

## 3. Push Notifications

### 3.1 Update FCM Token

**PUT** `/v1/devices/:device_id/push-token`

**Purpose:** Update Firebase Cloud Messaging token for push notifications

**Request:**
```json
{
    "firebase_token": "new_fcm_token_here",
    "signature": "base64_sig"
}
```

**Response:**
```json
{
    "success": true,
    "device_id": "F3A7C2B1...",
    "updated_at": 1704844800000  // Milliseconds
}
```

---

### 3.2 Push Notification Payload

**Sent to FCM when new message arrives:**

```json
{
    "notification": {
        "title": "New shared memory",
        "body": "Tap to view",
        "badge": 1
    },
    "data": {
        "type": "new_message",
        "message_id": "msg_abc123",
        "sender_did": "did:buds:5dGHK7P9mN"  // DID only (no name)
    }
}
```

**Privacy notes:**
- Push notification contains **no plaintext content** (only encrypted envelope metadata)
- Sender name is NOT included (only pseudonymous DID)
- App resolves DID → display name locally after fetching Circle data
- This prevents iOS/FCM from seeing social graph or real names

---

## 4. Health & Monitoring

### 4.1 Health Check

**GET** `/health`

**Response:**
```json
{
    "status": "ok",
    "version": "0.1.0",
    "timestamp": 1704844800000,  // Milliseconds
    "db_status": "connected"
}
```

---

### 4.2 Metrics

**GET** `/v1/metrics` (Admin only)

**Response:**
```json
{
    "total_devices": 1234,
    "active_devices_24h": 456,
    "total_messages": 5678,
    "messages_24h": 123,
    "avg_message_size_kb": 45.2,
    "db_size_mb": 123.4
}
```

**Auth:** Requires admin API key

---

## Database Schema (D1)

### Devices Table

```sql
CREATE TABLE devices (
    device_id TEXT PRIMARY KEY NOT NULL,
    owner_did TEXT NOT NULL,
    device_name TEXT NOT NULL,
    pubkey_x25519 TEXT NOT NULL,            -- Base64-encoded X25519 public key (32 bytes)
    pubkey_ed25519 TEXT NOT NULL,           -- Base64-encoded Ed25519 public key (32 bytes)
    firebase_token TEXT,                    -- FCM push token
    status TEXT NOT NULL DEFAULT 'active',  -- 'active' | 'revoked'
    last_seen_at_ms INTEGER,                -- Milliseconds
    created_at_ms INTEGER NOT NULL,         -- Milliseconds
    revoked_at_ms INTEGER                   -- Milliseconds (null if active)
);

CREATE INDEX idx_devices_did ON devices(owner_did);
CREATE INDEX idx_devices_status ON devices(status);
```

---

### Messages Table

```sql
CREATE TABLE messages (
    message_id TEXT PRIMARY KEY NOT NULL,
    receipt_cid TEXT NOT NULL,              -- CID of the receipt being shared
    encrypted_payload BLOB NOT NULL,        -- Full AES.GCM.SealedBox.combined (nonce || ciphertext || tag)
    wrapped_keys_json TEXT NOT NULL,        -- JSON: {deviceId: wrappedKey}
    sender_did TEXT NOT NULL,
    sender_device_id TEXT NOT NULL,
    recipient_dids_json TEXT NOT NULL,      -- JSON array
    relay_sent_at_ms INTEGER NOT NULL,      -- Milliseconds when relay processed message
    expires_at_ms INTEGER,                  -- Milliseconds
    delivered_to_json TEXT,                 -- JSON array of device_ids
    created_at_ms INTEGER NOT NULL          -- Milliseconds when relay received message
);

CREATE INDEX idx_messages_relay_sent_at ON messages(relay_sent_at_ms DESC);
CREATE INDEX idx_messages_expires ON messages(expires_at_ms);
```

---

### Rate Limits Table

```sql
CREATE TABLE rate_limits (
    key TEXT PRIMARY KEY NOT NULL,          -- "send:<did>" or "fetch:<device_id>"
    count INTEGER NOT NULL DEFAULT 0,
    window_start_ms INTEGER NOT NULL,       -- Milliseconds
    expires_at_ms INTEGER NOT NULL          -- Milliseconds
);

CREATE INDEX idx_rate_limits_expires ON rate_limits(expires_at_ms);
```

---

## Security Measures

### 1. Signature Verification

**All mutating operations require Ed25519 signatures:**

```typescript
async function verifySignature(
    payload: string,
    signature: string,
    publicKeyBase64: string
): Promise<boolean> {
    const publicKey = await crypto.subtle.importKey(
        'raw',
        base64Decode(publicKeyBase64),
        { name: 'Ed25519' },
        false,
        ['verify']
    );

    const signatureBytes = base64Decode(signature);
    const payloadBytes = new TextEncoder().encode(payload);

    return await crypto.subtle.verify(
        'Ed25519',
        publicKey,
        signatureBytes,
        payloadBytes
    );
}
```

**Signed payloads:**
- Device registration: `device_id + owner_did + pubkeys + current_time_ms`
- Send message: `message_id + receipt_cid + sender_did + relay_sent_at_ms`
- Revoke device: `device_id + owner_did + current_time_ms`

---

### 2. Rate Limiting

**Per-DID limits:**
- **Send messages**: 100/hour
- **Device registration**: 5/day
- **Fetch messages**: 1000/hour per device

**Implementation (sliding window):**

```typescript
async function checkRateLimit(
    key: string,
    limit: number,
    windowMs: number
): Promise<boolean> {
    const nowMs = Date.now();
    const windowStartMs = nowMs - (nowMs % windowMs);

    const result = await env.DB.prepare(
        'SELECT count FROM rate_limits WHERE key = ? AND window_start_ms = ?'
    ).bind(key, windowStartMs).first();

    if (!result) {
        // Create new window
        await env.DB.prepare(
            'INSERT INTO rate_limits (key, count, window_start_ms, expires_at_ms) VALUES (?, 1, ?, ?)'
        ).bind(key, windowStartMs, windowStartMs + windowMs + 3600000).run();  // +1 hour buffer
        return true;
    }

    if (result.count >= limit) {
        return false;  // Rate limit exceeded
    }

    // Increment counter
    await env.DB.prepare(
        'UPDATE rate_limits SET count = count + 1 WHERE key = ? AND window_start_ms = ?'
    ).bind(key, windowStartMs).run();

    return true;
}
```

---

### 3. Input Validation

**All inputs validated:**

```typescript
function validateMessageRequest(body: any): ValidationResult {
    const errors: string[] = [];

    // Check required fields
    if (!body.message_id || typeof body.message_id !== 'string') {
        errors.push('Invalid message_id');
    }

    // Validate CID format
    if (!body.receipt_cid || !body.receipt_cid.startsWith('bafyre')) {
        errors.push('Invalid receipt_cid format');
    }

    // Validate payload size
    const payloadSize = Buffer.byteLength(body.encrypted_payload, 'base64');
    if (payloadSize > 10 * 1024 * 1024) {  // 10MB
        errors.push('Payload too large');
    }

    // Validate wrapped_keys
    if (!body.wrapped_keys || Object.keys(body.wrapped_keys).length === 0) {
        errors.push('wrapped_keys cannot be empty');
    }

    if (Object.keys(body.wrapped_keys).length > 24) {
        errors.push('Too many recipients (max 24)');
    }

    return { valid: errors.length === 0, errors };
}
```

---

### 4. Message Expiration

**Auto-cleanup expired messages:**

```typescript
// Run as cron trigger (daily)
export async function cleanupExpiredMessages(env: Env) {
    const nowMs = Date.now();

    const result = await env.DB.prepare(
        'DELETE FROM messages WHERE expires_at_ms IS NOT NULL AND expires_at_ms < ?'
    ).bind(nowMs).run();

    console.log(`Deleted ${result.meta.changes} expired messages`);

    // Also cleanup old rate limit windows
    await env.DB.prepare(
        'DELETE FROM rate_limits WHERE expires_at_ms < ?'
    ).bind(nowMs).run();
}
```

---

## Deployment

### Wrangler Configuration

**wrangler.toml:**

```toml
name = "buds-relay"
main = "src/index.ts"
compatibility_date = "2024-01-01"

[[ d1_databases ]]
binding = "DB"
database_name = "buds-relay-prod"
database_id = "<D1_DATABASE_ID>"

[vars]
ENVIRONMENT = "production"

[[kv_namespaces]]
binding = "KV"
id = "<KV_NAMESPACE_ID>"

[triggers]
crons = ["0 2 * * *"]  # Daily at 2am UTC for cleanup
```

---

### Deployment Commands

```bash
# Install dependencies
npm install

# Run locally
npm run dev

# Deploy to staging
wrangler deploy --env staging

# Deploy to production
wrangler deploy --env production

# Run migrations
wrangler d1 migrations apply buds-relay-prod

# View logs
wrangler tail
```

---

## Error Responses

**Standard error format:**

```json
{
    "error": "rate_limit_exceeded",
    "message": "Too many messages sent. Try again in 15 minutes.",
    "retry_after_ms": 900000,  // Milliseconds until retry allowed
    "timestamp": 1704844800000  // Milliseconds
}
```

**Error codes:**
- `400`: Bad request (invalid input)
- `401`: Unauthorized (invalid signature)
- `403`: Forbidden (not owner)
- `404`: Not found
- `409`: Conflict (duplicate)
- `413`: Payload too large
- `429`: Rate limit exceeded
- `500`: Internal server error

---

## Monitoring & Logging

### CloudFlare Analytics

**Metrics tracked:**
- Request count by endpoint
- Error rate by status code
- P50/P95/P99 latency
- Bandwidth (ingress/egress)
- Cache hit rate

### Custom Logging

```typescript
function logEvent(type: string, data: any) {
    console.log(JSON.stringify({
        timestamp: Date.now(),
        type,
        ...data
    }));
}

// Examples
logEvent('message_sent', {
    message_id: msg.message_id,
    sender_did: msg.sender_did,
    recipient_count: msg.recipient_dids.length
});

logEvent('device_registered', {
    device_id: device.device_id,
    owner_did: device.owner_did
});
```

---

## Cost Estimation

**Cloudflare Workers pricing (as of December 2025 - verify current pricing):**

| Resource | Free Tier | Paid |
|----------|-----------|------|
| Requests | 100K/day | $0.50 per million |
| CPU time | 10ms/request | $0.02 per million GB-s |
| D1 reads | 5M/day | $0.001 per million |
| D1 writes | 100K/day | $1.00 per million |
| Storage | 5GB | $0.75/GB/month |

**For 10K active users (v0.1 scale):**
- ~50K requests/day → Free tier
- ~500K D1 reads/day → Free tier
- ~10K D1 writes/day → Free tier
- ~1GB storage → Free tier

**Estimated monthly cost: $0** (within free tier)

---

## Future Enhancements

### Post-v0.1

1. **WebSocket support** for real-time delivery (no polling)
2. **E2EE group chat** (not just share receipts)
3. **Delivery receipts** (confirm recipient decrypted)
4. **Message reactions** (encrypted emoji reactions)
5. **Blob storage integration** (R2 for photos/videos)

---

**Next:** See [PRIVACY_ARCHITECTURE.md](./PRIVACY_ARCHITECTURE.md) for location privacy design.
