# Phase 10.3: Distributed Systems Edge Case Audit

**Auditor:** Senior Systems Engineer perspective (Snapchat, Google Maps, MMORPGs, Crypto)
**Date:** December 30, 2025
**Status:** 🔴 CRITICAL ISSUES FOUND

---

## Severity Classification

- 🔴 **CRITICAL** - Data loss, security breach, broken core functionality
- 🟡 **HIGH** - Poor UX, confusing states, requires manual recovery
- 🟢 **MEDIUM** - Edge case that happens rarely, has workaround
- ⚪ **LOW** - Theoretical edge case, unlikely in practice

---

## Category 1: Ordering & Causality

### 🔴 CRITICAL: Receipt Reordering (Network)

**Scenario:**
```
Owner creates jar → sends 4 receipts:
  1. jar.created (jar_id: "abc")
  2. jar.member_added (Alice)
  3. jar.member_added (Bob)
  4. jar.member_added (Charlie)

Network reorders, recipient receives:
  2. jar.member_added (Alice) ← Can't process, jar doesn't exist yet
  1. jar.created (jar_id: "abc")
  3. jar.member_added (Bob)
  4. jar.member_added (Charlie)
```

**Impact:** Member additions fail silently, jar state is incomplete

**Current Plan:** ❌ No dependency resolution, assumes in-order delivery

**Fix Required:**
- Add `parent_cid` to jar receipts (creates causal chain)
- Queue receipts with unsatisfied dependencies
- Process in topological order once all deps arrive
- Request missing receipts from relay if gap detected

---

### 🔴 CRITICAL: Concurrent Jar Operations (Split Brain)

**Scenario:**
```
Device A (owner) offline:
  - Renames jar "Friends" → "Homies" (timestamp: 10:00:00)

Device B (owner via multi-device) offline:
  - Renames jar "Friends" → "Squad" (timestamp: 10:00:05)

Both come online, broadcast receipts
```

**Impact:** Which name wins? Last-write-wins based on timestamp is fragile (clock skew)

**Current Plan:** 🟡 Last-write-wins by timestamp (vulnerable to clock skew)

**Fix Required:**
- Use Lamport clocks or vector clocks for ordering
- Or: Owner's device_id as tiebreaker (deterministic)
- Or: First-to-relay wins (relay assigns sequence number)
- Document conflict resolution strategy explicitly

---

### 🟡 HIGH: Missing Receipt Detection

**Scenario:**
```
Owner performs sequence:
  1. jar.created
  2. jar.member_added (Alice)
  3. jar.member_added (Bob)
  4. jar.updated (rename to "Squad")
  10 more operations...
  15. jar.member_added (Charlie)

Charlie receives receipts: [1, 2, 4, 15]
Missing: [3, 5-14]
```

**Impact:** Charlie has partial jar state, doesn't know Bob exists

**Current Plan:** ❌ No gap detection, assumes all receipts arrive

**Fix Required:**
- Add sequence numbers to jar receipts (per jar, monotonic)
- Detect gaps in sequence
- Request backfill from relay: `GET /api/jars/{jar_id}/receipts?from=3&to=14`
- Show UI: "Syncing jar..." during backfill

---

### 🟡 HIGH: Clock Skew (Timestamp-based Ordering)

**Scenario:**
```
Device A clock: 2025-12-30 10:00 (correct)
Device B clock: 2025-12-31 10:00 (1 day ahead - iOS bug, timezone change, etc.)

Device A renames jar at 10:00
Device B renames jar at 10:00 (but timestamp claims 12/31)

Last-write-wins thinks B's update is "newer" even though A happened after
```

**Impact:** Stale updates overwrite fresh updates

**Current Plan:** 🟡 Last-write-wins by timestamp

**Fix Required:**
- Use relay-assigned sequence numbers (server clock is source of truth)
- Or: Hybrid timestamp (local time + relay receive time)
- Or: Lamport clocks (logical timestamps)

