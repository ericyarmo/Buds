# Phase 7: Message Inbox + Push Notifications - COMPLETE ✅

**Completion Date:** December 24, 2025
**Implementation Time:** ~4 hours
**Status:** Code complete, ready for Xcode capabilities setup

---

## Summary

Phase 7 successfully implements silent push notifications and inbox polling for real-time Circle memory sharing. The system uses APNs for zero-PII push notifications that trigger immediate inbox polling, combined with background fetch for periodic polling (15-min intervals).

---

## Implementation Completed

### **Cloudflare Worker (Relay Server)**

#### 1. APNs Integration ✅
- **Installed:** `jose` library for JWT generation
- **Created:** Database migration `0002_add_apns_token.sql`
- **Updated:** Device registration endpoint to accept APNs tokens
- **Implemented:** APNs push notification handler:
  - JWT token generation with ES256 (cached 15 min)
  - Silent push payload: `{aps: {content-available: 1}, inbox: 1}`
  - Zero-PII (no sender info in push)
  - Automatic error handling (410 = invalid token cleanup)
  - Sandbox/production endpoint switching

#### 2. Security & Privacy ✅
- **Zero PII in push notifications** - Only generic "inbox has messages" hint
- **TOFU signature verification** - Uses locally-pinned Ed25519 keys from Circle roster
- **Idempotency protection** - Duplicate message filtering via relay message ID
- **Device-based E2EE** - Multi-device key wrapping maintained

**Files Changed:**
- `migrations/0002_add_apns_token.sql` (NEW)
- `src/handlers/devices.ts` (UPDATED)
- `src/handlers/messages.ts` (UPDATED)
- `src/utils/validation.ts` (UPDATED)
- `src/index.ts` (UPDATED)
- `package.json` (UPDATED - added jose)

---

### **iOS App**

#### 1. AppDelegate (BudsApp.swift) ✅
- **APNs registration** on app launch
- **Token upload** to relay server
- **Silent push handler** triggers immediate inbox poll
- **Background fetch** with BGTaskScheduler (15-min intervals)
- **Lifecycle management** for polling start/stop

#### 2. InboxManager ✅
**Location:** `Core/InboxManager.swift` (NEW)

**Features:**
- Foreground polling (30s intervals)
- Background polling via BGTaskScheduler
- Message decryption with TOFU verification
- Automatic database storage
- Idempotency protection
- UI notification on new messages

#### 3. E2EEManager ✅
**Added:** `decryptAndVerifyMessage()` method

**Security:**
- Decrypts AES-GCM encrypted payload
- Verifies Ed25519 signature against pinned key
- Throws error if sender not in Circle
- Prevents relay key-swap attacks

#### 4. CircleManager ✅
**Added:** `getPinnedEd25519PublicKey(for:)` method

**TOFU Key Pinning:**
- Returns locally-cached Ed25519 key from devices table
- Keys stored when member added to Circle (first use)
- Prevents relay from swapping keys in transit
- Critical security feature for E2EE

#### 5. RelayClient ✅
**Updated:**
- `registerDevice()` accepts optional `apnsToken` parameter
- Added `deleteMessage()` for cleanup after processing
- Inbox endpoint already existed from Phase 6

#### 6. DeviceManager ✅
**Added:** `updateAPNsToken()` method

**Features:**
- Stores token in UserDefaults
- Re-registers device with updated token
- Called from AppDelegate on token receipt

#### 7. MemoryRepository ✅
**Added Methods:**
- `isMessageProcessed(relayMessageId:)` - Idempotency check
- `storeSharedReceipt(_:senderDID:relayMessageId:)` - Save decrypted messages

**Updated Queries:**
- LEFT JOIN `received_memories` to fetch sender DID
- Populates `Memory.senderDID` for received memories

#### 8. Database Migration v4 ✅
**Location:** `Core/Database/Database.swift`

**New Table:** `received_memories`
```sql
CREATE TABLE received_memories (
    id TEXT PRIMARY KEY NOT NULL,
    memory_cid TEXT NOT NULL,
    sender_did TEXT NOT NULL,
    header_cid TEXT NOT NULL,
    permissions TEXT NOT NULL,
    shared_at REAL NOT NULL,
    received_at REAL NOT NULL,
    relay_message_id TEXT NOT NULL UNIQUE
);
```

**Indexes:**
- `idx_received_memories_sender` (sender_did)
- `idx_received_memories_received` (received_at DESC)
- `idx_received_memories_relay_msg` (relay_message_id - for idempotency)

