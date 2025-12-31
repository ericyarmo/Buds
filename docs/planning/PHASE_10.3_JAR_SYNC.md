# Phase 10.3: Jar Sync & Bud Multiplayer

**Status:** 📋 Planning
**Priority:** 🔴 CRITICAL - Blocks real multiplayer
**Estimated Time:** 18-24 hours
**Date:** December 30, 2025

---

## Executive Summary

**Problem:** Jars are currently local-only organizing buckets. When you create a jar and add members, they don't see it on their device. Shared buds land in the wrong jar (or Solo) with no notification. **Buds isn't actually multiplayer yet.**

**Solution:** Convert jars to synchronized group chats using the receipt system. Jar creation, member additions, and bud sharing all propagate via E2EE receipts through the relay.

**User Experience:**
- Create jar "Friends" → Send invites to members
- Members see notification → Accept invite → Jar appears on their shelf
- Share bud to "Friends" → All members see it in the right jar within 30s
- Toast notifications, unread badges, proper group chat UX

---

## Current Broken Flow

### What Happens Now

**Device A (You):**
1. Create jar "Friends" ✅ (stored locally only)
2. Add cofounder as member ✅ (stored in YOUR jar_members table)
3. Share a bud ✅ (encrypted, sent via relay)

**Device B (Cofounder):**
1. Receives encrypted bud ✅
2. Code looks for jars where YOU are a member on HIS device ❌
3. He's never added you to any jar ❌
4. Falls back to Solo ❌
5. Bud silently appears in Solo with no context ❌
6. He has no idea what jar you sent it from ❌

### Why It's Broken

**Jars are not synchronized:**
- Jar creation is local-only
- Member additions don't notify members
- No jar invites or acceptance flow
- Shared buds don't carry jar context
- No notifications when buds arrive

**Database mismatch:**
- Your `jars` table has "Friends" jar
- Your `jar_members` table has cofounder as member
- Cofounder's `jars` table has no "Friends" jar
- Cofounder's `jar_members` table doesn't know you exist
- Receipt lands in limbo, falls back to Solo

---

## Target Architecture: Group Chat Model

### Core Principle

**Jars = Group Chats**
Like WhatsApp groups, Snapchat groups, Signal groups, etc.

**Key Properties:**
1. **Shared existence** - When jar is created, all members see it
2. **Synchronized state** - Name changes, member adds/removes sync to everyone
3. **Proper bud routing** - Buds land in the correct jar, always
4. **Real-time notifications** - Toast, badges, push on new activity
5. **Invite-based membership** - Can't be added without accepting

### How It Should Work

**Jar Creation + Invite Flow:**

```
Device A (Owner):
1. Create jar "Friends"
   → Generate jar.created receipt (jar_id, name, owner_did)
   → Store locally

2. Add member (phone number)
   → Lookup DID from relay
   → Get member devices
   → Generate jar.member_added receipt
   → Encrypt jar.created + member_added receipts
   → Send to all member devices via relay

Device B (Invitee):
1. InboxManager polls, receives encrypted receipts
2. Decrypts jar.created receipt
   → Stores jar in local `jars` table (status: pending_invite)
3. Decrypts jar.member_added receipt
   → Stores in `jar_members` (status: pending)
4. Shows notification: "Eric invited you to Friends jar"
5. User taps "Accept"
   → Updates jar status: pending_invite → active
   → Updates member status: pending → active
   → Generates jar.invite_accepted receipt
   → Sends back to owner + all other members
6. Jar appears on shelf ✅
```

**Bud Sharing Flow:**

```
Device A (Sender):
1. Create bud "Blue Dream" in jar "Friends"
2. Tap "Share with Circle"
3. Select members (or all)
4. Generate session.created receipt
   → payload includes jar_id: "friends-uuid-123"
5. Encrypt + send via relay

Device B (Recipient):
1. InboxManager polls, receives encrypted bud receipt
2. Decrypts, extracts jar_id from payload
3. Looks up jar_id in local `jars` table
   → Found: jar "Friends" (status: active) ✅
4. Stores bud in local_receipts with jar_id
5. Posts .inboxUpdated notification
6. JarDetailView reloads → Bud appears ✅
7. Toast: "Eric shared Blue Dream to Friends 🌿"
8. Badge on jar card: "+1 new bud"
```

---

## New Receipt Types

### 1. Jar Created (`app.buds.jar.created/v1`)

**Purpose:** Announce jar creation to invited members

