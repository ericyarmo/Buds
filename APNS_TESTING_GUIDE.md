# APNs Push Notifications Testing Guide

**Status**: 100% Implemented (Phase 6)
**Test Date**: TBD (after plane WiFi)
**Priority**: High (95% reduction in wasted requests)

---

## Pre-Flight Check ✅

All code already exists from Phase 6:

- ✅ iOS APNs registration (BudsApp.swift:22)
- ✅ Token upload to relay (BudsApp.swift:51)
- ✅ Silent push handler (BudsApp.swift:65-96)
- ✅ Inbox poll on push (BudsApp.swift:84)
- ✅ Relay sends APNs push (messages.ts:121)
- ✅ APNs credentials configured in Cloudflare Workers

---

## Test 1: APNs Token Registration (5 min)

**Goal**: Verify iPhone registers for APNs and uploads token to relay

### Steps:

1. **Kill and restart the app** (fresh launch)
2. **Watch Xcode Console** for these logs:

```
🔧 [DEBUG] AppDelegate didFinishLaunchingWithOptions called
🔧 [DEBUG] Registering for remote notifications...
📲 APNs token: <64-hex-characters>
✅ APNs token uploaded to relay
```

3. **Verify token uploaded to relay**:
   - Check Cloudflare D1: `devices` table
   - Find your device: `device_id = E3EAADEA-83C0-4BA3-9790-86C893C55271`
   - Column `apns_token` should be populated (64 hex chars)

### Success Criteria:

- ✅ APNs token appears in console (64 hex characters)
- ✅ "APNs token uploaded to relay" log appears
- ✅ No errors in console
- ✅ D1 devices table shows apns_token for your device

### If It Fails:

**Symptom**: "Failed to register for remote notifications"
- **Cause**: Simulator (APNs only works on real device)
- **Fix**: Must test on physical iPhone

**Symptom**: APNs token is nil
- **Cause**: No internet connection or Firebase not configured
- **Fix**: Check WiFi, verify GoogleService-Info.plist exists

---

## Test 2: Silent Push Reception (10 min)

**Goal**: Verify relay sends silent push when message shared

### Setup:

You need **2 devices** OR **1 device + Python test script**:

**Option A: Two iPhones** (Easier)
1. Device A (sender): Your iPhone
2. Device B (receiver): Friend's iPhone or your iPad

**Option B: One iPhone + Python Script** (What we did yesterday)
1. Device A (sender): Your iPhone
2. Device B (receiver): Python test script simulates receiver

### Steps (Option A - Two iPhones):

1. **Device B: Open app, watch Xcode Console**
   - Should see: "📬 Inbox notification received, triggering poll"

2. **Device A: Share a memory to Circle**
   - Go to Memory Detail → Share to Circle → Select Device B's user

3. **Device B: Watch for silent push** (within 2-5 seconds):

```
📲 Silent push received
📬 Inbox notification received, triggering poll
📬 Received 1 messages
📥 [INBOX] Processing message <uuid>
✅ [INBOX] CID verified - content matches claimed CID
✅ [INBOX] Signature verified - message is authentic
✅ [INBOX] Message <uuid> fully processed and stored
```

4. **Device B: Check Timeline**
   - Shared memory should appear immediately (no 30s delay!)

### Steps (Option B - Python Script):

1. **Run Python test script** (simulates Device B):
   ```bash
   cd /Users/ericyarmolinsky/Developer/Buds/Buds/Buds
   python3 test_e2ee_single_device.py
   ```

2. **Share memory from iPhone** (Device A)

3. **Watch relay logs**:
   ```bash
   cd /Users/ericyarmolinsky/Developer/buds-relay
   npx wrangler tail --env production
   ```

   Look for:
   ```
   Push notification sent successfully to device <uuid>
   ```

### Success Criteria:

- ✅ Silent push received within 2-5 seconds of share
- ✅ Inbox poll triggered automatically (no 30s wait)
- ✅ Message decrypted and stored successfully
- ✅ Shared memory appears in Timeline immediately
- ✅ Relay logs: "Push notification sent successfully"

### If It Fails:

**Symptom**: No push notification received
- **Check 1**: Is Device B registered? (check D1 devices table)
- **Check 2**: Does Device B have apns_token in D1?
- **Check 3**: Are APNs credentials correct in Cloudflare?
   ```bash
   npx wrangler secret list --env production
   # Should show: APNS_P8_KEY, APNS_KEY_ID, APNS_TEAM_ID
   ```
- **Check 4**: Relay logs - did it try to send push?
   ```bash
   npx wrangler tail --env production
   # Look for "No APNs tokens found" or "APNs error"
   ```

**Symptom**: Push received but inbox poll fails
- **Cause**: Network issue or E2EE decryption error
- **Check**: Xcode logs for specific error message

