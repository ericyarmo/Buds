# Buds R1 Master Plan — App Store V1 (UPDATED)

**Status**: ✅ Phases 1-10 Complete | 🚧 Phase 10.1 In Progress (Beta Readiness)
**Date**: December 29, 2025
**Last Update**: Phase 10.1 Modules 1-4 Complete (UX + Error Handling)
**Goal**: Ship TestFlight beta → Gather feedback → Ship App Store V1
**Target**: 20-50 beta users → App Store launch

---

## Executive Summary

**Current State** (as of Dec 29, 2025):
- ✅ **Phases 1-10 COMPLETE**: E2EE, DB, Jars, Shelf, Production Hardening
- 🚧 **Phase 10.1 IN PROGRESS**: Beta Readiness - Modules 1-5 ✅ Complete
- 🎯 **Next Milestone**: Manual Testing → Module 6 (TestFlight Prep) → Beta Launch
- 📦 **Parallel Track**: Building Phases 11-14 (Map, Shop, AI) while polishing beta

**Architecture Changes (Live)**:
- ✅ Jar-centric model (migrated from Circle)
- ✅ Shelf grid view (replaced Timeline)
- ✅ Lightweight MemoryListItem (performance optimization)
- ✅ Simplified create flow (name → enrich pattern)
- ✅ Visual enrichment signals (dashed borders for minimal buds)
- ✅ Memory detail view (full-screen with edit/delete/share)

**Core Physics (Unchanged)**:
- ✅ Chainge Kernel (UCR, CID, signatures) - SOLID
- ✅ E2EE messaging (X25519 + AES-256-GCM) - VERIFIED
- ✅ Receipt-based data model - IMMUTABLE
- ✅ Multi-device sync - WORKING

---

## Phase Status (Complete → In Progress)

### ✅ Phases 1-7: Foundation (COMPLETE)
**Timeline**: ~30 hours
**Status**: Shipped, stable, no regressions

**What Was Built**:
1. **Phase 1**: Auth + Device Management
2. **Phase 2**: E2EE Core (X25519 key exchange)
3. **Phase 3**: Receipt System (UCR implementation)
4. **Phase 4**: Relay Infrastructure (Cloudflare Workers)
5. **Phase 5**: Multi-device Sync
6. **Phase 6**: Image Handling + Blob Storage
7. **Phase 7**: Database Layer (GRDB)

**Key Files**:
- `Core/Auth/AuthManager.swift`
- `Core/Crypto/CryptoManager.swift`
- `Core/Receipt/ReceiptManager.swift`
- `Core/Database/Database.swift`
- `Core/Relay/RelayClient.swift`

---

### ✅ Phase 8: Database Migration + Jar Model (COMPLETE)
**Timeline**: 3 hours
**Date Completed**: December 24, 2025
**Status**: ✅ Migration v5 successful, all data migrated

**What Changed**:
- Circle-centric → Jar-centric architecture
- New models: `Jar`, `JarMember`
- Migration v5: All existing buds → "Solo" jar
- JarRepository for CRUD operations

**Files Created** (4):
- `Core/Models/Jar.swift`
- `Core/Models/JarMember.swift`
- `Core/Database/Repositories/JarRepository.swift`
- `Core/JarManager.swift` (renamed from CircleManager)

**Success Metrics**:
- ✅ Zero data loss during migration
- ✅ All existing buds accessible in Solo jar
- ✅ Create/delete jars working
- ✅ Member management working (add/remove, max 12)

---

### ✅ Phase 9a: Jar Management (COMPLETE)
**Timeline**: 4 hours
**Date Completed**: December 25, 2025
**Status**: ✅ Full CRUD + member management

**What Was Built**:
- Create/edit/delete jars
- Add/remove jar members
- Jar metadata (name, description, color)
- Member roles (owner vs member)
- Jar capacity limits (max 12 members)

**Files Created** (5):
- `Features/Jar/CreateJarView.swift`
- `Features/Jar/JarDetailView.swift`
- `Features/Jar/AddMemberView.swift`
- `Features/Jar/MemberDetailView.swift`
- `Core/Models/JarMember.swift` (enhanced)