**Payload:**
```swift
struct JarCreatedPayload: Codable {
    let jarID: String              // UUID (e.g., "friends-uuid-123")
    let jarName: String            // "Friends"
    let jarDescription: String?    // Optional description
    let ownerDID: String           // Creator's DID
    let createdAtMs: Int64         // Timestamp
    let jarColor: String?          // Optional hex color (future)
    let jarIcon: String?           // Optional emoji (future)
}
```

**When generated:**
- Owner creates jar locally
- Owner adds first member (sends to that member)
- Owner adds subsequent members (sends to each new member)

**When received:**
- Creates jar in local `jars` table (status: pending_invite)
- Shows invite notification to user

### 2. Jar Member Added (`app.buds.jar.member_added/v1`)

**Purpose:** Notify all jar members when someone is added

**Payload:**
```swift
struct JarMemberAddedPayload: Codable {
    let jarID: String              // Which jar
    let memberDID: String          // New member's DID
    let displayName: String        // Member's display name
    let phoneNumber: String        // Member's phone (for UI)
    let invitedByDID: String       // Who sent the invite
    let addedAtMs: Int64           // Timestamp
}
```

**When generated:**
- Owner adds member to jar
- Sent to: (1) new member, (2) all existing active members

**When received:**
- If you're the new member: store invite (status: pending)
- If you're existing member: update jar members list

### 3. Jar Invite Accepted (`app.buds.jar.invite_accepted/v1`)

**Purpose:** Notify owner + members that someone accepted invite

**Payload:**
```swift
struct JarInviteAcceptedPayload: Codable {
    let jarID: String              // Which jar
    let memberDID: String          // Who accepted
    let acceptedAtMs: Int64        // Timestamp
}
```

**When generated:**
- Member taps "Accept" on jar invite

**When received:**
- Updates member status from pending → active
- Shows toast: "[Name] joined Friends jar"

### 4. Jar Member Removed (`app.buds.jar.member_removed/v1`)

**Purpose:** Notify member they were removed + notify other members

**Payload:**
```swift
struct JarMemberRemovedPayload: Codable {
    let jarID: String              // Which jar
    let memberDID: String          // Who was removed
    let removedByDID: String       // Who removed them (owner)
    let removedAtMs: Int64         // Timestamp
    let reason: String?            // Optional reason
}
```

**When generated:**
- Owner taps "Remove Member"

**When received:**
- If you're the removed member: jar disappears from shelf, buds move to Solo
- If you're other member: member removed from jar members list

### 5. Jar Member Left (`app.buds.jar.member_left/v1`)

**Purpose:** Member voluntarily leaves jar

**Payload:**
```swift
struct JarMemberLeftPayload: Codable {
    let jarID: String              // Which jar
    let memberDID: String          // Who left
    let leftAtMs: Int64            // Timestamp
}
```

**When generated:**
- Member taps "Leave Jar"

**When received:**
- Jar disappears from leaver's shelf
- Other members see "[Name] left Friends jar"

### 6. Jar Updated (`app.buds.jar.updated/v1`)

**Purpose:** Sync jar metadata changes (name, description)

**Payload:**
```swift
struct JarUpdatedPayload: Codable {
    let jarID: String              // Which jar
    let jarName: String?           // New name (nil = no change)
    let jarDescription: String?    // New description (nil = no change)
    let updatedByDID: String       // Who made the change
    let updatedAtMs: Int64         // Timestamp
}
```

**When generated:**
- Owner edits jar name or description

**When received:**
- Updates jar metadata for all members

### 7. Jar Deleted (`app.buds.jar.deleted/v1`)

**Purpose:** Owner deletes jar, notify all members

**Payload:**
```swift
struct JarDeletedPayload: Codable {
    let jarID: String              // Which jar
    let deletedByDID: String       // Owner DID
    let deletedAtMs: Int64         // Timestamp
}
```

**When generated:**
- Owner deletes jar (only for shared jars, not Solo)

**When received:**
- Jar disappears from all members' shelves
- Buds move to Solo for all members
- Toast: "Friends jar was deleted by Eric"

### 8. Session Payload Update (Existing)

**Add jar_id to session.created/edited/deleted:**

```swift
struct SessionPayload: Codable {
    // ... existing fields (product_name, rating, etc.) ...

    let jarID: String?  // NEW: Which jar this bud belongs to
                        // nil = Solo jar (backwards compat)
}
```

**Why include jar_id:**
- Sender's context for which jar bud belongs to
- Recipient knows where to put it
- Immutable record of original jar (even if moved later)

---

## Database Changes

### Migration v8: Jar Sync Tables

**1. Update `jars` table:**