#### 9. TimelineView ✅
**Updated:**
- Starts foreground polling on appear
- Stops polling on disappear
- Listens to `NotificationCenter.inboxUpdated` for auto-refresh
- Reloads timeline when new shared memories arrive

#### 10. MemoryCard ✅
**Enhanced:**
- Shows "From [Name]" badge for received memories
- Loads sender's display name from Circle roster
- Different icon (arrow.down.circle.fill) for received vs shared
- Color-coded: Accent blue for received, Green for shared

#### 11. Memory Model ✅
**Added Field:** `senderDID: String?`
- Populated for memories received from Circle members
- `nil` for your own memories
- Used to display sender name in UI

**Files Changed:**
- `App/BudsApp.swift` (UPDATED)
- `Core/InboxManager.swift` (NEW)
- `Core/E2EEManager.swift` (UPDATED)
- `Core/CircleManager.swift` (UPDATED)
- `Core/RelayClient.swift` (UPDATED)
- `Core/DeviceManager.swift` (UPDATED)
- `Core/Database/Repositories/MemoryRepository.swift` (UPDATED)
- `Core/Database/Database.swift` (UPDATED - v4 migration)
- `Core/Models/Memory.swift` (UPDATED)
- `Features/Timeline/TimelineView.swift` (UPDATED)
- `Shared/Views/MemoryCard.swift` (UPDATED)

---

## Architecture Highlights

### Push Notification Flow
```
1. User A shares memory to User B
2. Relay encrypts + stores message in inbox
3. Relay sends silent APNs push to User B's devices
4. User B's device receives push → triggers immediate inbox poll
5. InboxManager fetches encrypted messages from relay
6. E2EEManager decrypts + verifies signature (TOFU)
7. MemoryRepository stores in received_memories table
8. TimelineView auto-refreshes via NotificationCenter
9. MemoryCard displays "From User A" badge
```

### Background Polling Flow
```
1. App backgrounds → schedules BGAppRefreshTask
2. iOS wakes app after ~15 minutes
3. InboxManager polls relay for new messages
4. Process messages → store → notify UI
5. Schedule next background poll
```

### Security Chain
```
1. Relay sends push (zero PII)
2. Device polls inbox
3. Device looks up sender's pinned Ed25519 key (TOFU)
4. Device decrypts with own X25519 private key
5. Device verifies signature with pinned Ed25519 public key
6. Device stores only if signature valid
7. Relay cannot swap keys (TOFU prevents MITM)
```

---

## Key Security Features

### ✅ Implemented

1. **Zero-PII Push Notifications**
   - No sender DID in push payload
   - No message content in push
   - Only generic "inbox has messages" hint

2. **TOFU Key Pinning**
   - Ed25519 keys cached when member added to Circle
   - Prevents relay from swapping signing keys
   - Critical defense against key-swap attacks

3. **Idempotency Protection**
   - Duplicate messages filtered by relay message ID
   - Prevents double-processing on retries

4. **E2EE Maintained**
   - All messages encrypted with AES-256-GCM
   - Per-device X25519 key wrapping
   - Relay cannot decrypt payloads

5. **Signature Verification**
   - Every received message signature checked
   - Invalid signatures rejected
   - Sender must be in Circle roster

---

## Testing Performed

### ✅ Code Complete
- All TypeScript compiles (Worker)
- All Swift compiles (iOS)
- Database migrations validated
- No syntax errors

### ⏳ Pending (After Xcode Setup)
1. APNs token registration test
2. Silent push notification test
3. Inbox polling test (foreground)
4. Background fetch test
5. E2E sharing flow test
6. TOFU verification test

---

## Remaining Setup Steps

### 1. Xcode Capabilities (User Action Required)
**See:** `XCODE_CAPABILITIES_SETUP.md` for detailed instructions

**Quick Summary:**
- Add Background Modes capability
- Enable Background fetch + Remote notifications
- Add BGTaskScheduler identifier to Info.plist

### 2. Apple Developer Portal (User Action Required)
- Create APNs Key (.p8 file)
- Download key (only once!)
- Note Key ID and Team ID

### 3. Cloudflare Worker Secrets (User Action Required)
```bash
cd /Users/ericyarmolinsky/Developer/buds-relay
npx wrangler secret put APNS_P8_KEY      # Paste .p8 content
npx wrangler secret put APNS_KEY_ID      # e.g., ABC123DEFG
npx wrangler secret put APNS_TEAM_ID     # e.g., XYZ9876543
```

