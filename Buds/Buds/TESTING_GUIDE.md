# Phase 7 Testing Guide

Complete guide for testing E2EE functionality with one device and analyzing scale.

---

## Prerequisites

1. **Install Python dependencies**:
   ```bash
   pip3 install cryptography requests aiohttp
   ```

2. **Get Firebase ID Token**:
   - Run Buds app on your iPhone
   - Open Xcode console
   - Look for: `🔐 Firebase ID Token: eyJhbGciOiJSUzI1...`
   - Copy the full token (will be ~800 characters)
   - Paste into test scripts where it says `FIREBASE_ID_TOKEN = None`

3. **Update Relay URL**:
   - Edit test scripts and replace with your relay URL:
   ```python
   RELAY_URL = "https://buds-relay-production.ericyarmolinsky.workers.dev"
   ```

---

## Test 1: Single-Device E2EE Flow

**Purpose**: Test E2EE encryption/decryption without needing two physical devices.

**What it tests**:
- ✅ Device registration to relay
- ✅ Message encryption (iPhone)
- ✅ Message decryption (Python simulation)
- ✅ CID integrity verification
- ✅ Signature format validation

**How to run**:

```bash
# 1. Edit test_e2ee_single_device.py
#    - Set FIREBASE_ID_TOKEN
#    - Set RELAY_URL

# 2. Run the test
python3 test_e2ee_single_device.py

# 3. Follow prompts:
#    - Enter your DID (from iPhone)
#    - Enter your phone number
#    - Wait for Device B to register
#    - Share a memory from iPhone
#    - Press Enter to decrypt
```

**Expected output**:
```
📱 Simulated Device Created:
   DID: did:buds:abc123...
   Device ID: 550e8400-e29b-41d4-a716-446655440000
   X25519 Public: TnV4ZGF0YQ==...
   Ed25519 Public: Q2xhdWRlQ29kZQ==...

📡 Registering device to relay...
✅ Device registered successfully

⏸️  PAUSE: Go to your iPhone and share a memory
Press Enter when you've shared a memory...

📬 Polling inbox for did:buds:abc123...
📭 Found 1 messages

🔓 Decrypting message abc12345...
   Sender: did:buds:abc123
   Receipt CID: bafyreiabc123...

🔑 Wrapped key size: 92 bytes
✅ Unwrapped AES key: 32 bytes
✅ Decrypted payload: 2048 bytes CBOR
✅ CID verified - content integrity confirmed
🔐 Signature size: 64 bytes (expected: 64)
✅ Signature format valid

======================================================================
✅ E2EE TEST PASSED!
======================================================================
   CID: bafyreiabc123...
   CBOR size: 2048 bytes
   Sender: did:buds:abc123
   Sender device: 550e8400-e29b...

🗑️  Deleting message from relay...
✅ Message deleted
```

**Troubleshooting**:
- **No messages found**: Wait 30s and try again (polling interval)
- **Registration failed 401**: Firebase token expired, get new one from Xcode
- **CID mismatch**: Check relay URL is correct (dev vs production)
- **Decryption failed**: Verify you're using the same DID on iPhone

---

## Test 2: Relay Stress Test

**Purpose**: Test relay performance under load (1000 users, 10k messages).

**What it tests**:
- ✅ D1 write throughput (message inserts)
- ✅ D1 read throughput (inbox queries)
- ✅ Worker CPU under load
- ✅ Rate limiting effectiveness
- ✅ Concurrent request handling

**How to run**:

```bash
# 1. Edit stress_test_relay.py
#    - Set FIREBASE_ID_TOKEN
#    - Set RELAY_URL
#    - Adjust NUM_USERS (default: 100)
#    - Adjust NUM_MESSAGES (default: 1000)
#    - Adjust CONCURRENCY (default: 10)

# 2. Run stress test
python3 stress_test_relay.py
```

**Expected output**:
```
======================================================================
Buds Relay Stress Test
======================================================================

📝 Creating 100 simulated users...
✅ Registered 100/100 users in 8.45s

📤 Sending 1000 messages (concurrency: 10)...
✅ Sent 1000/1000 messages in 45.23s
   Throughput: 22.11 msg/s

📬 Polling 100 inboxes for 30s...
✅ Completed 600 inbox polls in 30.01s
   Throughput: 19.99 polls/s

======================================================================
STRESS TEST RESULTS
======================================================================

📊 Success Rates:
   Register: 100/100
   Send:     1000/1000
   Inbox:    600/600

⏱️  Latency (ms):
   Register   - avg:  84.50ms  p50:  82.00ms  p95: 120.00ms  p99: 150.00ms
   Send       - avg:  45.23ms  p50:  42.00ms  p95:  68.00ms  p99:  89.00ms
   Inbox      - avg:  20.15ms  p50:  18.00ms  p95:  35.00ms  p99:  45.00ms

======================================================================

✅ Stress test complete!
```

**Interpreting results**:
- **Throughput**: Should be >20 msg/s for sends, >50 polls/s for inbox
- **Latency p95**: Should be <100ms for all operations
- **Success rate**: Should be 100% (no rate limiting at this scale)

**Scaling up**:
```python
# Test with higher load
NUM_USERS = 500        # 500 users
NUM_MESSAGES = 5000    # 5000 messages
CONCURRENCY = 50       # 50 parallel requests

# Watch for:
# - Rate limiting (429 responses)
# - Increased p95/p99 latency
# - Worker CPU timeouts
```

**Troubleshooting**:
- **Rate limited (429)**: Reduce CONCURRENCY or increase rate limits in relay
- **Timeout errors**: Cloudflare Workers CPU limit hit (check relay logs)
- **Failed sends**: Check relay database size (if using D1 for blobs)