```sql
ALTER TABLE jars ADD COLUMN owner_did TEXT NOT NULL DEFAULT '';
ALTER TABLE jars ADD COLUMN created_cid TEXT;  -- CID of jar.created receipt
ALTER TABLE jars ADD COLUMN status TEXT NOT NULL DEFAULT 'active';
-- status: 'active' | 'pending_invite' | 'archived'

CREATE INDEX idx_jars_owner_did ON jars(owner_did);
CREATE INDEX idx_jars_status ON jars(status);
```

**2. Update `jar_members` table:**

```sql
ALTER TABLE jar_members ADD COLUMN invite_cid TEXT;  -- CID of member_added receipt
ALTER TABLE jar_members ADD COLUMN invited_by_did TEXT;
ALTER TABLE jar_members ADD COLUMN accepted_at REAL;  -- Timestamp (nil = pending)

CREATE INDEX idx_jar_members_invite_cid ON jar_members(invite_cid);
```

**3. New `jar_receipts` table:**

```sql
CREATE TABLE jar_receipts (
    id TEXT PRIMARY KEY,           -- UUID
    jar_id TEXT NOT NULL,          -- Which jar
    receipt_cid TEXT NOT NULL,     -- CID of jar receipt
    receipt_type TEXT NOT NULL,    -- jar.created, jar.member_added, etc.
    sender_did TEXT NOT NULL,      -- Who sent this receipt
    payload_json TEXT NOT NULL,    -- JSON serialized payload
    received_at REAL NOT NULL,     -- When we received it
    processed BOOLEAN DEFAULT 0,   -- Have we processed this?

    FOREIGN KEY (jar_id) REFERENCES jars(id) ON DELETE CASCADE
);

CREATE INDEX idx_jar_receipts_jar_id ON jar_receipts(jar_id);
CREATE INDEX idx_jar_receipts_type ON jar_receipts(receipt_type);
CREATE INDEX idx_jar_receipts_processed ON jar_receipts(processed);
```

**4. New `jar_invites` table (for UI state):**

```sql
CREATE TABLE jar_invites (
    id TEXT PRIMARY KEY,           -- UUID
    jar_id TEXT NOT NULL,          -- Which jar
    invite_cid TEXT NOT NULL,      -- CID of jar.created receipt
    inviter_did TEXT NOT NULL,     -- Who invited us
    invited_at REAL NOT NULL,      -- Timestamp
    status TEXT NOT NULL,          -- 'pending' | 'accepted' | 'declined'

    FOREIGN KEY (jar_id) REFERENCES jars(id) ON DELETE CASCADE
);

CREATE INDEX idx_jar_invites_status ON jar_invites(status);
```

**5. Update Solo jar for existing users:**

```sql
-- Backfill owner_did for Solo jar
UPDATE jars
SET owner_did = (SELECT did FROM identity LIMIT 1)
WHERE id = 'solo';
```

---

## Implementation Modules

### Module 1: Receipt Types & Canonicalization (2-3 hours)

**Files to create:**
- `Core/Models/JarReceipts.swift` - All jar payload structs

**Files to modify:**
- `Core/ChaingeKernel/ReceiptType.swift` - Add new receipt types
- `Core/ChaingeKernel/ReceiptCanonicalizer.swift` - Add encode/decode for jar payloads
- `Core/ChaingeKernel/ReceiptManager.swift` - Add jar receipt creation methods

**Tasks:**
1. Define 7 new receipt types (jar.created, jar.member_added, etc.)
2. Create payload structs with proper Codable conformance
3. Add canonicalization support (CBOR encoding)
4. Add verification support
5. Write unit tests for encode/decode

**Success criteria:**
- Can generate jar.created receipt with valid CID
- Can decode jar.created receipt from CBOR
- Signature verification works

### Module 2: Database Migration (1-2 hours)

**Files to modify:**
- `Core/Database/Database.swift` - Add migration v8

**Tasks:**
1. Write migration SQL (ALTER tables, CREATE tables)
2. Backfill Solo jar owner_did
3. Add indexes
4. Test migration on fresh install + existing install
5. Verify rollback safety

**Success criteria:**
- Fresh install: v8 schema created
- Existing install: v7 → v8 migration succeeds
- Solo jar has owner_did set
- All indexes exist

### Module 3: Jar Creation with Receipts (2-3 hours)

**Files to create:**
- `Core/JarSyncManager.swift` - Handles jar receipt generation and processing

**Files to modify:**
- `Core/JarManager.swift` - Update createJar to generate receipt
- `Core/Database/Repositories/JarRepository.swift` - Store jar receipts