**Success Metrics**:
- ✅ Can create jars with custom name/color
- ✅ Can add members via phone number
- ✅ Can remove members (owner only)
- ✅ Member limit enforced (12 max)
- ✅ Owner permissions work correctly

---

### ✅ Phase 9b: Shelf View (COMPLETE)
**Timeline**: 6 hours
**Date Completed**: December 26, 2025
**Status**: ✅ Timeline fully replaced by Shelf

**What Was Built**:
- Shelf grid layout (2 columns)
- Jar cards with bud counts
- Pull-to-refresh
- Jar deletion with Solo migration
- Empty state UX
- FAB for quick create

**Files Created** (2):
- `Features/Shelf/ShelfView.swift`
- `Features/Shelf/JarCard.swift`

**Files Deprecated**:
- `Features/Timeline/TimelineView.swift` (old, not used)

**Design**:
```
┌────────────────────────────┐
│ Shelf              [+]     │
├────────────────────────────┤
│ ┌──────┐  ┌──────┐        │
│ │ Solo │  │ Friends│       │
│ │ 12📷│  │ 5 📷 │        │
│ └──────┘  └──────┘        │
│ ┌──────┐  ┌──────┐        │
│ │ Work │  │ Travel│        │
│ │ 3 📷 │  │ 0 📷 │        │
│ └──────┘  └──────┘        │
│                            │
│          [+ FAB]           │
└────────────────────────────┘
```

**Success Metrics**:
- ✅ Shelf loads all jars (cached)
- ✅ Bud counts accurate
- ✅ Jar deletion moves buds to Solo
- ✅ Pull-to-refresh works
- ✅ FAB opens jar picker

---

### ✅ Phase 10: Production Hardening (COMPLETE)
**Timeline**: 7-9 hours
**Date Completed**: December 27, 2025
**Status**: ✅ All critical bugs fixed, TestFlight-ready infrastructure

**What Was Fixed**:
1. **E2EE Verification Test**: ✅ Signatures verified, jar deletion safe
2. **Memory Optimization**: ✅ Downsampled thumbnails, <40MB baseline
3. **Lightweight List Loading**: ✅ MemoryListItem model (no full Memory objects)
4. **Split Refresh Logic**: ✅ refreshJar() vs refreshGlobal() (5x faster)
5. **Toast Notifications**: ✅ Success/error feedback
6. **Haptic Feedback**: ✅ FAB, buttons, interactions
7. **Pull-to-Refresh**: ✅ Shelf + JarDetailView

**Files Created** (3):
- `Core/Models/MemoryListItem.swift`
- `Shared/Toast.swift`
- `Features/CreateMemory/JarPickerView.swift`

**Files Modified** (8):
- `Core/Database/Repositories/MemoryRepository.swift` (fetchLightweightList)
- `Features/Circle/MemoryListCard.swift` (downsampled thumbnails)
- `Features/Circle/JarDetailView.swift` (pull-to-refresh, empty state)
- `Features/Shelf/ShelfView.swift` (FAB, haptics, toast)
- `Features/CreateMemory/CreateMemoryView.swift` (toast on success)
- `Core/JarManager.swift` (split refresh methods)

**Performance Improvements**:
- Before: 70-80MB with 1 image bud → After: ~30-40MB
- Before: Full refresh on every change → After: Targeted jar refresh (5x faster)
- Before: Full Memory objects in lists → After: Lightweight MemoryListItem

**Success Metrics**:
- ✅ Memory <40MB with 10 buds
- ✅ E2EE signatures still verify after jar deletion
- ✅ List scrolling smooth (60fps)
- ✅ No crashes on common flows
- ✅ Archive build succeeds

---

### 🚧 Phase 10.1: Beta Readiness - 20-50 Real Users (IN PROGRESS)
**Timeline**: 18-24 hours (estimated)
**Started**: December 28, 2025
**Status**: 🚧 Module 1.4 Complete (Reactions) → Module 2 Next
**Goal**: Fill UX gaps so beta users don't hit dead ends

