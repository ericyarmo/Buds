# Phase 5 Complete: Circle Mechanics

**Completed:** December 20, 2025
**Duration:** ~6 hours (design + implementation + testing)
**Status:** ✅ All features working, ready for E2EE integration

---

## What Was Built

### 1. Database Schema (Migration v3)
- **`circles` table** - Friend roster with DID-based identity
- **Updated `devices` table** - Multi-device support schema
- **Indexes** - Optimized queries for `did` and `status` columns
- **Status tracking** - pending/active/removed lifecycle

### 2. Core Models
- **CircleMember** - GRDB-backed model with Identifiable conformance
  - DID-based identity (not phone numbers)
  - Display names (local-only, privacy-preserving)
  - X25519 public key storage for E2EE
  - Status enum: pending, active, removed
  - Timestamps: invited_at, joined_at, removed_at

- **Device** - Multi-device support model
  - Device-level X25519 and Ed25519 keypairs
  - Owner DID mapping
  - Status tracking (active/revoked)

### 3. CircleManager
- **Singleton ObservableObject** - Centralized Circle state
- **CRUD operations** - Add, remove, update members
- **12-member limit** - Privacy-focused roster size
- **Placeholder DIDs** - Phase 5 uses local placeholders (Phase 6 adds relay lookup)
- **Real-time updates** - @Published members array

### 4. Circle UI (Dark Mode)
- **CircleView** - Main Circle management screen
  - Empty state with invite prompt
  - Member list with capacity indicator (X/12)
  - Status badges (color-coded: green/orange/gray)
  - Member cards with avatar initials

- **AddMemberView** - Sheet for inviting friends
  - Display name + phone number form
  - +1 US phone prefix (hardcoded for v0.1)
  - Form validation
  - Error handling

- **MemberDetailView** - Individual member management
  - Large avatar with initial
  - Inline name editing
  - DID and phone display
  - Remove with confirmation alert
  - InfoRow component for consistent layout