**Tasks:**
1. Update JarManager.createJar:
   - Generate jar.created receipt
   - Store receipt CID in jars.created_cid
   - Store receipt in jar_receipts table
2. Create JarSyncManager:
   - `generateJarCreatedReceipt()`
   - `processJarCreatedReceipt()`
   - `storeJarReceipt()`
3. Test local jar creation still works

**Success criteria:**
- Create jar → jar.created receipt generated
- Receipt stored in jar_receipts table
- jars.created_cid populated
- Jar still appears on shelf

### Module 4: Member Invite Flow (3-4 hours)

**Files to modify:**
- `Core/JarManager.swift` - Update addMember
- `Core/JarSyncManager.swift` - Add invite logic
- `Core/InboxManager.swift` - Process jar receipts

**Tasks:**
1. Update JarManager.addMember:
   - Generate jar.member_added receipt
   - Send jar.created + jar.member_added to new member
   - Send jar.member_added to existing members
2. Encrypt jar receipts (same as bud receipts)
3. Send via relay
4. Update InboxManager to route jar receipts to JarSyncManager
5. Process jar.created on receive:
   - Create jar (status: pending_invite)
   - Create jar_invite entry
   - Post notification for UI
6. Process jar.member_added on receive:
   - If you're the invitee: store invite
   - If you're existing member: add member to jar_members

**Success criteria:**
- Device A adds Device B to jar
- Device B receives jar.created receipt
- Jar appears in Device B's `jars` table (status: pending_invite)
- Invite stored in `jar_invites` table

### Module 5: Invite Notification UI (2-3 hours)

**Files to create:**
- `Features/Circle/JarInviteCard.swift` - Card showing pending invite
- `Features/Circle/JarInviteSheet.swift` - Accept/decline sheet

**Files to modify:**
- `Features/Shelf/ShelfView.swift` - Show pending invites section
- `Core/JarSyncManager.swift` - Add acceptInvite/declineInvite methods

**Tasks:**
1. Create JarInviteCard:
   - Show jar name, inviter name
   - "Accept" / "Decline" buttons
   - Preview member count
2. Add pending invites section to ShelfView (above jar grid)
3. Implement accept flow:
   - Update jar status: pending_invite → active
   - Update member status: pending → active
   - Generate jar.invite_accepted receipt
   - Send to owner + all members
   - Move jar to main grid
4. Implement decline flow:
   - Delete jar from local database
   - Generate jar.invite_declined receipt
   - Send to owner
5. Add toast notifications:
   - "Joined Friends jar"
   - "Declined Friends jar invite"

**Success criteria:**
- Pending invites show above jar grid
- Tap "Accept" → jar moves to main grid
- Tap "Decline" → invite disappears
- Owner sees acceptance notification

### Module 6: Bud Sharing with jar_id (2-3 hours)

**Files to modify:**
- `Core/Models/UCRHeader.swift` - Add jar_id to SessionPayload
- `Core/Database/Repositories/MemoryRepository.swift` - Update create() to include jar_id
- `Core/Database/Repositories/MemoryRepository.swift` - Update storeSharedReceipt() to use jar_id from payload
- `Features/Share/ShareToCircleView.swift` - Pass jar context

**Tasks:**
1. Add jar_id field to SessionPayload (optional, for backwards compat)
2. Update MemoryRepository.create():
   - Include jar_id in payload
3. Update MemoryRepository.storeSharedReceipt():
   - Extract jar_id from payload
   - Look up jar in local `jars` table
   - If found: use that jar_id
   - If not found: fall back to Solo, log warning
4. Test bud creation includes jar_id
5. Test bud reception uses jar_id

**Success criteria:**
- Create bud in "Friends" jar → receipt contains jar_id
- Share to member → member receives receipt with jar_id
- Member's bud lands in correct jar
- If jar doesn't exist: lands in Solo (graceful degradation)

### Module 7: Real-time Notifications (2 hours)

**Files to create:**
- `Shared/InboxNotification.swift` - Toast notification view

**Files to modify:**
- `Core/InboxManager.swift` - Post notifications after processing
- `Features/Shelf/ShelfView.swift` - Listen for jar activity
- `Features/Circle/JarDetailView.swift` - Listen for new buds

**Tasks:**
1. Create InboxNotification toast:
   - "[Name] shared [BudName] to [JarName] 🌿"
   - "[Name] joined [JarName]"
   - "[Name] left [JarName]"
2. Post notifications from InboxManager:
   - After bud stored
   - After jar receipt processed
3. Add toast listeners to views:
   - ShelfView: jar-level notifications
   - JarDetailView: bud-level notifications