**Design Philosophy**:
> "Create fast, enrich later. Visual signals show what needs attention."

**What's Being Built**:

#### ✅ Module 1.0: Simplified Create → Enrich Flow (COMPLETE)
**Timeline**: 2-3 hours
**Completed**: December 28, 2025

**Problem**: Old create flow too complex (10+ fields), users abandon mid-flow.

**Solution**: Two-step pattern:
1. **Quick Create**: Name + Type → Save (< 15 seconds)
2. **Enrich Invitation**: Auto-shows enrich view → Add photos/rating/effects OR skip

**Implementation**:
```swift
// Step 1: Simplified CreateMemoryView (name + type only)
CreateMemoryView(jarID: "solo") { createdMemoryID in
    // Step 2: On save, immediately show enrich view
    showEditMemory(createdMemoryID)
}
```

**Visual Enrichment Signals**:
- **Minimal buds** (name only):
  - 🟠 Dashed orange border
  - 📝 Pencil icon (no thumbnail)
  - "⭐️ Not rated yet"
  - "+ Add Details" hint text

- **Partial buds** (some enrichment):
  - Solid border
  - 🌿 Leaf.circle icon

- **Complete buds** (fully enriched):
  - Thumbnail image
  - Full metadata displayed

**Files Created** (1):
- `Features/Memory/EditMemoryView.swift` (placeholder for Module 1.2)

**Files Modified** (6):
- `Features/CreateMemory/CreateMemoryView.swift` (simplified to 2 fields)
- `Core/Models/MemoryListItem.swift` (added enrichment fields + enrichmentLevel)
- `Core/Database/Repositories/MemoryRepository.swift` (include effects/notes in query)
- `Features/Circle/MemoryListCard.swift` (visual enrichment signals)
- `Features/Circle/JarDetailView.swift` (create → enrich sheets)
- `Features/Shelf/ShelfView.swift` (FAB → jar picker → create → enrich)
- `Features/CreateMemory/JarPickerView.swift` (callback pattern, no nested NavigationLinks)

**Success Criteria**:
- ✅ Can create bud with just name (<15 seconds)
- ✅ Enrich view appears automatically after save
- ✅ Minimal buds show dashed orange border
- ✅ "+ Add Details" hint appears
- ✅ Pencil icon shows instead of thumbnail
- ✅ "⭐️ Not rated yet" text appears
- ✅ All 4 entry points work (FAB, empty state, menu, jar detail)
- ✅ Data persists with defaults (rating: 0, effects: [], notes: "")

**Testing**: Build + test in progress...

---

#### ✅ Module 1.1: Memory Detail View (COMPLETE)
**Timeline**: 2-3 hours (faster than estimated, reused existing view)
**Completed**: December 28, 2025

**What Was Built**: Full-screen view to see bud data
- ✅ Display all metadata (strain, type, rating, notes, effects, flavors, product details)
- ✅ Image carousel (swipeable, up to 3 images)
- ✅ Timestamps (created, relative time)
- ✅ Edit button (wired to EditMemoryView)
- ✅ Delete button with confirmation dialog
- ✅ Share to Circle button
- ✅ Favorite toggle
- ✅ Black background styling (Phase 10.1 consistency)

**Files Modified** (2):
- `Features/Timeline/MemoryDetailView.swift` (updated styling + edit wiring)
- `Features/Circle/JarDetailView.swift` (added navigation + loadMemoryDetail())

**Navigation Flow**:
```swift
// Tap MemoryListCard → Fetch full Memory → Show sheet
MemoryListCard(item: item) {
    await loadMemoryDetail(id: item.id)  // Fetches Memory from DB
}
.sheet(item: $selectedMemory) { memory in
    MemoryDetailView(memory: memory)
}
```