---

## Category 2: Membership & Permissions

### 🔴 CRITICAL: Removed Member Sends Receipts

**Scenario:**
```
10:00 - Owner removes Bob from jar
10:01 - Bob (offline, doesn't know yet) shares bud to jar
10:02 - Bob comes online, sends encrypted bud receipt to all members
```

**Impact:** Removed member can spam jar, security issue

**Current Plan:** ⚪ Mentioned relay-side validation but not specified

**Fix Required:**
- **Server-side:** Relay validates sender is active member before forwarding
  ```typescript
  // Cloudflare Worker
  const isMember = await db.query(`
    SELECT 1 FROM jar_members
    WHERE jar_id = ? AND member_did = ? AND status = 'active'
  `, [jar_id, sender_did]);

  if (!isMember) {
    return Response.json({ error: "Not a member" }, { status: 403 });
  }
  ```
- **Client-side:** Verify sender DID is in local jar_members (defense in depth)
- **Relay-side:** Store jar membership state (authoritative)

---

### 🔴 CRITICAL: Concurrent Membership Changes

**Scenario:**
```
Owner adds Alice (timestamp 10:00:00)
Owner removes Alice (timestamp 10:00:10)

Network reorders, member receives:
  1. jar.member_removed (Alice)  ← Alice not in jar yet, no-op
  2. jar.member_added (Alice)    ← Alice added AFTER removal

Final state: Alice is active member (wrong!)
```

**Impact:** Removed members can rejoin by network reordering

**Current Plan:** ❌ No handling for out-of-order membership changes

**Fix Required:**
- Membership operations reference parent_cid (causal chain)
- Process in dependency order
- Or: Membership has monotonic version number per member
  - `member_added(alice, version: 1)`
  - `member_removed(alice, version: 2)`
  - Ignore operations with version <= current

---

### 🟡 HIGH: Partial Member List (Incomplete State)

**Scenario:**
```
Owner creates jar with 12 members
Sends 12 jar.member_added receipts
New member receives 11/12 (one dropped)

New member shares bud, encrypts for 11 members
12th member can't decrypt
```

**Impact:** Some members can't see shared buds

**Current Plan:** 🟡 Mentioned but no detection/recovery

**Fix Required:**
- Jar receipts include total member count
- Client detects mismatch: "Expected 12 members, have 11"
- Request full member list from relay: `GET /api/jars/{jar_id}/members`
- Show UI: "Syncing jar members..."

---

### 🟡 HIGH: Byzantine Owner (Malicious/Buggy)

**Scenario:**
```
Owner sends conflicting receipts:
  - jar.created(jar_id: "abc", name: "Friends")
  - jar.created(jar_id: "abc", name: "Enemies")  ← Same jar_id, different name
```

**Impact:** Recipient jar state is corrupted

**Current Plan:** ❌ Assumes owner is honest

**Fix Required:**
- First jar.created receipt for a jar_id is canonical (immutable)
- Subsequent jar.created with same jar_id are rejected
- Relay enforces: only owner can create jar.created for a jar_id
- Relay checks: jar_id hasn't been created yet

---

## Category 3: Offline Behavior

### 🔴 CRITICAL: Offline Operation Queue Explosion

**Scenario:**
```
User goes offline for 7 days
App is open, user performs 1000 jar operations:
  - Rename jar 500 times (testing, bug, etc.)
  - Add/remove members 500 times

Comes online, tries to send 1000 receipts
```

**Impact:** Relay flooded, client sends stale operations, confusion

**Current Plan:** ⚪ Mentioned "queue operations in outbox" but no bounds

**Fix Required:**
- Offline operation queue has max size (100 operations)
- Older operations dropped or merged (e.g., 500 renames → just final rename)
- Bounded offline window: >7 days = require full resync, discard queue
- Show UI: "You were offline for 7 days, syncing latest state..."

---

### 🟡 HIGH: Offline Conflict Detection