4. Add unread badge to jar cards:
   - Track unread count in JarStats
   - Show badge on ShelfJarCard
   - Clear on jar open

**Success criteria:**
- Receive shared bud → toast appears
- Receive jar invite → toast appears
- Member joins → toast appears
- Badge shows unread count on jar card

### Module 8: Member Management Sync (2-3 hours)

**Files to modify:**
- `Core/JarManager.swift` - Update removeMember
- `Core/JarSyncManager.swift` - Add member sync handlers

**Tasks:**
1. Implement member removal:
   - Generate jar.member_removed receipt
   - Send to removed member + all active members
   - Process on receive:
     - If you're removed: delete jar, move buds to Solo
     - If you're other member: remove from jar_members
2. Implement member leave:
   - User taps "Leave Jar"
   - Generate jar.member_left receipt
   - Send to owner + all members
   - Delete jar locally, move buds to Solo
3. Add confirmation dialogs:
   - Remove member: "Remove [Name] from [Jar]?"
   - Leave jar: "Leave [Jar]? Your buds will move to Solo."
4. Add toast notifications

**Success criteria:**
- Owner removes member → member sees jar disappear
- Member leaves → owner sees "[Name] left jar"
- Buds move to Solo correctly

### Module 9: Jar Metadata Sync (1-2 hours)

**Files to modify:**
- `Core/JarManager.swift` - Update updateJar
- `Core/JarSyncManager.swift` - Add jar.updated handler

**Tasks:**
1. Update JarManager.updateJar:
   - Generate jar.updated receipt
   - Send to all active members
2. Process jar.updated on receive:
   - Update jar name/description
   - Post notification
   - Refresh UI
3. Add toast: "[Name] renamed jar to [NewName]"

**Success criteria:**
- Owner renames jar → all members see new name
- Owner updates description → all members see update

### Module 10: Edge Cases & Testing (3-4 hours)

**Edge cases to handle:**

1. **Jar name conflicts:**
   - User has local jar "Friends"
   - Gets invite to shared jar "Friends"
   - Solution: Auto-rename local jar to "Friends (Local)"

2. **Duplicate invites:**
   - User already accepted invite
   - Receives duplicate jar.created receipt
   - Solution: Check if jar already exists (by jar_id), ignore

3. **Offline member add:**
   - Owner adds member while offline
   - Solution: Queue messages in outbox (future), or require online

4. **Stale membership:**
   - Owner removes member while member is offline
   - Member comes online, tries to share to jar
   - Solution: Relay rejects (member not in jar_members)

5. **Race conditions:**
   - Two owners rename jar at same time
   - Solution: Last-write-wins based on timestamp

6. **Missing jar on bud receive:**
   - Receive bud for jar_id "xyz" but don't have jar
   - Solution: Land in Solo, log warning, show hint to ask for re-invite

**Testing checklist:**

**Single Device:**
- [ ] Create jar → receipt generated
- [ ] Add member (yourself) → receipts sent
- [ ] Receive invite → jar appears as pending
- [ ] Accept invite → jar becomes active
- [ ] Share bud → jar_id included

**Two Devices:**
- [ ] Device A creates jar → Device B receives invite
- [ ] Device B accepts → Device A sees acceptance
- [ ] Device A shares bud → Device B sees in correct jar
- [ ] Device B shares back → Device A sees it
- [ ] Device A renames jar → Device B sees new name
- [ ] Device A removes Device B → Device B sees jar disappear
- [ ] Device B leaves jar → Device A sees leave notification

**Three Devices (group chat):**
- [ ] Device A creates jar
- [ ] Device A adds Device B and C
- [ ] Both B and C see invites
- [ ] B accepts → C sees notification
- [ ] C accepts → B sees notification
- [ ] A shares bud → B and C both see it
- [ ] B shares bud → A and C both see it

**Edge Cases:**
- [ ] Jar name conflict → local jar renamed
- [ ] Duplicate invite → ignored
- [ ] Missing jar on bud receive → lands in Solo
- [ ] Member removed while offline → syncs on reconnect
- [ ] Jar deleted → all members see deletion

---

## UI/UX Changes

### ShelfView Updates

**New sections:**
```
┌────────────────────────────────┐
│ Shelf                    [+]   │
├────────────────────────────────┤
│ Pending Invites (2)            │  ← NEW
│ ┌──────────────────────────┐   │
│ │ Friends                   │   │
│ │ Invited by Eric           │   │
│ │ [Accept] [Decline]        │   │
│ └──────────────────────────┘   │
│                                │
│ Your Jars                      │  ← Existing
│ ┌──────┐  ┌──────┐            │
│ │ Solo │  │ Work │            │
│ │ 12🌿│  │ 5 🌿│    (2 new)  │  ← Badge
│ └──────┘  └──────┘            │
└────────────────────────────────┘
```

