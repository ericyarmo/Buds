# Quick E2EE Test Instructions

## 🚀 3-Step Test Process

### Step 1: Run App on iPhone
```bash
# Open Xcode and build to your physical iPhone
# Phone: 650-445-8988
# DID: did:buds:3mVJmCTSNQf1VRQZmwsNHvJLYHaA
```

### Step 2: Copy Firebase Token
In Xcode console, look for:
```
🔐 Firebase ID Token: eyJhbGciOiJSUzI1NiIsImtpZCI6IjNjYmFm...
```
Copy the **full token** (starts with `eyJ`, ~800 characters)

### Step 3: Run Test Script
```bash
cd /Users/ericyarmolinsky/Developer/Buds/Buds/Buds
./run_e2ee_test.sh
```

The script will:
1. Ask for Firebase token → paste it
2. Register simulated Device B
3. Wait for you to **share a memory from iPhone**
4. Decrypt and verify the message

---

## What Gets Tested ✅

- ✅ Device registration to relay (api.getstreams.app)
- ✅ E2EE encryption (iPhone) → decryption (Python)
- ✅ X25519 key unwrapping
- ✅ AES-256-GCM decryption
- ✅ CID integrity verification (prevents tampering)
- ✅ Ed25519 signature format validation

---

## Expected Output

```
======================================================================
Phase 7 E2EE Single-Device Test Harness
======================================================================

📝 Using DID: did:buds:3mVJmCTSNQf1VRQZmwsNHvJLYHaA
📝 Using Phone: +16504458988
📞 Phone hash: 9b74c9897bac770ffc...

📱 Simulated Device Created:
   DID: did:buds:3mVJmCTSNQf1VRQZmwsNHvJLYHaA
   Device ID: 550e8400-e29b-41d4-a716-446655440000
   X25519 Public: TnV4ZGF0YQ==...
   Ed25519 Public: Q2xhdWRlQ29kZQ==...

📡 Registering device to relay...
✅ Device registered successfully

======================================================================
⏸️  PAUSE: Go to your iPhone and share a memory
======================================================================
Press Enter when you've shared a memory...

📬 Polling inbox for did:buds:3mVJmCTSNQf1VRQZmwsNHvJLYHaA...
📭 Found 1 messages

🔓 Decrypting message abc12345...
   Sender: did:buds:3mVJmCTSNQf1VRQZmwsNHvJLYHaA
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
   Sender: did:buds:3mVJmCTSNQf1VRQZmwsNHvJLYHaA
   Sender device: 550e8400-e29b...

🗑️  Deleting message from relay...
✅ Message deleted
```

---

## Troubleshooting

### "No messages found"
- Wait 30 seconds and try again (inbox polling interval)
- Verify you shared the memory to your Circle

### "Registration failed 401"
- Firebase token expired (valid ~1 hour)
- Get fresh token from Xcode logs

### "CID mismatch"
- Relay URL mismatch (verify `api.getstreams.app`)
- Check relay is running

### "Decryption failed"
- Verify DID matches between iPhone and test script
- Check wrapped keys include the simulated device ID

---

## Changes Made

- ✅ Updated RelayClient.swift to use `api.getstreams.app`
- ✅ Added Firebase token logging to RelayClient
- ✅ Fixed E2EEManager signature verification
- ✅ Updated CircleManager with device-specific key lookup
- ✅ Fixed InboxManager with CID integrity check
- ✅ Python test script configured with your DID/phone

---

## After Test Passes

Next steps:
1. Read SCALE_ANALYSIS.md for production readiness
2. Fix D1 blob storage (migrate to R2) - CRITICAL
3. Enable APNs push notifications
4. Implement tiered photo storage

Ready to test! 🚀