**Scenario:**
```
User offline, performs operations:
  - Rename jar "Friends" → "Homies"
  - Add member Alice
  - Share 10 buds

Comes online, syncs inbox first
Receives from other members:
  - Jar renamed to "Squad" (conflicts with "Homies")
  - Alice already added by someone else
  - Jar was deleted

Which operations are still valid?
```

**Impact:** User's offline work is invalidated, confusing UX

**Current Plan:** ❌ No offline conflict detection

**Fix Required:**
- Before sending queued operations, sync inbox first
- Check each queued operation is still valid:
  - Jar still exists? (not deleted)
  - User still a member? (not removed)
  - Operation conflicts with synced state?
- Show UI: "Jar was deleted while offline, discarding 13 pending changes"
- Or: Ask user: "Jar was renamed to Squad. Apply your rename to Homies?"

---

### 🟡 HIGH: Stale Member List (Offline Sharing)

**Scenario:**
```
10:00 - User sees jar with members [Alice, Bob, Charlie]
10:05 - Goes offline
11:00 - Owner removes Charlie (user doesn't know)
11:05 - User shares bud to jar, encrypts for [Alice, Bob, Charlie]
12:00 - Comes online, sends receipt
```

**Impact:** Removed member receives encrypted bud (privacy leak?)

**Current Plan:** 🟡 Relay-side validation mentioned but not clear if it blocks

**Fix Required:**
- Relay validates recipient list against current membership
- If removed member in recipient list: relay filters them out before forwarding
- User's receipt still sent to relay with all 3, relay only forwards to Alice & Bob
- Or: Reject entire operation, show user error: "Charlie was removed, retry"

---

## Category 4: Deletion & Tombstones

### 🔴 CRITICAL: Deleted Jar Resurrection

**Scenario:**
```
10:00 - Owner deletes jar, sends jar.deleted
10:05 - Network delayed jar.member_added arrives (sent at 9:59)

Recipient processes:
  1. jar.deleted → jar removed
  2. jar.member_added → jar re-created (wrong!)
```

**Impact:** Deleted jars can be resurrected by delayed receipts

**Current Plan:** ❌ No tombstone tracking

**Fix Required:**
- When jar deleted, create tombstone entry
  ```sql
  CREATE TABLE jar_tombstones (
    jar_id TEXT PRIMARY KEY,
    deleted_at REAL NOT NULL,
    deleted_by_did TEXT NOT NULL
  );
  ```
- All jar operations check tombstone first
- If tombstone exists: reject operation, log warning
- Tombstones persist indefinitely (or until relay confirms no more pending receipts)

---

### 🟡 HIGH: Bud Belongs to Deleted Jar

**Scenario:**
```
User receives bud receipt with jar_id "abc"
Jar "abc" was deleted 1 hour ago
```

**Impact:** Bud arrives for non-existent jar

**Current Plan:** 🟡 Fall back to Solo (mentioned)

**Fix Required:**
- Check jar_tombstones before falling back to Solo
- If tombstone exists: Show toast "Received bud for deleted jar [name], moved to Solo"
- Store bud with metadata: `original_jar_id`, `original_jar_name`
- User can see "This bud was shared to [deleted jar name]"

---

### 🟡 HIGH: Member Leaves, Jar Still Sending Receipts

**Scenario:**
```
Alice leaves jar at 10:00
Owner (offline) shares bud at 10:05
Owner comes online at 11:00, sends bud receipt to Alice
```

**Impact:** Alice receives buds for jar she left

**Current Plan:** 🟡 Relay validates membership (mentioned)

**Fix Required:**
- Relay checks recipient is active member before forwarding
- If recipient left: don't forward receipt
- Owner doesn't know Alice left (offline), but relay filters
- When owner syncs inbox, gets jar.member_left receipt, updates local state

---

## Category 5: Data Integrity

### 🔴 CRITICAL: Receipt Replay Attack

