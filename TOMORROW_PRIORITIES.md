# Top 3 Priorities for Tomorrow Morning

**Date**: December 25, 2025 (Completed)
**Current Status**: All 3 priorities complete ✅

---

## 🔴 Priority 1: Test E2EE with R2 Storage (30 minutes)

**Why Critical**: Verify R2 migration works end-to-end in production

**Tasks:**
1. Share a new memory from iPhone (should upload to R2)
2. Check Cloudflare Dashboard → R2 → `buds-messages-prod` bucket
   - Verify object exists: `messages/{uuid}.bin`
   - Check metadata: `messageId`, `receiptCid`, `senderDid`
3. Receive the memory on another device (or same device via Circle)
4. Check Xcode logs for successful decryption/verification:
   ```
   ✅ [INBOX] Message decrypted and verified
   ✅ [INBOX] CID verified - content matches claimed CID
   ✅ [INBOX] Signature verified - message is authentic
   ```

**Success Criteria:**
- R2 object created in production bucket
- Message decrypts successfully
- All 4 verification steps pass (decrypt → CID → signature → store)

**If Issues:**
- Check relay logs: `cd /Users/ericyarmolinsky/Developer/buds-relay && npx wrangler tail --env production`
- Verify R2 bucket permissions
- Check iOS logs for decryption errors

---

## 🟡 Priority 2: Enable APNs Push Notifications (2 hours)

**Why Important**: Replace 30s polling → 95% reduction in wasted requests, better battery life

**From SCALE_ANALYSIS.md Phase 2:**
- Current: 9.6M requests/day (95% return empty)
- After: 480k requests/day (push-triggered inbox fetch)
- Impact: Battery savings, reduced relay costs

**Tasks:**
1. **iOS App Updates:**
   - Register APNs token on app launch (after Firebase auth)
   - Send token to relay via `/api/devices/register` (already supports `apns_token` field!)
   - Add notification handler in AppDelegate/BudsApp
   - Trigger inbox poll when silent push received

2. **Relay Already Ready!**
   - ✅ APNs push code already implemented in `src/handlers/messages.ts:298-384`
   - ✅ Sends silent push to all recipient devices when message sent
   - ✅ Handles invalid tokens (marks device inactive)

3. **Configuration Needed:**
   - Get APNs .p8 key from Apple Developer Portal
   - Get Key ID and Team ID
   - Add to Cloudflare Workers secrets:
     ```bash
     npx wrangler secret put APNS_P8_KEY --env production
     npx wrangler secret put APNS_KEY_ID --env production
     npx wrangler secret put APNS_TEAM_ID --env production
     ```

4. **Testing:**
   - Share memory from iPhone A
   - iPhone B should receive silent push
   - iPhone B fetches inbox immediately (no 30s delay)
   - Verify in logs: "Push notification sent successfully"

**Success Criteria:**
- APNs token registered on app launch
- Silent push received within 2 seconds of message send
- Inbox fetched immediately (not polling)
- Battery usage decreases (no more 30s polling)

**Files to Update:**
- `Buds/App/BudsApp.swift` - Add APNs registration + notification handler
- `Buds/Core/DeviceManager.swift` - Send APNs token to relay
- `Buds/Core/InboxManager.swift` - Add push-triggered poll method

---

## 🟢 Priority 3: Tiered Photo Storage Planning (1 hour)

**Why Important**: Prevents 19GB/year iPhone storage bloat for heavy users

**From SCALE_ANALYSIS.md:**
- Problem: 120 memories/day × 3 photos × 150KB = 19GB/year
- Solution: Hot tier (30 days local) + Cold tier (iCloud)

**Tasks (Planning Phase - No Code Yet):**
1. **Architecture Design:**
   - Add `storage_tier` column: 'hot' (local) or 'cold' (iCloud)
   - Add `icloud_url` column for cold-tier photos
   - Migration strategy: Mark photos >30 days as 'cold', upload to iCloud

2. **iCloud Integration Research:**
   - Review CloudKit API for photo storage
   - Estimate costs: iCloud storage pricing for 10k users
   - Design lazy-loading UI (placeholder → download on demand)

3. **User Settings:**
   - Add "Keep photos for [30/90/365] days" setting
   - Add "Storage usage" display in Profile
   - Add "Clear old photos" button (manual cleanup)

4. **Database Migration Design:**
   ```sql
   -- Migration 0005: Tiered photo storage
   ALTER TABLE memories ADD COLUMN storage_tier TEXT DEFAULT 'hot';
   ALTER TABLE memories ADD COLUMN icloud_url TEXT;
   CREATE INDEX idx_memories_storage_tier ON memories(storage_tier);
   ```

**Output:**
- Create `TIERED_STORAGE_PLAN.md` with:
  - Architecture diagram
  - Migration steps
  - iCloud integration details
  - Estimated implementation time (4 hours from SCALE_ANALYSIS.md)

**Success Criteria:**
- Complete plan documented
- iCloud API researched
- Database migration designed
- Ready to implement next week

---

## Summary

**Time Estimate:**
- Priority 1: 30 minutes
- Priority 2: 2 hours
- Priority 3: 1 hour
- **Total: 3.5 hours**

**Actual Outcome (December 25, 2025):**
- ✅ Priority 1: R2 migration verified working in production (337 byte objects in buds-messages-prod)
- ✅ Priority 2: APNs implementation discovered complete (Phase 6), testing guide created
- ✅ Priority 3: Tiered storage plan documented (TIERED_STORAGE_PLAN.md, 4.5 hour implementation)

**After These 3:**
- Continue with Map View (Phase 8 from original plan)
- Or implement tiered storage if APNs finishes quickly

---

**Notes:**
- Phase 7 E2EE + R2 migration complete ✅
- Production relay at https://buds-relay.getstreams.workers.dev
- All infrastructure ready for 10k users, 100k messages/day
- Focus on performance optimizations (APNs, tiered storage) before adding new features