### JarDetailView Updates

**Member status indicators:**
```
┌────────────────────────────────┐
│ ← Friends             [•••]    │
├────────────────────────────────┤
│ Members (2/12)                 │
│ ┌──────────────────────────┐   │
│ │ 👤 Eric (You) - Owner     │   │
│ └──────────────────────────┘   │
│ ┌──────────────────────────┐   │
│ │ 👤 Alex - Active          │   │  ← Status
│ └──────────────────────────┘   │
│ ┌──────────────────────────┐   │
│ │ 👤 Sam - Pending...       │   │  ← Pending
│ └──────────────────────────┘   │
│                                │
│ Buds (8)                  (2)  │  ← Unread badge
│ ...                            │
└────────────────────────────────┘
```

### New: JarInviteSheet

**Accept/decline flow:**
```
┌────────────────────────────────┐
│ Jar Invite                     │
├────────────────────────────────┤
│         🫙                      │
│                                │
│ Eric invited you to            │
│ Friends                        │
│                                │
│ "Share buds with the crew"     │
│                                │
│ 3 members                      │
│ 👤 Eric, Alex, Sam             │
│                                │
│ ┌──────────┐ ┌──────────┐     │
│ │ Decline  │ │ Accept ✓ │     │
│ └──────────┘ └──────────┘     │
└────────────────────────────────┘
```

### Toast Notifications

**Variants:**
- "Eric shared Blue Dream to Friends 🌿"
- "You joined Friends jar"
- "Alex joined Friends jar"
- "Sam left Friends jar"
- "Eric renamed jar to Homies"

---

## Edge Case Handling

### 1. Jar Name Conflicts

**Scenario:** User has local jar "Friends", gets invite to shared jar "Friends"

**Solution:**
```swift
func processJarCreatedReceipt(payload: JarCreatedPayload) async throws {
    // Check if jar_id already exists
    if let existingJar = try await JarRepository.shared.getJar(id: payload.jarID) {
        print("⚠️ Jar already exists, ignoring duplicate invite")
        return
    }

    // Check if jar name conflicts with local jar
    var finalName = payload.jarName
    if let conflictingJar = try await JarRepository.shared.getJarByName(payload.jarName) {
        // Rename local jar
        try await JarRepository.shared.updateJar(
            jarID: conflictingJar.id,
            name: "\(conflictingJar.name) (Local)",
            description: conflictingJar.description
        )
        print("⚠️ Renamed local jar to avoid conflict")
    }

    // Create jar with pending_invite status
    try await JarRepository.shared.createJarFromReceipt(
        jarID: payload.jarID,
        name: finalName,
        description: payload.jarDescription,
        ownerDID: payload.ownerDID,
        createdCID: receiptCID,
        status: .pending_invite
    )
}
```

### 2. Missing Jar on Bud Receive

**Scenario:** Receive bud for jar_id "xyz" but jar doesn't exist locally

**Solution:**
```swift
func storeSharedReceipt(...) async throws {
    // Extract jar_id from payload
    let payload = try ReceiptCanonicalizer.decodeSessionPayload(from: receiptFields.payloadCBOR)
    let jarID = payload.jarID ?? "solo"  // Backwards compat

    // Check if jar exists
    let jar = try await db.readAsync { db in
        try Jar.fetchOne(db, key: jarID)
    }

    if jar == nil && jarID != "solo" {
        // Jar doesn't exist - graceful degradation
        print("⚠️ Bud for unknown jar \(jarID), landing in Solo")

        // Land in Solo with metadata
        try await db.writeAsync { db in
            let localReceipt = LocalReceipt(
                uuid: UUID(),
                headerCID: receiptCID,
                jarID: "solo",  // Override to Solo
                senderDID: senderDID,
                // ... other fields
                localNotes: "Shared to jar: \(jarID)"  // Hint for user
            )
            try localReceipt.insert(db)
        }

        // Show toast with hint
        await MainActor.run {
            ToastManager.shared.show("Received shared bud (unknown jar)")
        }
        return
    }

    // Normal flow: store with jar_id
    // ...
}
```

### 3. Offline Member Management

**Scenario:** Owner adds member while offline

**Current limitation:** Requires online to lookup DID and send invite

**Future solution (Phase 11+):**
- Queue operations in `outbox_messages` table
- When online: process outbox, send pending messages
- Show "Pending (offline)" status in UI