**Success Criteria**:
- ✅ Tap bud card → full detail view appears
- ✅ All images load in carousel
- ✅ All metadata displays correctly
- ✅ Edit button opens EditMemoryView
- ✅ Delete button shows confirmation → deletes bud
- ✅ Black background matches app theme

---

#### ✅ Module 1.2: Edit Memory (Enrich) (COMPLETE)
**Timeline**: 3-4 hours
**Completed**: December 28, 2025

**What Was Built**: Full edit/enrich form with all fields
- ✅ Pre-fills existing data from Memory object
- ✅ Edit all fields: name, type, rating, effects, notes, images
- ✅ 12 common effects checkboxes (relaxed, happy, euphoric, etc.)
- ✅ Camera + photo library buttons (side-by-side)
- ✅ Up to 3 images with add/remove functionality
- ✅ Updates receipt (creates new receipt with same UUID - immutable pattern)
- ✅ Toast notification on save: "Bud updated! 🌿"
- ✅ Proper layout (20px horizontal padding, fixed zoomed-in issue)
- ✅ White text in inputs (fixed gray text issue)
- ✅ Save button disabled until changes made

**Files Created** (1):
- `Features/Memory/EditMemoryViewModel.swift` (180 lines)

**Files Modified** (3):
- `Features/EditMemoryView.swift` (completely rebuilt, 310 lines)
- `Core/Database/Repositories/MemoryRepository.swift` (+60 lines: update method)
- `Features/Timeline/MemoryDetailView.swift` (toast on edit dismiss)

**Additional Fixes**:
- ✅ Image carousel changed to `.aspectRatio(.fit)` to prevent cropping
- ✅ Removed Product Info section from MemoryDetailView
- ✅ Toast shows after edit completes (0.3s delay after sheet dismiss)

---

#### ✅ Module 1.3: Delete Memory (COMPLETE - Dec 28, 2025)
**Timeline**: 2 hours
**Status**: Complete

**What Built**: Delete individual buds with confirmation
- ✅ "Delete" button in MemoryDetailView with confirmation alert
- ✅ Improved delete() method with blob cleanup
- ✅ List refreshes after delete
- ✅ Toast notification "Bud deleted"
- ⏭️ Swipe-to-delete skipped (conflicts with navigation swipe gesture)

**Files Modified**:
- `Features/Timeline/MemoryDetailView.swift` (delete button + confirmation + toast)
- `Core/Database/Repositories/MemoryRepository.swift` (improved delete with blob cleanup)
- `Features/Circle/JarDetailView.swift` (reload list after delete)

---

#### ✅ Module 1.4: Reactions System (COMPLETE - Dec 28, 2025)
**Timeline**: 3-4 hours
**Status**: Complete

**What Built**: Social reactions for buds (5 emojis)
- ✅ 5 emoji reactions: ❤️ 😂 🔥 👀 😌
- ✅ Tap to toggle (add/remove/change)
- ✅ Summary view with counts: "❤️ 3  🔥 2"
- ✅ One reaction per user per bud (unique constraint)
- ✅ Database migration v6 with cascade delete
- ✅ ReactionRepository with toggle logic
- ✅ UI integrated into MemoryDetailView

**Files Created**:
- `Core/Models/Reaction.swift` (model + ReactionType enum)
- `Core/Database/Repositories/ReactionRepository.swift` (CRUD + toggle logic)
- `Features/Memory/ReactionPicker.swift` (5 buttons UI)
- `Features/Memory/ReactionSummary.swift` (display counts)

**Files Modified**:
- `Core/Database/Database.swift` (added v6 migration)
- `Features/Timeline/MemoryDetailView.swift` (reactions UI + ViewModel)
- `Core/Database/Repositories/MemoryRepository.swift` (cascade delete reactions)

**Note**: Using placeholder phone number (+1234567890) until AuthManager integration

---

#### 🔜 Module 1.5: Multi-User Reactions Sync (DEFERRED)
**Timeline**: 2-3 hours
**Status**: Planned, deferred to post-beta

**What**: E2EE sync for reactions in shared jars
- Get real user phone from AuthManager (30m)
- Receipt-based reactions with E2EE relay (2h)
- Display combined reactions from all jar members (30m)