**Scenario:**
```
Attacker captures jar.member_added receipt
Replays it 100 times
```

**Impact:** Duplicate member entries, database bloat

**Current Plan:** ⚪ Mentioned "idempotent processing" but not enforced

**Fix Required:**
- Track processed receipt CIDs in database
  ```sql
  CREATE TABLE processed_receipts (
    receipt_cid TEXT PRIMARY KEY,
    processed_at REAL NOT NULL
  );
  ```
- Before processing receipt: check if CID already processed
- If processed: skip, log warning
- Cleanup old entries (>30 days) to prevent bloat

---

### 🔴 CRITICAL: CID Collision (Birthday Attack)

**Scenario:**
```
Two different jar.created receipts produce same CID (hash collision)
```

**Impact:** Second jar overwrites first jar

**Current Plan:** ⚪ Assumes CID collisions impossible

**Fix Required:**
- CIDv1 uses SHA-256: collision probability is 2^-256 (effectively zero)
- Defense in depth: If CID exists, compare full receipt CBOR
- If CBOR differs: reject as collision (or hash collision attack)
- Log critical error, notify user

---

### 🟡 HIGH: Signature Verification Bypass

**Scenario:**
```
Attacker MITMs relay, modifies jar.created receipt
Changes jar name from "Friends" to "Pwned"
Forwards to victim
```

**Impact:** Victim processes forged receipt

**Current Plan:** ✅ Ed25519 signature verification (existing)

**Fix Required:**
- Already mitigated by existing signature verification
- But: Ensure signature verification happens BEFORE any state changes
- Ensure verified DID matches expected sender (owner or member)

---

### 🟡 HIGH: Incomplete Receipt (Truncated CBOR)

**Scenario:**
```
Network truncates receipt CBOR mid-transmission
Incomplete payload arrives
```

**Impact:** CBOR decode fails, receipt lost

**Current Plan:** 🟡 Decode errors logged but receipt lost

**Fix Required:**
- Relay includes receipt byte length in metadata
- Client verifies length before decoding
- If mismatch: request re-transmission from relay
- Show UI: "Syncing jar... (retry 1/3)"

---

## Category 6: Scalability & Performance

### 🟡 HIGH: Large Member List (12 members * 5 devices = 60 encryptions)

**Scenario:**
```
Jar has 12 members, each has 5 devices
Share bud = encrypt 60 times
```

**Impact:** Share operation takes 5-10 seconds, blocks UI

**Current Plan:** ⚪ Mentioned multi-device but not performance