**For Phase 10.3:**
- Require online for member add
- Show error toast: "Cannot add members offline"

### 4. Stale Membership (Security)

**Scenario:** Owner removes Device B while Device B is offline. Device B comes online and tries to share bud to jar.

**Relay-side protection:**
```typescript
// Cloudflare Worker: /api/messages/send
async function sendMessage(request) {
    const { jar_id, recipient_dids } = await request.json();

    // Check if sender is active member of jar
    const isMember = await db.query(`
        SELECT 1 FROM jar_members
        WHERE jar_id = ? AND member_did = ? AND status = 'active'
    `, [jar_id, sender_did]);

    if (!isMember) {
        return new Response(
            JSON.stringify({ error: "Not a member of this jar" }),
            { status: 403 }
        );
    }

    // Proceed with message send
    // ...
}
```

**Client-side handling:**
```swift
func shareMemory(memoryCID: String, jarID: String, with circleDIDs: [String]) async throws {
    do {
        try await RelayClient.shared.sendMessage(encrypted)
    } catch RelayError.forbidden {
        // Not a member anymore
        throw ShareError.notAMember("You are no longer a member of this jar")
    }
}
```

### 5. Race Conditions (Jar Rename)

**Scenario:** Device A and Device B both rename jar at same time

**Solution: Last-write-wins based on timestamp**

```swift
func processJarUpdatedReceipt(payload: JarUpdatedPayload) async throws {
    let jar = try await JarRepository.shared.getJar(id: payload.jarID)

    // Check timestamp to prevent out-of-order updates
    if let lastUpdatedAt = jar.lastUpdatedAt {
        if payload.updatedAtMs < Int64(lastUpdatedAt * 1000) {
            print("⚠️ Ignoring stale jar update (older than current)")
            return
        }
    }

    // Apply update
    try await JarRepository.shared.updateJar(
        jarID: payload.jarID,
        name: payload.jarName ?? jar.name,
        description: payload.jarDescription ?? jar.description
    )

    // Update timestamp
    try await JarRepository.shared.setLastUpdatedAt(
        jarID: payload.jarID,
        timestamp: Double(payload.updatedAtMs) / 1000.0
    )
}
```

---

## Testing Strategy

### Unit Tests

**ReceiptManager:**
- [ ] Generate jar.created receipt → valid CID
- [ ] Encode/decode all jar payloads
- [ ] Signature verification

**JarSyncManager:**
- [ ] processJarCreatedReceipt → jar created
- [ ] processJarMemberAdded → member added
- [ ] processJarInviteAccepted → status updated
- [ ] Edge case: duplicate invite → ignored
- [ ] Edge case: name conflict → local renamed

**MemoryRepository:**
- [ ] storeSharedReceipt with jar_id → correct jar
- [ ] storeSharedReceipt missing jar → Solo fallback

### Integration Tests (Two Simulators)

**Jar Creation + Invite:**
1. Device A: Create jar "Friends"
2. Device A: Add Device B's phone
3. Device B: Poll inbox (or wait 30s)
4. Device B: Verify jar appears in pending invites
5. Device B: Accept invite
6. Device A: Verify acceptance notification
7. Both: Verify jar shows in active jars

**Bud Sharing:**
1. Device A: Create bud "Blue Dream" in "Friends"
2. Device A: Share to Device B
3. Device B: Poll inbox
4. Device B: Verify bud appears in "Friends" jar (not Solo)
5. Device B: Verify toast notification
6. Device B: Verify jar card badge

**Member Management:**
1. Device A: Remove Device B from jar
2. Device B: Verify jar disappears
3. Device B: Verify buds moved to Solo
4. Device B: Verify toast notification

### Manual TestFlight Testing (Real Devices)

**Multi-user scenarios:**
- [ ] 3-person jar: all members see all buds
- [ ] Rename jar: all members see new name
- [ ] Remove member: member sees jar disappear
- [ ] Member leaves: others see notification
- [ ] Offline member add: error shown
- [ ] Duplicate invite: gracefully handled

---

## Rollout Plan

### Phase 1: Internal Testing (You + Cofounder)