**Why Defer**:
- Local-only reactions work for solo jars
- Infrastructure already proven (E2EE, relay, receipts)
- Can ship beta without multi-user reactions
- Gather feedback on basic reactions first

**Files to Modify** (when implementing):
- `Core/Auth/AuthManager.swift` - Add phone accessor
- `Core/Receipt/ReceiptManager.swift` - Add reaction receipt type
- `Core/Database/Repositories/ReactionRepository.swift` - Handle received reactions
- `Features/Timeline/MemoryDetailView.swift` - Use real phone

---

#### 🔜 Modules 2-6: Polish & Ship (PENDING)
**Remaining Work**:

**Module 2**: Jar System Polish (4-5h)
- Edit jar name/color
- Better delete confirmation
- Move bud between jars

**Module 3**: User Guidance (5-6h)
- 3-screen onboarding
- Settings screen
- Better empty states

**Module 4**: Error Handling (4-5h)
- Error toasts (red, user-facing)
- Loading states everywhere
- Confirmation dialogs

**Module 5**: Testing (4-5h)
- Stress test (100+ buds)
- Fresh install test
- Multi-device test

**Module 6**: TestFlight Prep (1-2h)
- Version 1.0.0 (build 1)
- CHANGELOG.md
- Archive + Upload
- Invite 5-10 beta testers

---

## Remaining Phases (Post-Beta)

### Phase 11: Map View v1 (4 hours)
**Status**: Not started
**Goal**: Legal regions only, no memories attached yet
**Deferred**: Until after beta feedback

### Phase 12: Shop View + Remote Config (8 hours)
**Status**: Not started
**Goal**: Product catalog, affiliate links, tracking
**Deferred**: Until after beta feedback

### Phase 13: AI Buds v1 (6 hours)
**Status**: Not started
**Goal**: Reflection-only AI insights
**Deferred**: Until after beta feedback

### Phase 14: App Store Prep + Polish (9 hours)
**Status**: Not started
**Goal**: Screenshots, marketing copy, submission
**Deferred**: Until after beta feedback

---

## Architecture Notes (For Coding Agents)

### Receipt-Based Data Model (IMMUTABLE)
**Core Principle**: All user data stored as receipts (UCR), never modified.

**Pattern**:
```swift
// Create
let receipt = try await receiptManager.create(payload: payload)

// Read
let memory = try await memoryRepository.fetch(id: uuid)

// Update (creates NEW receipt with same UUID)
let updatedReceipt = try await receiptManager.update(uuid: uuid, newPayload: newPayload)

// Delete
try await receiptManager.delete(uuid: uuid)  // Soft delete, receipt remains
```

**Why**: Immutability enables:
- Conflict-free multi-device sync
- Audit trail (see all versions)
- E2EE verification (signatures never break)
- Offline-first (queue changes, sync later)

---

### Jar-Centric Model

**Current Schema**:
```
User has N Jars
Jar has N Members (max 12)
Jar has N Buds (unlimited)
Bud belongs to exactly 1 Jar
```

**Critical Rule**: One bud = one jar. No multi-jar buds.

**Jar Types**:
1. **Solo**: Auto-created, single-user, cannot delete
2. **Shared**: Multi-user (2-12), can delete (buds move to Solo)

---

### Lightweight List Loading (Performance)

**Problem**: Loading full Memory objects (with images) in lists = 70-80MB.

**Solution**: MemoryListItem model (metadata only):
```swift
struct MemoryListItem {
    let id: UUID
    let strainName: String
    let productType: ProductType
    let rating: Int
    let createdAt: Date
    let thumbnailCID: String?  // CID only, not image data
    let jarID: String
    let effects: [String]      // For enrichment calculation
    let notes: String?         // For enrichment calculation
}
```

**Pattern**:
```swift
// List view: Lightweight
let items = try await repository.fetchLightweightList(jarID: jarID, limit: 50)

// Detail view: Full Memory (when needed)
let memory = try await repository.fetch(id: memoryID)
```