### 4. Worker Deployment
```bash
# Apply migration
npx wrangler d1 execute buds-relay-db --file=./migrations/0002_add_apns_token.sql

# Deploy
npx wrangler deploy
```

---

## Performance Considerations

### APNs Rate Limits
- JWT token cached 15 minutes (reduces overhead)
- One push per message (not per recipient device)
- Worker handles APNs 429 gracefully

### Polling Frequency
- **Foreground:** 30 seconds (configurable)
- **Background:** 15 minutes (iOS limit)
- **Silent push:** Immediate (best UX)

### Database Impact
- New table: `received_memories` (~300 bytes per message)
- Indexed for fast sender queries
- Relay message ID unique constraint prevents duplicates

### Network Usage
- Silent push: <100 bytes
- Inbox poll: Variable (depends on message count)
- Background fetch: Limited by iOS (system-managed)

---

## Known Limitations

### iOS Platform Limits
1. Background fetch not guaranteed (iOS discretion)
2. Silent push requires internet connection
3. Simulator doesn't support push notifications
4. Background tasks killed after 30 seconds

### Architectural Trade-offs
1. 15-minute background poll delay (iOS limit)
2. Silent push requires APNs (no alternative)
3. TOFU requires first-time key exchange
4. Relay message retention: 30 days (hardcoded)

---

## Future Enhancements (vNext)

### Potential Improvements
1. **Delivery Receipts** - Let sender know when message opened
2. **Read Receipts** - Optional read status
3. **Message Expiration** - Configurable TTL per message
4. **Priority Push** - Urgent vs normal delivery
5. **Retry Logic** - Exponential backoff for failed polls
6. **Offline Queue** - Store messages for offline viewing

### Not Implemented (Out of Scope)
- User-facing push notification banners (silent only)
- Message preview in lock screen
- Push notification settings UI
- Per-message notification control

---

## Documentation Updates

### New Files Created
- ✅ `XCODE_CAPABILITIES_SETUP.md` - Detailed setup instructions
- ✅ `PHASE_7_COMPLETE.md` - This completion summary
- ✅ `migrations/0002_add_apns_token.sql` - Worker migration

### Updated Files
- ✅ `PHASE_7_PLAN.md` - Reference implementation plan
- ✅ `README.md` - (Should update with Phase 7 status)

---

## Deployment Checklist

### Pre-Deployment
- [ ] Read `XCODE_CAPABILITIES_SETUP.md`
- [ ] Add Background Modes to Xcode target
- [ ] Add BGTaskScheduler identifier to Info.plist
- [ ] Create APNs Key in Apple Developer Portal
- [ ] Download .p8 file and save securely
- [ ] Note Key ID and Team ID

### Worker Deployment
- [ ] Add APNs secrets to Cloudflare
- [ ] Run database migration (0002_add_apns_token.sql)
- [ ] Deploy worker with `npx wrangler deploy`
- [ ] Verify deployment logs (no errors)

### Testing
- [ ] Launch app on physical device
- [ ] Verify APNs token logged
- [ ] Verify token uploaded to relay
- [ ] Test foreground inbox polling
- [ ] Test background fetch (wait 15+ min)
- [ ] Test E2E share flow with silent push

---

## Success Criteria

### ✅ Code Complete
All code implemented and compiling successfully.

### ⏳ Testing Phase
After Xcode setup, verify:
1. APNs token registration works
2. Silent push triggers immediate poll
3. Background fetch polls every 15 min
4. Shared memories appear with "From [Name]" badge
5. TOFU signature verification works
6. No duplicate messages stored

---

## Support & Troubleshooting

### Common Issues

**APNs token not received:**
- Ensure running on physical device (not simulator)
- Check Push Notifications capability enabled
- Verify Apple Developer account has APNs entitlements

**Silent push not working:**
- Verify Worker has APNs secrets configured
- Check Worker logs for APNs errors (410, 429)
- Ensure device has internet connection

**Background fetch not running:**
- iOS controls timing (not guaranteed)
- Test with real backgrounding (not force quit)
- Check console for "Background poll scheduled" log

---

**Phase 7 Status: CODE COMPLETE ✅**

**Next Steps:** Follow `XCODE_CAPABILITIES_SETUP.md` to enable capabilities and test the implementation.

**Estimated Setup Time:** 15-20 minutes (Xcode + Apple Developer Portal + Worker deployment)