**Week 1:**
1. Implement Modules 1-6 (receipts, DB, creation, invites, bud sync)
2. Test with 2 devices (your phone + cofounder's phone)
3. Verify core flow works: create jar → invite → accept → share bud

**Success criteria:**
- Jar invite flow works
- Shared buds land in correct jar
- No crashes, no data loss

### Phase 2: Polish + Notifications (You + Cofounder)

**Week 2:**
1. Implement Modules 7-9 (notifications, member management, metadata sync)
2. Test member removal, jar renaming, edge cases
3. Add toast notifications, badges, polish

**Success criteria:**
- UX feels smooth
- Notifications are timely
- Edge cases handled gracefully

### Phase 3: Beta Testing (20-50 Users)

**Week 3:**
1. Push to TestFlight
2. Monitor for edge cases (name conflicts, missing jars, etc.)
3. Gather feedback on UX

**Success criteria:**
- No critical bugs
- Users understand jar invite flow
- Shared buds appear in correct jars

### Phase 4: App Store Launch

**Week 4+:**
1. Fix any critical bugs from beta
2. Final polish
3. Submit to App Store

---

## Open Questions / Decisions Needed

### 1. Solo Jar Behavior

**Question:** Should Solo jar be shareable?

**Option A: Solo is always private (recommended)**
- Solo jar has no members
- Can't add members to Solo
- Can't share buds from Solo
- Clean, simple, matches name

**Option B: Solo can become shared**
- Add members to Solo → converts to shared jar
- Rename to "Friends" or similar
- More flexible but confusing

**Decision:** Option A - Keep Solo private

### 2. Jar Limits

**Question:** Should we limit number of jars per user?

**Current:** Unlimited jars

**Options:**
- Unlimited (current)
- Max 10 jars (prevent abuse)
- Freemium: 3 jars free, unlimited paid

**Decision:** Start unlimited, revisit after beta feedback

### 3. Bud Visibility After Removal

**Question:** When member is removed, what happens to shared buds they received?

**Option A: Keep buds (recommended)**
- Removed member keeps buds in Solo
- Can view but jar context is lost
- Privacy-friendly, user keeps their data

**Option B: Delete buds**
- Removed member loses access to all shared buds
- Clean break, privacy-focused
- But surprising, data loss

**Option C: Owner choice**
- Owner decides on removal: "Keep memories" vs "Revoke access"
- Flexible but complex

**Decision:** Option A - Keep buds, move to Solo

### 4. Push Notifications

**Question:** Should we add push notifications for jar activity?

**Current:** 30s polling, toast notifications in-app

**Future:** Silent push to trigger immediate inbox poll

**Decision:** Defer push to Phase 11, polling is sufficient for beta

### 5. Jar Discovery

**Question:** Should we add "Browse public jars" or "Join by code"?

**Current:** Invite-only, owner adds members by phone

**Future ideas:**
- Share join link: "buds://join/xyz"
- Public jars with search
- QR code invite

**Decision:** Invite-only for V1, revisit after launch

---

## Success Metrics

### Technical Metrics

- [ ] Jar invite acceptance rate >80%
- [ ] Shared buds land in correct jar >95%
- [ ] Receipt processing latency <500ms
- [ ] Zero data loss on jar operations
- [ ] Zero crashes in jar flows

### UX Metrics

- [ ] Users understand jar invites (no confusion in beta feedback)
- [ ] Toast notifications are helpful (mentioned positively)
- [ ] Jar renaming feels natural
- [ ] Member management is intuitive

### Performance Metrics

- [ ] Inbox polling overhead <10% battery drain
- [ ] Jar sync doesn't increase memory usage
- [ ] Database queries <100ms for jar operations

---

## Timeline Estimate

**Total: 18-24 hours**

| Module | Estimated Time | Description |
|--------|----------------|-------------|
| 1. Receipt Types | 2-3 hours | Define payloads, canonicalization |
| 2. Database Migration | 1-2 hours | Schema changes, migration v8 |
| 3. Jar Creation | 2-3 hours | Generate receipts on creation |
| 4. Member Invite Flow | 3-4 hours | Send invites, process receipts |
| 5. Invite UI | 2-3 hours | Accept/decline flow, UI |
| 6. Bud jar_id Sync | 2-3 hours | Include jar_id, route correctly |
| 7. Notifications | 2 hours | Toasts, badges |
| 8. Member Mgmt Sync | 2-3 hours | Remove, leave, sync |
| 9. Metadata Sync | 1-2 hours | Rename, description updates |
| 10. Edge Cases | 3-4 hours | Testing, polish |

**Weekly breakdown:**
- Week 1 (16-20 hours): Modules 1-6 (core functionality)
- Week 2 (2-4 hours): Modules 7-10 (polish + testing)

---

## Next Steps

1. **Review this plan** - Any questions or changes?
2. **Start Module 1** - Receipt types & payloads
3. **Parallel work possible:**
   - You: Test jar creation on device
   - Me: Implement receipt processing

Ready to start? 🚀