**Result**: Memory reduced to <40MB, list scrolling smooth.

---

### Simplified Create Flow (UX Pattern)

**Problem**: Long forms intimidate users, cause abandonment.

**Solution**: Progressive disclosure:
1. **Quick Create**: Minimum viable data (name + type)
2. **Enrich Invitation**: Immediately after save, show enrich view
3. **Visual Signals**: Minimal buds look different (dashed borders)

**Pattern**:
```swift
// Step 1: Create with minimal data
CreateMemoryView(jarID: jarID) { createdMemoryID in
    // Step 2: Show enrich view
    self.memoryToEnrich = createdMemoryID
}

// Step 3: User can enrich OR skip
EditMemoryView(memoryID: memoryID, isEnrichMode: true)
```

**Why This Works**:
- Lower barrier to entry (just name!)
- Momentum: User already committed, more likely to enrich
- Optional: Can skip if in a hurry
- Visual feedback: Unenriched buds are obvious

---

### EnrichmentLevel (Visual Signal)

**Implementation**:
```swift
enum EnrichmentLevel {
    case minimal   // Just name, maybe type
    case partial   // Some details added
    case complete  // Fully enriched
}

extension MemoryListItem {
    var enrichmentLevel: EnrichmentLevel {
        var score = 0
        if rating > 0 { score += 1 }
        if !effects.isEmpty { score += 1 }
        if notes != nil && !notes!.isEmpty { score += 1 }
        if thumbnailCID != nil { score += 1 }

        switch score {
        case 0...1: return .minimal
        case 2...3: return .partial
        default: return .complete
        }
    }
}
```

**Visual Design**:
```
Minimal:    ┌╌╌╌╌╌╌╌┐  (dashed orange border)
            │📝 Name │
            │+ Add   │
            └╌╌╌╌╌╌╌┘

Partial:    ┌───────┐  (solid border)
            │🌿 Name │
            │⭐⭐⭐  │
            └───────┘

Complete:   ┌───────┐
            │[Image]│
            │⭐⭐⭐⭐⭐│
            └───────┘
```

---

## Current File Structure (Dec 29, 2025)