### 5. Design System Updates
- **Dark mode backgrounds** - Black (#000000) instead of light gray
- **Text contrast fixes** - White text on dark backgrounds
- **Card readability** - Black text on light cards
- **Consistent styling** - Applied across Timeline, Circle, Profile

---

## Technical Implementation

### Database Migration v3

```sql
CREATE TABLE circles (
    id TEXT PRIMARY KEY NOT NULL,
    did TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    phone_number TEXT,              -- Optional, for display only
    avatar_cid TEXT,
    pubkey_x25519 TEXT NOT NULL,    -- For E2EE key wrapping
    status TEXT NOT NULL,            -- 'pending' | 'active' | 'removed'
    joined_at REAL,
    invited_at REAL,
    removed_at REAL,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL
);

CREATE TABLE devices (
    device_id TEXT PRIMARY KEY NOT NULL,
    owner_did TEXT NOT NULL,
    device_name TEXT NOT NULL,
    pubkey_x25519 TEXT NOT NULL,
    pubkey_ed25519 TEXT NOT NULL,
    status TEXT NOT NULL,            -- 'active' | 'revoked'
    registered_at REAL NOT NULL,
    last_seen_at REAL
);
```

### CircleManager Architecture

```swift
@MainActor
class CircleManager: ObservableObject {
    static let shared = CircleManager()

    @Published var members: [CircleMember] = []
    @Published var isLoading = false

    private let maxCircleSize = 12

    func addMember(phoneNumber: String, displayName: String) async throws {
        // Phase 5: Create placeholder DID
        let placeholderDID = "did:buds:placeholder_\(UUID().uuidString.prefix(8))"

        // Phase 6: Will call RelayClient.lookupDID(phoneNumber)

        // Store in local DB
        let member = CircleMember(...)
        try await db.write { try member.insert($0) }
        await loadMembers()
    }
}
```

### Privacy Model

**Phone Numbers:**
- Entered by user (local only)
- Displayed in UI (optional)
- **Never stored in receipts**
- **Never sent to relay server** (Phase 6 will hash with SHA-256)

**DIDs:**
- Phase 5: Placeholder format `did:buds:placeholder_<uuid>`
- Phase 6: Real DIDs from `did:buds:<base58(pubkey_ed25519)>`
- Used for all cross-device identity

**Display Names:**
- Local-only (your nickname for the person)
- Not shared with relay or other devices
- Privacy-preserving (no global namespace)

---

## Architecture Highlights

### Local-First Circle Roster

```
┌─────────────────────────────────────────┐
│         Local Circle Storage            │
│   (circles table in SQLite, private)    │
│                                         │
│  Circle Member = {                      │
│    did: "did:buds:abc123"              │
│    displayName: "Alex" (local only)    │
│    pubkeyX25519: "base64..." (E2EE)    │
│    status: "active" | "pending"        │
│  }                                      │
└─────────────────────────────────────────┘
           ↓ Phase 6: Share Memory
┌─────────────────────────────────────────┐
│        Cloudflare Workers Relay         │
│   (E2EE: sees only encrypted payload)   │
│                                         │
│  POST /api/messages/send {              │
│    encryptedPayload: "base64..."       │
│    wrappedKeys: {                       │
│      deviceId1: "wrapped_aes_key_1",   │
│      deviceId2: "wrapped_aes_key_2"    │
│    }                                    │
│  }                                      │
└─────────────────────────────────────────┘
```

### Multi-Device Model

**Problem:** Alice has iPhone + iPad, both need to decrypt Circle messages.

**Solution:** Device-based key wrapping
- Each device gets unique `device_id` (UUID)
- Each device has own X25519 keypair
- When sharing, sender wraps AES key for **each recipient device**
- Relay stores `wrappedKeys` map: `{ deviceId → wrapped_aes_key }`

**Example:**
```
Alice shares memory with Bob (who has 2 devices):
1. Generate ephemeral AES-256 key
2. Encrypt memory payload with AES-GCM
3. Wrap AES key for Bob's iPhone (X25519 key agreement)
4. Wrap AES key for Bob's iPad (separate X25519 key agreement)
5. Send to relay: { wrappedKeys: { "bob-iphone": "...", "bob-ipad": "..." } }
6. Both Bob's devices can unwrap and decrypt
```

---

## Testing Results

### Manual Testing (Dec 20, 2025)

**✅ Circle Management**
- Add member with display name + phone → Success
- View member list with status badges → Success
- Edit member name inline → Success
- Remove member with confirmation → Success
- 12-member limit enforced → Success (button disables at 12)

**✅ UI/UX**
- Empty state displays correctly → Success
- Dark mode backgrounds (black) → Success
- Text contrast (white on dark, black on cards) → Success
- Member cards with avatar initials → Success
- Status badges color-coded → Success

**✅ Database**
- Migration v3 runs without errors → Success
- Circles table created → Success
- Devices table recreated with new schema → Success
- Indexes created → Success
- CRUD operations work → Success

**✅ Edge Cases**
- Add duplicate phone number → Allowed (different display names)
- Remove non-existent member → Graceful error
- Empty Circle state → Shows invite prompt
- Long display names → Truncate gracefully

---

## Known Limitations (Phase 5)

### 1. Placeholder DIDs
**Current:** `did:buds:placeholder_<uuid>`
**Phase 6:** Real DIDs from Cloudflare relay lookup

### 2. No Real Sharing
**Current:** UI mockup only
**Phase 6:** E2EE encryption + Cloudflare Workers relay

### 3. No Device Registration
**Current:** Devices table schema exists but unused
**Phase 6:** Device registration on first launch

### 4. Status Always "Pending"
**Current:** All members show "pending" status
**Phase 6:** "active" when DID lookup succeeds

### 5. No Multi-Device Discovery
**Current:** Only stores one pubkey per member
**Phase 6:** Query all devices for a DID from relay

---

## Code Metrics

**Files Created (6):**
- `Core/CircleManager.swift` - 140 lines
- `Core/Models/CircleMember.swift` - 70 lines
- `Core/Models/Device.swift` - 55 lines
- `Features/Circle/CircleView.swift` - 200 lines
- `Features/Circle/AddMemberView.swift` - 155 lines
- `Features/Circle/MemberDetailView.swift` - 195 lines

**Files Modified (4):**
- `Core/Database/Database.swift` - +60 lines (migration v3)
- `Features/MainTabView.swift` - Replaced Circle placeholder
- `Features/Timeline/TimelineView.swift` - Dark mode
- `Features/Profile/ProfileView.swift` - Dark mode

**Total Lines Added:** ~875 lines Swift

**Database:**
- 2 new tables (circles, devices updated)
- 4 new indexes

---

## What's Next (Phase 6)

Phase 6 will transform Circle from local-only UI to functional E2EE sharing:

### 1. Cloudflare Workers Relay
- Device registration endpoint
- Phone → DID lookup
- Message send/receive
- D1 database (SQLite at the edge)

### 2. Device Management
- Register device on first launch
- Store X25519 + Ed25519 keypairs
- Multi-device discovery

### 3. E2EE Encryption
- X25519 key agreement
- AES-256-GCM payload encryption
- Per-message ephemeral AES keys
- Multi-device key wrapping

### 4. Share Flow
- "Share to Circle" UI
- Encrypt memory with recipient device pubkeys
- POST to Cloudflare Workers
- Recipient polls inbox and decrypts

### 5. Real DID Lookup
- Replace placeholder DIDs with real DIDs
- Phone number → DID mapping (SHA-256 hashed)
- Member status: pending → active when found

---

## Architecture Decisions

### Why Local-First Circle?
**Privacy:** No server-side roster → relay can't see your social graph
**Ownership:** You control the list, not the platform
**Offline:** View Circle even without network

### Why 12-Member Limit?
**Key Distribution:** Manageable key wrapping for each device
**Privacy:** Small, trusted group (not broadcast)
**UX:** Intimate friend group, not social network

### Why Display Names are Local?
**Privacy:** No global namespace → can't enumerate users
**Flexibility:** You choose nicknames (e.g., "Mom" vs "Susan")
**Offline:** No lookup required to display name

### Why Device-Based Encryption?
**Multi-Device:** Each device has own keypair
**Forward Secrecy:** Revoke device without affecting others
**Key Rotation:** Easy to rotate per-device keys

---

## Lessons Learned

### 1. Dark Mode Cohesion
**Challenge:** Light gray backgrounds made app feel inconsistent.
**Solution:** Pure black (#000000) backgrounds with white text creates cohesive dark mode.

### 2. Identifiable Conformance
**Challenge:** SwiftUI `.sheet(item:)` requires `Identifiable`.
**Solution:** CircleMember already had `id: String`, just needed protocol conformance.

### 3. Card Text Contrast
**Challenge:** Gray text on white cards hard to read.
**Solution:** Black text on cards, white text on dark backgrounds.

### 4. Migration Testing
**Challenge:** Schema changes required app reinstall in DEBUG mode.
**Solution:** `eraseDatabaseOnSchemaChange = true` makes iteration fast.

---

## Screenshots

**Empty State:**
- Large icon, clear CTA ("Add Friend")
- Explains Circle purpose ("Max 12 members")

**Member List:**
- Capacity indicator (2 / 12 members)
- Avatar circles with initials
- Status badges (pending/active)
- Phone numbers (optional display)

**Member Detail:**
- Large avatar
- Inline name editing (pencil icon)
- DID display (for debugging)
- Remove button (red, confirmation required)

**Add Member:**
- Display name field
- Phone number field (+1 prefix)
- Form validation (both fields required)
- Loading state while adding

---

## Production Readiness

**Phase 5 Status: ✅ Production-Ready UI**

Circle mechanics are **UI-complete** but **non-functional** for sharing:
- ✅ CRUD operations work
- ✅ Dark mode design polished
- ✅ Database schema ready for E2EE
- ⏳ Placeholder DIDs (Phase 6: real lookup)
- ⏳ No encryption (Phase 6: E2EE)
- ⏳ No relay server (Phase 6: Cloudflare Workers)

**Safe to ship:** Yes (Circle is view-only in v0.1)
**Functional sharing:** No (requires Phase 6 completion)

---

## Migration Notes

**Database Schema Evolution:**

```
v1 (Phase 0-2): Base schema
  - ucr_headers, local_receipts, locations, blobs
  - circle_members table (old schema)
  - devices table (old schema)

v2 (Phase 3): Multi-image support
  - image_cid → image_cids (JSON array)

v3 (Phase 5): Circle mechanics
  - circles table (new, replaces circle_members)
  - devices table (updated schema)
```

**Note:** Phase 5 creates `circles` table separately from old `circle_members`. Both coexist in v3, but only `circles` is used. Future migration can drop `circle_members`.

---

## Acknowledgments

**Design Inspiration:** Signal's private groups, iMessage's group chats
**Architecture:** ChaingeOS principles (local-first, receipts-first, causality-first)
**Crypto:** CryptoKit (X25519, Ed25519, AES-GCM)

---

**December 20, 2025: Circle mechanics complete! Foundation ready for E2EE sharing in Phase 6. 🎉🌿**