---

## Test 3: Scale Analysis

**Purpose**: Understand breaking points at 10k users and 100k messages/day.

**Read**: `SCALE_ANALYSIS.md`

**Key findings**:
- 🔴 **CRITICAL**: D1 blob storage breaks at ~100 messages (need R2 migration)
- 🟡 **WARNING**: Photo storage grows 19 GB/year per heavy user
- 🟡 **WARNING**: Inbox polling wastes 9.6M requests/day
- ✅ **PASSES**: All other metrics (CPU, bandwidth, E2EE performance)

**Action items**:
1. **MUST FIX**: Migrate encrypted payloads from D1 to R2 (before ANY users)
2. **FIX SOON**: Enable APNs push notifications (before 1k users)
3. **FIX LATER**: Implement tiered photo storage (before users hit iPhone limits)

---

## Test 4: Manual Relay API Testing (curl)

**Purpose**: Test individual relay endpoints without Python.

### Get Firebase Token

```bash
# 1. Run app on iPhone
# 2. Copy token from Xcode logs:
#    🔐 Firebase ID Token: eyJhbGciOiJSUzI1...

export FIREBASE_TOKEN="eyJhbGciOiJSUzI1..."
export RELAY_URL="https://buds-relay-production.ericyarmolinsky.workers.dev"
```

### Test Device Registration

```bash
curl -X POST "$RELAY_URL/api/devices/register" \
  -H "Authorization: Bearer $FIREBASE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "550e8400-e29b-41d4-a716-446655440000",
    "device_name": "Test Device",
    "owner_did": "did:buds:abc123",
    "owner_phone_hash": "9b74c9897bac770ffc029102a200c5de",
    "pubkey_x25519": "TnV4ZGF0YQ==",
    "pubkey_ed25519": "Q2xhdWRlQ29kZQ=="
  }'
```

Expected: `201 Created`

### Test Inbox Polling

```bash
curl -X GET "$RELAY_URL/api/messages/inbox?did=did:buds:abc123&limit=50" \
  -H "Authorization: Bearer $FIREBASE_TOKEN"
```

Expected: `{"messages": [...], "count": 0, "has_more": false}`

### Test Message Send

```bash
curl -X POST "$RELAY_URL/api/messages/send" \
  -H "Authorization: Bearer $FIREBASE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "message_id": "msg-123",
    "receipt_cid": "bafyreiabc123",
    "sender_did": "did:buds:abc123",
    "sender_device_id": "550e8400-e29b-41d4-a716-446655440000",
    "recipient_dids": ["did:buds:xyz789"],
    "encrypted_payload": "base64encrypteddata",
    "wrapped_keys": {"device-uuid": "base64wrappedkey"},
    "signature": "base64signature88chars"
  }'
```

Expected: `201 Created`

### Test Health Endpoint (No Auth)

```bash
curl "$RELAY_URL/health"
```

Expected: `{"status": "ok", "timestamp": 1234567890}`

---

## Testing Checklist

### Before Launch

- [ ] Run single-device E2EE test (verify encryption/decryption works)
- [ ] Run stress test with 100 users, 1000 messages (verify no errors)
- [ ] Read SCALE_ANALYSIS.md (understand bottlenecks)
- [ ] **CRITICAL**: Migrate relay from D1 blobs to R2 storage
- [ ] Test on real iPhone (share memory, verify it appears in timeline)
- [ ] Test cross-device (borrow a friend's phone for 10 minutes)

### Before 100 Users

- [ ] Enable APNs push notifications (replace polling)
- [ ] Run stress test with 500 users, 5000 messages
- [ ] Monitor Cloudflare dashboard for errors
- [ ] Check D1 database size (should be <100 MB if using R2)

### Before 1000 Users

- [ ] Implement tiered photo storage (30-day hot tier + iCloud)
- [ ] Run stress test with 1000 users, 10k messages
- [ ] Profile iOS app with 10k receipts in database
- [ ] Test APNs delivery at peak load

---

## Common Issues

### "No messages found" in single-device test
- **Cause**: Inbox polling hasn't run yet
- **Fix**: Wait 30 seconds and try again

### "Registration failed 401"
- **Cause**: Firebase token expired (valid for 1 hour)
- **Fix**: Get fresh token from Xcode logs

### "CID mismatch" error
- **Cause**: Relay tampering or wrong relay URL
- **Fix**: Verify RELAY_URL matches what iPhone app uses

### "Signature verification failed"
- **Cause**: Sender not in Circle, or device not registered
- **Fix**: Add sender to Circle first, ensure device registered

### Stress test shows high failure rate
- **Cause**: Rate limiting kicking in
- **Fix**: Reduce CONCURRENCY or increase rate limits in relay

### D1 database full error
- **Cause**: Storing encrypted payloads in D1 (blobs too large)
- **Fix**: CRITICAL - migrate to R2 storage immediately

---

## Next Steps

1. **Run single-device test** to verify Phase 7 E2EE works
2. **Run stress test** to ensure relay can handle load
3. **Read scale analysis** to understand when things break
4. **Fix D1 blob storage** (critical before launch)
5. **Test on real device** to verify end-to-end flow

All test files are in: `/Users/ericyarmolinsky/Developer/Buds/Buds/Buds/`
- `test_e2ee_single_device.py` - Single-device E2EE test
- `stress_test_relay.py` - Relay stress test
- `SCALE_ANALYSIS.md` - Scale analysis document
- `TESTING_GUIDE.md` - This file

---

Happy testing! 🚀