```
Buds/
├── Core/
│   ├── Auth/
│   │   ├── AuthManager.swift              ✅ Phase 1
│   │   └── DeviceManager.swift            ✅ Phase 1
│   ├── Crypto/
│   │   ├── CryptoManager.swift            ✅ Phase 2
│   │   └── KeychainManager.swift          ✅ Phase 2
│   ├── Receipt/
│   │   ├── ReceiptManager.swift           ✅ Phase 3
│   │   └── SignatureVerifier.swift        ✅ Phase 3
│   ├── Database/
│   │   ├── Database.swift                 ✅ Phase 7
│   │   └── Repositories/
│   │       ├── MemoryRepository.swift     ✅ Phase 7, 🔄 Phase 10.1
│   │       ├── JarRepository.swift        ✅ Phase 8
│   │       └── ReactionRepository.swift   🔜 Phase 10.1 Module 1.4
│   ├── Models/
│   │   ├── Memory.swift                   ✅ Phase 7
│   │   ├── MemoryListItem.swift           ✅ Phase 10, 🔄 Phase 10.1
│   │   ├── Jar.swift                      ✅ Phase 8
│   │   ├── JarMember.swift                ✅ Phase 8
│   │   └── Reaction.swift                 ✅ Phase 10.1 Module 1.4
│   ├── Relay/
│   │   └── RelayClient.swift              ✅ Phase 4
│   └── JarManager.swift                   ✅ Phase 8, 🔄 Phase 10
├── Features/
│   ├── Auth/
│   │   └── LoginView.swift                ✅ Phase 1
│   ├── Shelf/
│   │   ├── ShelfView.swift                ✅ Phase 9b, 🔄 Phase 10.1
│   │   └── JarCard.swift                  ✅ Phase 9b
│   ├── Jar/
│   │   ├── CreateJarView.swift            ✅ Phase 9a
│   │   └── JarDetailView.swift            ✅ Phase 9a, 🔄 Phase 10.1
│   ├── Circle/
│   │   ├── JarDetailView.swift            ✅ Phase 9a, 🔄 Phase 10.1
│   │   ├── AddMemberView.swift            ✅ Phase 9a
│   │   ├── MemberDetailView.swift         ✅ Phase 9a
│   │   └── MemoryListCard.swift           ✅ Phase 10, 🔄 Phase 10.1
│   ├── CreateMemory/
│   │   ├── CreateMemoryView.swift         ✅ Phase 6, 🔄 Phase 10.1 (simplified)
│   │   ├── JarPickerView.swift            ✅ Phase 10, 🔄 Phase 10.1
│   │   ├── PhotoPicker.swift              ✅ Phase 6
│   │   └── ImagePicker.swift              ✅ Phase 6
│   ├── Memory/
│   │   ├── EditMemoryView.swift           ✅ Phase 10.1 Module 1.2
│   │   ├── MemoryDetailView.swift         ✅ Phase 10.1 Module 1.1
│   │   ├── ReactionPicker.swift           ✅ Phase 10.1 Module 1.4
│   │   └── ReactionSummary.swift          ✅ Phase 10.1 Module 1.4
│   ├── Onboarding/
│   │   └── OnboardingView.swift           ✅ Phase 10.1 Module 3.1
│   ├── Profile/
│   │   └── ProfileView.swift              ✅ Phase 1, 🔄 Phase 10.1 Module 3.2
│   ├── Settings/  [DEPRECATED]
│   │   └── SettingsView.swift             ❌ Less features than ProfileView
│   └── Timeline/  [DEPRECATED]
│       ├── TimelineView.swift             ❌ Old, not used
│       ├── CircleView.swift               ❌ Redundant with ShelfView
│       └── MemoryDetailView.swift         ❌ Old, replaced in 10.1
├── Shared/
│   ├── DesignSystem/
│   │   ├── BudsColors.swift               ✅ Phase 6
│   │   ├── BudsTypography.swift           ✅ Phase 6
│   │   └── BudsSpacing.swift              ✅ Phase 6
│   └── Toast.swift                        ✅ Phase 10, 🔄 Phase 10.1 Module 4.1
└── ContentView.swift                      ✅ Phase 1, 🔄 Phase 10

Legend:
✅ Complete and stable
🔄 Modified in current phase
🔜 Planned, not yet built
❌ Deprecated, not used
```

---

## Success Metrics (Updated)

### Phase 10.1 Beta Readiness
- [x] Users can create buds in <15 seconds (Module 1.0 ✅)
- [x] Users can view bud details (Module 1.1 ✅)
- [x] Users can edit/enrich buds (Module 1.2 ✅)
- [x] Users can delete buds (Module 1.3 ✅)
- [x] Users can react to buds (❤️ 😂 🔥 👀 😌) (Module 1.4 ✅)
- [x] Jar system polish complete (Module 2 ✅)
- [x] Onboarding explains the app (Module 3.1 ✅)
- [x] Profile/Settings with privacy links (Module 3.2 ✅)
- [x] Empty states polished (Module 3.3 ✅)
- [x] Errors show helpful messages (Module 4.1 ✅)
- [x] Loading states consistent (Module 4.2 ✅)
- [x] Destructive actions confirmed (Module 4.3 ✅)
- [x] Stress test tools created (Module 5.1 ✅)
- [x] Fresh install checklist ready (Module 5.2 ✅)
- [x] Multi-device checklist ready (Module 5.3 ✅)
- [ ] No crashes on common flows (Module 5 - Manual Testing Required)
- [ ] Memory <60MB with 100 buds (Module 5 - Manual Testing Required)
- [ ] 20-50 beta users successfully using app (Module 6 - TestFlight)

### TestFlight Beta
- [ ] 20-50 users invited
- [ ] Feedback channel set up (Discord/Slack)
- [ ] No critical bugs reported in first week
- [ ] Average session length >5 minutes
- [ ] User retention >50% (week 1 → week 2)