**Fix Required:**
- Encrypt bud once with random symmetric key
- Encrypt symmetric key 60 times (fast, just 32 bytes)
- **Already implemented in E2EEManager** (hybrid encryption)
- Ensure UI shows progress: "Encrypting for 60 devices..."
- Background thread for encryption (don't block main thread)

---

### 🟡 HIGH: Receipt Storm (100 buds shared at once)

**Scenario:**
```
User imports 100 buds from photos
Shares all to jar at once
100 receipts sent to relay simultaneously
```

**Impact:** Relay rate limit, some receipts dropped

**Current Plan:** ❌ No rate limiting or batching

**Fix Required:**
- Client-side rate limit: max 10 receipts/second
- Batch receipts if possible (future: single "bulk share" receipt)
- Show progress UI: "Sharing 100 buds... (42/100)"
- Retry failed sends with exponential backoff

---

### 🟢 MEDIUM: Large Jar History (1000+ operations)

**Scenario:**
```
Jar exists for 1 year
1000+ jar receipts (renames, member changes, etc.)
New member joins, needs full sync
```

**Impact:** Slow initial sync, large database

**Current Plan:** ❌ No compaction or snapshots

**Fix Required (Future):**
- Jar state snapshots (every 100 operations)
- New member downloads snapshot + recent receipts (not all 1000)
- Snapshot is signed by owner, includes full state
- For V1: Accept slow sync, optimize in Phase 11

---

### 🟢 MEDIUM: Inbox Backlog (Offline for 7 days = 1000s of receipts)

**Scenario:**
```
User offline for 7 days
Active jar with 10 members sharing frequently
1000+ bud receipts + 100+ jar receipts pending
```

**Impact:** First poll after returning online is huge, takes minutes

**Current Plan:** ⚪ Polling fetches all, no pagination

**Fix Required:**
- Relay paginates inbox: `GET /api/inbox?limit=50&offset=0`
- Client processes in batches
- Show progress: "Syncing inbox... (512/1043 messages)"
- Process high-priority first (jar operations before buds)

---

## Category 7: User Experience

### 🟡 HIGH: No Visual Indication of Sync State

**Scenario:**
```
User shares bud to jar
Receipt sent to relay
Waiting for members to receive and process
User has no idea if it worked
```

**Impact:** User doesn't know if share succeeded

**Current Plan:** ⚪ Toast on send, but no delivery confirmation

**Fix Required:**
- Add sync status to jar card:
  - "Syncing..." (receipts pending)
  - "Up to date" (all synced)
  - "Sync failed" (retry needed)
- Add delivery receipts (future):
  - Member sends jar.receipt_ack when processed
  - Sender sees "Seen by 3/5 members"

---

### 🟡 HIGH: Confusing Pending Invite State

**Scenario:**
```
User receives jar invite
Doesn't accept or decline (forgot, distracted)
Jar sits in "Pending Invites" forever
Owner thinks they joined
```

**Impact:** Confused ownership, partial membership

**Current Plan:** 🟡 Pending invites show in UI

**Fix Required:**
- Invites expire after 7 days (auto-decline)
- Owner gets notification: "Alice didn't respond to Friends jar invite"
- User gets reminder after 24 hours: "You have pending jar invites"
- Expired invites automatically declined (tombstone created)

---

### 🟢 MEDIUM: No "Undo" for Destructive Operations

**Scenario:**
```
User accidentally deletes jar
All members lose access immediately
No way to recover
```

**Impact:** Data loss, user frustration

**Current Plan:** ❌ Deletes are permanent

**Fix Required (Future):**
- Soft delete with 30-day retention
- Owner can undelete within 30 days
- Members see "Jar archived" instead of deleted
- After 30 days: hard delete with tombstone

---

## Recommendations by Priority

### 🔴 CRITICAL (Must Fix for Phase 10.3)

1. **Causal Ordering**
   - Add `parent_cid` to all jar receipts
   - Queue receipts until dependencies satisfied
   - Process in topological order

2. **Server-Side Membership Validation**
   - Relay enforces member permission checks
   - Reject receipts from non-members
   - Validate before forwarding

3. **Tombstone Tracking**
   - Track deleted jars in `jar_tombstones` table
   - Prevent resurrection by delayed receipts
   - Check tombstones before processing any jar operation

4. **Receipt Replay Protection**
   - Track processed receipt CIDs
   - Skip already-processed receipts
   - Idempotent processing guaranteed

5. **Sequence Numbers**
   - Add monotonic sequence number to jar receipts
   - Detect gaps in sequence
   - Request backfill from relay

### 🟡 HIGH (Should Fix for Production)

6. **Offline Conflict Detection**
   - Sync inbox before sending queued operations
   - Validate queued operations still valid
   - Show user which operations were discarded

7. **Missing Receipt Detection**
   - Detect sequence gaps
   - Request backfill automatically
   - Show "Syncing..." UI during backfill

8. **Bounded Offline Window**
   - Max 7 days offline, then require resync
   - Discard stale queued operations
   - Clear UX: "Offline for 7 days, syncing..."

9. **Partial Member List Recovery**
   - Detect member count mismatch
   - Request full member list from relay
   - Auto-recover incomplete state

### 🟢 MEDIUM (Nice to Have)

10. **Invite Expiration** (7 days)
11. **Rate Limiting** (10 receipts/sec)
12. **Inbox Pagination** (50 receipts/batch)
13. **Sync Status UI** ("Syncing...", "Up to date")

### ⚪ LOW (Future Phases)

14. **Delivery Receipts** ("Seen by 3/5")
15. **Jar Snapshots** (compaction)
16. **Soft Delete** (30-day retention)
17. **Undo** for destructive operations

---

## Updated Architecture Requirements

### Receipt Structure (Updated)

All jar receipts now include:
```swift
struct JarReceiptCommon: Codable {
    let jarID: String              // Which jar
    let sequenceNumber: Int        // Monotonic per jar
    let parentCID: String?         // Causal dependency
    let timestamp: Int64           // Local time (for UX, not ordering)
}
```

### Relay API (New Endpoints)

```
GET  /api/jars/{jar_id}/receipts?from={seq}&to={seq}  // Backfill missing receipts
GET  /api/jars/{jar_id}/members                        // Full member list
GET  /api/inbox?limit=50&offset=0                      // Paginated inbox
POST /api/jars/{jar_id}/validate                       // Check membership
```

### Database Tables (Updated)

```sql
-- Track processed receipts (idempotency)
CREATE TABLE processed_receipts (
    receipt_cid TEXT PRIMARY KEY,
    processed_at REAL NOT NULL,
    receipt_type TEXT NOT NULL
);
CREATE INDEX idx_processed_receipts_time ON processed_receipts(processed_at);

-- Track deleted jars (tombstones)
CREATE TABLE jar_tombstones (
    jar_id TEXT PRIMARY KEY,
    deleted_at REAL NOT NULL,
    deleted_by_did TEXT NOT NULL,
    jar_name TEXT  -- For UX ("Bud for deleted Friends jar")
);

-- Queue receipts with missing dependencies
CREATE TABLE receipt_queue (
    id TEXT PRIMARY KEY,
    receipt_cid TEXT NOT NULL,
    parent_cid TEXT,              -- Waiting for this
    receipt_data BLOB NOT NULL,   -- Encrypted receipt
    queued_at REAL NOT NULL
);
CREATE INDEX idx_receipt_queue_parent ON receipt_queue(parent_cid);
```

---

## Testing Checklist (Updated)

### Ordering Tests
- [ ] Out-of-order receipts queued and processed in order
- [ ] Missing receipt detected, backfill requested
- [ ] Concurrent operations resolved deterministically

### Membership Tests
- [ ] Removed member can't send receipts (relay blocks)
- [ ] Offline member operations validated on reconnect
- [ ] Partial member list recovered automatically

### Deletion Tests
- [ ] Deleted jar creates tombstone
- [ ] Late receipts for deleted jar rejected
- [ ] Bud for deleted jar lands in Solo with metadata

### Offline Tests
- [ ] Offline >7 days triggers full resync
- [ ] Queued operations validated before sending
- [ ] Conflicts shown to user with clear UX

### Edge Cases
- [ ] Receipt replay detected and skipped
- [ ] Clock skew doesn't break ordering
- [ ] Byzantine receipts rejected
- [ ] Incomplete receipts re-requested

---

## Conclusion

**Current plan is 60% there** but missing critical distributed systems hardening:

**Missing:**
- ❌ Causal ordering (parent_cid, dependency resolution)
- ❌ Sequence numbers (gap detection)
- ❌ Tombstones (deletion safety)
- ❌ Replay protection (processed receipt tracking)
- ❌ Offline conflict detection
- ❌ Server-side validation details

**Next Steps:**
1. Update Phase 10.3 plan with these hardening measures
2. Implement in order: tombstones → sequencing → causal ordering → validation
3. Focus on CRITICAL issues first, defer MEDIUM/LOW to Phase 11

**Estimated time with hardening:** 24-32 hours (not 18-24)

Ready to update the plan? 🔒