**Symptom**: APNs 410 "Token invalid"
- **Cause**: Using sandbox certificate in production (or vice versa)
- **Check**: Verify APNs environment matches deployment:
  - Production app → Production APNs endpoint
  - TestFlight app → Production APNs endpoint
  - Xcode debug build → Sandbox APNs endpoint

---

## Test 3: Verify 30s Polling Disabled (Optional)

**Goal**: Confirm app no longer polls every 30 seconds (waits for push instead)

### Steps:

1. **Open app, authenticated, on Timeline**
2. **Watch Xcode Console for 2 minutes**
3. **No memory sharing** (just idle)

### Expected Behavior:

**BEFORE APNs (old behavior):**
```
📭 Inbox empty  (every 30 seconds)
📭 Inbox empty
📭 Inbox empty
```

**AFTER APNs (new behavior):**
```
(silence - no polling until push received)
```

### Success Criteria:

- ✅ No inbox polls while app is idle
- ✅ Only polls when push notification received
- ✅ Battery usage decreases (check Settings → Battery after 1 hour)

---

## Metrics: Before vs After APNs

| Metric | Before (Polling) | After (Push) | Improvement |
|--------|-----------------|--------------|-------------|
| Requests/day (1 user) | 2,880 (every 30s × 24h) | ~60 (only on share) | **98% reduction** |
| Requests/day (10k users) | 28.8M | ~600k | **98% reduction** |
| Message latency | Up to 30s | 1-3s | **90% faster** |
| Battery drain | High (constant polling) | Low (push-triggered) | **Significant improvement** |
| Relay cost (10k users) | Higher CPU usage | Lower CPU usage | **Cost savings** |

---

## Troubleshooting

### APNs Token Registration Issues

**Problem**: Token never appears in console

**Solutions**:
1. Verify running on **physical device** (not simulator)
2. Check **internet connection** (APNs requires network)
3. Verify **GoogleService-Info.plist** exists in project
4. Check **provisioning profile** has Push Notifications capability
5. Clean build: Xcode → Product → Clean Build Folder

---

### Silent Push Not Received

**Problem**: Share happens but no push notification

**Debug Steps**:

1. **Check relay logs**:
   ```bash
   npx wrangler tail --env production
   ```

   Look for:
   - `"No APNs tokens found for recipients"` → Device not registered or token is NULL
   - `"APNs error 400"` → Invalid payload or JWT
   - `"APNs error 403"` → Invalid certificate or topic
   - `"APNs error 410"` → Invalid token (device uninstalled app)

2. **Verify APNs credentials**:
   ```bash
   npx wrangler secret list --env production
   ```

   All three should exist:
   - APNS_P8_KEY
   - APNS_KEY_ID
   - APNS_TEAM_ID

3. **Check D1 database**:
   ```sql
   SELECT device_id, device_name, apns_token, status
   FROM devices
   WHERE owner_did = 'did:buds:3mVJmCTSNQf1VRQZmwsNHvJLYHaA';
   ```

   Verify:
   - `apns_token` is NOT NULL (64 hex chars)
   - `status = 'active'`

4. **Test APNs directly** (bypassing app):

   Use Apple's Push Notification Console:
   - https://developer.apple.com/notifications/
   - Upload your .p8 key
   - Send test notification to your device token
   - Verify it arrives

---

### Push Arrives But Inbox Poll Fails

**Problem**: Silent push received but message not decrypted

**Check Xcode logs** for specific error:

- `"Sender not in Circle"` → Add sender to Circle first
- `"Sender device not pinned"` → Device keys not synced
- `"CID mismatch"` → Relay tampering or corruption
- `"Signature verification failed"` → Wrong Ed25519 key or corrupted message

---

## Production Readiness Checklist

Before deploying to 10k users:

- [ ] APNs token registration tested on 3+ devices
- [ ] Silent push reception tested end-to-end
- [ ] Verified 30s polling no longer happens
- [ ] Battery usage improved (measured over 24 hours)
- [ ] Relay logs show successful push delivery
- [ ] APNs 410 handling tested (uninstall app, verify device marked inactive)
- [ ] Stress test: 100 concurrent shares → 100 pushes sent
- [ ] Monitoring: Set up alerts for APNs errors in Cloudflare

---

## Current Status

**iOS Implementation**: ✅ 100% Complete (Phase 6)
**Relay Implementation**: ✅ 100% Complete (Phase 6)
**APNs Credentials**: ✅ Configured in Cloudflare Workers
**Testing**: ⏸️  Pending (requires solid WiFi, not airplane Starlink)

**Next Step**: Run Test 1 and Test 2 when off the plane.

**Expected Result**: 95% reduction in wasted requests, 1-3s message latency (vs 30s polling).

🚀 **No code changes needed - just test and verify!**