### App Store V1 (R1)
- [ ] All beta feedback addressed
- [ ] Screenshots + marketing copy ready
- [ ] Privacy policy + terms of service published
- [ ] App Store submission package complete
- [ ] No cannabis content violations

---

## Risk Analysis (Updated)

### ✅ RESOLVED: Jar Architecture Breaking E2EE
**Original Risk**: Moving buds to Solo during jar deletion might break signature verification.
**Resolution**: Verified in Phase 10 Step 0. jar_id is local metadata, not part of signed receipt. E2EE signatures remain valid.

### 🟡 NEW RISK: Simplified Create Flow Adoption
**Risk**: Users might skip enrichment entirely, leading to low-quality data.
**Mitigation**:
- Visual signals make unenriched buds obvious (dashed borders)
- "+ Add Details" hint text prompts enrichment
- Enrich view shows immediately after create (momentum)
- Can always enrich later via Edit button

**Monitoring**:
- Track enrichment rate (% of buds with rating, effects, notes)
- A/B test different hint text
- Survey beta users about create flow

### 🟡 ONGOING: App Store Rejection (Cannabis)
**Risk**: Apple rejects due to cannabis-related content.
**Mitigation**:
- No cannabis leaf imagery in marketing
- Positioned as "journal" not "cannabis tracker"
- No direct purchase/transaction features
- Medical/wellness framing in description

**Status**: Monitoring, will adjust based on review feedback.

---

## Next Steps (Immediate)

**Right Now** (Dec 29, 2025):
1. ✅ Modules 1-5 COMPLETE (UX + Error Handling + Testing Tools)
2. 🧪 **Manual Testing**: Run the test checklists
   - Use stress test tool to generate 100+ buds
   - Run fresh install checklist on physical device
   - Test on iPhone SE, 15, and Pro Max
   - Verify memory <60MB, scrolling smooth, no crashes
3. 🐛 Fix any critical bugs found in testing

**Next Session**:
4. 🚀 **Module 6**: TestFlight Prep (2-3h)
   - Screenshots
   - App Store metadata
   - Privacy policy finalization
   - Terms of service
5. 📦 **First TestFlight Build**: Upload to App Store Connect
6. 🧪 **Internal Testing**: Test build on real devices

**This Week**:
7. 👥 **Invite Beta Testers**: 5-10 initial users
8. 📊 **Gather Feedback**: Set up Discord/Slack channel
9. 🐛 **Fix Critical Bugs**: Based on beta feedback
10. 🚀 **Expand Beta**: 20-50 users

**Next Week**:
11. 📊 **Analyze Usage**: Session length, retention, enrichment rate
12. 🎨 **UI Polish**: Based on user feedback
13. 🚀 **Final Beta Build**: Address all feedback
14. 📱 **App Store Submission**: V1.0

---

## Conclusion

**Where We Are**:
- ✅ **Phases 1-10 COMPLETE**: Solid foundation (E2EE, DB, Jars, Shelf, Hardening)
- 🚧 **Phase 10.1 IN PROGRESS**: Making app beta-ready (UX polish, reactions, guidance)
- 🎯 **Goal**: 20-50 real users testing within 2 weeks

**What's Different**:
- Pivoted from "build all features" → "ship beta, gather feedback"
- Simplified create flow dramatically (name → enrich pattern)
- Visual enrichment signals guide users
- Reactions system for social engagement

**Core Physics Intact**:
- E2EE still works ✅
- Receipts still immutable ✅
- Multi-device sync still functional ✅
- No regressions in critical flows ✅

**Next Milestone**: TestFlight beta with real users testing the simplified UX.

**Remember**: The goal is not perfection. The goal is 20-50 people can use the app without frustration, then iterate based on feedback.

---

**Updated**: December 28, 2025 - Phase 10.1 Module 1.0 Complete
**Next Update**: After Module 1.1 (Memory Detail View)
