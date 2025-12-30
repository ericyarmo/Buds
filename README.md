# Buds v1.0 🌿

**Private cannabis memory journal with E2EE sharing for up to 12 friends**

Built on receipt-first, local-first, privacy-by-default principles.

---

## Project Status

**Current Build:** ✅ Phases 1-10 Complete | 🚧 Phase 10.1 In Progress (Beta Readiness)
**Date:** December 29, 2025
**Version:** 1.0.0 (Beta)
**Bundle ID:** `app.getbuds.buds`

**Latest Milestone:** Phase 10.1 Modules 1-5 Complete ✅
**Next Up:** Module 6 - TestFlight Prep
**Goal:** TestFlight beta with 20-50 real users → Gather feedback → App Store

---

## Quick Start (Coding Agents)

### Essential Reading (In Order)

1. **[`R1_MASTER_PLAN_UPDATED.md`](./docs/planning/R1_MASTER_PLAN_UPDATED.md)** ← **START HERE**
   - Complete project status (what's built, what's next)
   - All architecture patterns for agents
   - Phase-by-phase implementation history
   - Current file structure with status

2. **[`PHASE_10.1_BETA_READINESS.md`](./docs/planning/PHASE_10.1_BETA_READINESS.md)**
   - Current work in progress
   - Module 1.0 complete (simplified create flow)
   - Modules 1.1-1.4 specs (detail view, edit, delete, reactions)

3. **[`CANONICALIZATION_SPEC.md`](./docs/CANONICALIZATION_SPEC.md)** ← **CRITICAL**
   - Receipt signing implementation
   - Unsigned preimage pattern
   - CBOR encoding rules

4. **[`DATABASE_SCHEMA.md`](./docs/DATABASE_SCHEMA.md)**
   - GRDB schema (current migration: v5)
   - Tables: jars, jar_members, local_receipts, ucr_headers, blobs, reactions

5. **[`E2EE_DESIGN.md`](./docs/E2EE_DESIGN.md)**
   - X25519 key agreement + AES-256-GCM
   - Multi-device encryption
   - Verified in Phase 10 (signatures still valid after jar deletion)

---

## Current Architecture (Dec 28, 2025)

### Receipt-Based Data Model (IMMUTABLE)

Every event is a signed, content-addressed receipt:

```swift
struct UCRHeader {
    let cid: String              // CIDv1 (dag-cbor, sha2-256)
    let did: String              // Author DID
    let parentCID: String?       // Edit chain parent (CAUSAL TRUTH)
    let rootCID: String          // First version in chain
    let receiptType: String      // app.buds.session.created/v1
    let payload: ReceiptPayload  // Strongly-typed (contains claimed_time_ms)
    let signature: String        // Ed25519 (base64)
}
```

**Key Principle:** Causality (parentCID) = truth. Time (claimed_time_ms) = claim.

**CRUD Pattern:**
```swift
// Create
let receipt = try await receiptManager.create(payload: payload)

// Read
let memory = try await memoryRepository.fetch(id: uuid)

// Update (creates NEW receipt with same UUID)
let updated = try await receiptManager.update(uuid: uuid, newPayload: newPayload)

// Delete (soft delete, receipt remains)
try await receiptManager.delete(uuid: uuid)
```

**Why Immutable:** Enables E2EE verification, conflict-free sync, audit trails.

---

### Jar-Centric Model

**Schema:**
```
User has N Jars
Jar has N Members (max 12)
Jar has N Buds (unlimited)
Bud belongs to exactly 1 Jar
```

**Critical Rule:** One bud = one jar. No multi-jar buds.

**Jar Types:**
1. **Solo**: Auto-created, single-user, cannot delete
2. **Shared**: Multi-user (2-12), can delete (buds move to Solo)

---

### Lightweight List Loading (Performance)

**Problem:** Loading full Memory objects in lists = 70-80MB.

**Solution:** MemoryListItem model (metadata only):

```swift
struct MemoryListItem {
    let id: UUID
    let strainName: String
    let productType: ProductType
    let rating: Int
    let createdAt: Date
    let thumbnailCID: String?    // CID only, not image data
    let jarID: String
    let effects: [String]        // For enrichment calculation
    let notes: String?           // For enrichment calculation
}
```

**Pattern:**
```swift
// List view: Lightweight
let items = try await repository.fetchLightweightList(jarID: jarID, limit: 50)

// Detail view: Full Memory (when needed)
let memory = try await repository.fetch(id: memoryID)
```

**Result:** Memory <40MB, smooth 60fps scrolling.

---

### Simplified Create Flow (Progressive Disclosure)

**Problem:** Long forms intimidate users, cause abandonment.

**Solution:** Create fast → Enrich later.

**Pattern:**
```swift
// Step 1: Create with minimal data (name + type)
CreateMemoryView(jarID: jarID) { createdMemoryID in
    // Step 2: Immediately show enrich view
    self.memoryToEnrich = createdMemoryID
}

// Step 3: User can enrich OR skip
EditMemoryView(memoryID: memoryID, isEnrichMode: true)
```

**Visual Enrichment Signals:**
```swift
enum EnrichmentLevel {
    case minimal   // Just name, maybe type (dashed orange border)
    case partial   // Some details added (solid border)
    case complete  // Fully enriched (thumbnail image)
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

**Why This Works:** Lower barrier to entry, momentum-based enrichment, visual feedback.

---

## Tech Stack

| Component | Technology | Why |
|-----------|-----------|-----|
| Language | Swift 6 | Latest features, concurrency |
| UI | SwiftUI | Declarative, native performance |
| Database | GRDB | Production SQLite wrapper |
| Crypto | CryptoKit | Apple native (Ed25519, X25519, AES) |
| Auth | Firebase Auth | Phone verification |
| Backend | Cloudflare Workers | Edge compute, E2EE relay |
| Storage | Cloudflare R2 | Object storage for encrypted payloads |

---

## File Structure (Dec 28, 2025)

```
Buds/
├── Core/
│   ├── Auth/
│   │   ├── AuthManager.swift           ✅ Phase 1
│   │   └── DeviceManager.swift         ✅ Phase 1
│   ├── Crypto/
│   │   ├── CryptoManager.swift         ✅ Phase 2
│   │   └── KeychainManager.swift       ✅ Phase 2
│   ├── Receipt/
│   │   ├── ReceiptManager.swift        ✅ Phase 3
│   │   └── SignatureVerifier.swift     ✅ Phase 3
│   ├── Database/
│   │   ├── Database.swift              ✅ Phase 7 (migration v5 current)
│   │   └── Repositories/
│   │       ├── MemoryRepository.swift  ✅ Phase 7, 🔄 Phase 10.1
│   │       ├── JarRepository.swift     ✅ Phase 8
│   │       └── ReactionRepository.swift 🔜 Phase 10.1 Module 1.4
│   ├── Models/
│   │   ├── Memory.swift                ✅ Phase 7
│   │   ├── MemoryListItem.swift        ✅ Phase 10, 🔄 Phase 10.1
│   │   ├── Jar.swift                   ✅ Phase 8
│   │   ├── JarMember.swift             ✅ Phase 8
│   │   └── Reaction.swift              🔜 Phase 10.1 Module 1.4
│   ├── Relay/
│   │   └── RelayClient.swift           ✅ Phase 4
│   └── JarManager.swift                ✅ Phase 8, 🔄 Phase 10
├── Features/
│   ├── Auth/
│   │   └── LoginView.swift             ✅ Phase 1
│   ├── Shelf/
│   │   ├── ShelfView.swift             ✅ Phase 9b, 🔄 Phase 10.1
│   │   └── JarCard.swift               ✅ Phase 9b
│   ├── Circle/
│   │   ├── JarDetailView.swift         ✅ Phase 9a, 🔄 Phase 10.1
│   │   ├── AddMemberView.swift         ✅ Phase 9a
│   │   ├── MemberDetailView.swift      ✅ Phase 9a
│   │   └── MemoryListCard.swift        ✅ Phase 10, 🔄 Phase 10.1
│   ├── CreateMemory/
│   │   ├── CreateMemoryView.swift      ✅ Phase 6, 🔄 Phase 10.1 (simplified)
│   │   ├── JarPickerView.swift         ✅ Phase 10, 🔄 Phase 10.1
│   │   ├── PhotoPicker.swift           ✅ Phase 6
│   │   └── ImagePicker.swift           ✅ Phase 6
│   ├── Memory/
│   │   ├── EditMemoryView.swift        🔜 Phase 10.1 Module 1.2
│   │   ├── ReactionPicker.swift        🔜 Phase 10.1 Module 1.4
│   │   └── ReactionSummary.swift       🔜 Phase 10.1 Module 1.4
│   └── Timeline/
│       └── MemoryDetailView.swift      ✅ Phase 10.1 Module 1.1 (active)
├── Shared/
│   ├── DesignSystem/
│   │   ├── BudsColors.swift            ✅ Phase 6
│   │   ├── BudsTypography.swift        ✅ Phase 6
│   │   └── BudsSpacing.swift           ✅ Phase 6
│   └── Toast.swift                     ✅ Phase 10
└── ContentView.swift                   ✅ Phase 1, 🔄 Phase 10

Legend:
✅ Complete and stable
🔄 Modified in current phase
🔜 Planned, not yet built
❌ Deprecated, not used
```

---

## What's Working (Phases 1-10 Complete)

### ✅ Core Infrastructure
- E2EE encryption (X25519 + AES-256-GCM)
- Receipt-based data model (immutable, verifiable)
- GRDB database (migration v5)
- Blob storage for images
- Multi-device sync
- Cloudflare relay (E2EE message relay)

### ✅ Features
- Phone auth (Firebase)
- Create bud flow (simplified: name + type)
- Jar system (Solo + Shared, max 12 members)
- Jar CRUD (create, delete, view)
- Member management (add, remove, roles)
- Shelf grid view (home)
- Memory list cards (lightweight, <40MB)
- Pull-to-refresh
- Toast notifications
- Haptic feedback

### ✅ Design System
- BudsColors, BudsTypography, BudsSpacing
- Dark mode throughout
- Consistent UI components

---

## What's In Progress (Phase 10.1)

### ✅ Module 1.0: Simplified Create Flow (COMPLETE)
- Reduced create form to 2 fields (name + type)
- Auto-shows enrich view after save
- Visual enrichment signals (dashed orange borders for minimal buds)
- Pencil icon for unenriched buds
- "+ Add Details" hint text

### ✅ Module 1.1: Memory Detail View (COMPLETE)
- Full-screen bud detail with black background
- Image carousel (swipeable)
- All metadata display (strain, type, rating, notes, effects, product details)
- Edit button wired to EditMemoryView
- Delete button with confirmation
- Navigation from MemoryListCard tap

### ✅ Module 1.2: Edit Memory (Enrich) (COMPLETE)
- Full edit form (rating, effects, notes, images)
- 12 common effects checkboxes
- Camera + photo library options
- Pre-fills existing data
- Updates receipt (immutable pattern)
- Toast on save success
- Proper layout (20px horizontal padding)

### ✅ Module 1.3: Delete Memory (COMPLETE)
- Delete button in detail view with confirmation
- Cleans up blobs (images) and database entries
- Toast notification on delete
- List refreshes after delete
- Note: Swipe-to-delete skipped (conflicts with nav gesture)

### ✅ Module 1.4: Reactions System (COMPLETE)
- 5 emoji reactions: ❤️ 😂 🔥 👀 😌
- Tap to toggle (add/remove/change)
- Summary view with counts (e.g., "❤️ 3  🔥 2")
- Database table with migration (v6)
- ReactionRepository for CRUD
- Cascade delete with memories
- UI components: ReactionPicker + ReactionSummaryView
- Note: Local-only, uses placeholder phone (multi-user sync deferred)

### 🔜 Module 1.5: Multi-User Reactions Sync (DEFERRED)
- Receipt-based reactions for E2EE shared jars
- Get real user phone from AuthManager
- Sync via relay (same pattern as memories)
- Display combined reactions from all jar members
- Deferred: Can ship beta without this, add after feedback

### ✅ Module 2: Jar System Polish (COMPLETE)
- Custom mason jar icon with lid + leaf inside
- Edit jar (context menu → Edit → change name/description)
- Delete confirmation already shows bud count (✅ was already done!)
- Move bud between jars (Move button → select jar → toast)
- Toast notifications for create/edit/delete/move operations

### ✅ Module 3: User Guidance (COMPLETE)
- **3.1 Onboarding**: 3-screen first-launch flow (Welcome, Jars, Privacy)
- **3.2 Profile/Settings**: Account info, privacy links, dev tools, E2EE test
- **3.3 Empty States**: Consistent empty states across Shelf, Jar detail, Members
- Tab bar simplified to 2 tabs (Shelf + Profile)
- ProfileView enhanced with Privacy Policy and Terms links

### ✅ Module 4: Error Handling & Feedback (COMPLETE)
- **4.1 Error Toasts**: Tap-to-dismiss, 5s duration, 90% opacity red backgrounds
- **4.2 Loading States**: All views show "Loading..." with .budsPrimary spinner
- **4.3 Confirmation Dialogs**: All destructive actions confirmed (delete jar/bud/member, reset data)
- Toast system enhanced with auto-durations (5s errors, 2s success)

### ✅ Module 5: Performance & Testing (COMPLETE)
- **5.1 Stress Testing**: Tool to generate 100+ test buds, performance monitoring
- **5.2 Fresh Install**: 10-step checklist for first-time user experience
- **5.3 Multi-Device**: Testing across iPhone SE, 15, Pro Max
- Stress test generator accessible from Profile → Debug section

---

## Phase History (Summary)

| Phase | Status | What Was Built |
|-------|--------|----------------|
| **1-7** | ✅ Complete | Foundation (Auth, E2EE, Receipts, DB, Images, Relay, Signatures) |
| **8** | ✅ Complete | Jar Model (migrated from Circle, added jars + jar_members tables) |
| **9a** | ✅ Complete | Jar Management (CRUD, member management, roles) |
| **9b** | ✅ Complete | Shelf View (grid layout, replaced Timeline) |
| **10** | ✅ Complete | Production Hardening (E2EE verified, memory optimized, toast, haptics) |
| **10.1** | 🚧 In Progress | Beta Readiness (simplified UX, reactions, polish) - **Modules 1-5 done** |
| **11-14** | 🔜 Planned | Map, Shop, AI, App Store Prep (deferred until after beta feedback) |

**See [`R1_MASTER_PLAN_UPDATED.md`](./docs/planning/R1_MASTER_PLAN_UPDATED.md) for complete phase details.**

---

## Development Setup

### 1. Clone & Open

```bash
git clone <repo_url>
cd Buds
open Buds.xcodeproj
```

### 2. Install Dependencies (SPM)

- **GRDB**: `https://github.com/groue/GRDB.swift`
- **Firebase**: `https://github.com/firebase/firebase-ios-sdk`

### 3. Configure Services

- Firebase project (phone auth + push)
- Cloudflare Workers account (relay server)
- See [`buds-relay/README.md`](../buds-relay/README.md) for relay setup

### 4. Build & Run

```bash
# Clean build
Cmd+Shift+K

# Build
Cmd+B

# Run on simulator
Cmd+R
```

---

## Testing

### Current Test Focus (Phase 10.1 Module 1.0)

1. **Simplified Create Flow**
   - Tap FAB → Select jar → Enter name → Continue → Enrich view appears
   - Skip enrichment → Toast appears → Bud created

2. **Visual Enrichment Signals**
   - Minimal buds show dashed orange border
   - Pencil icon instead of thumbnail
   - "+ Add Details" hint text

3. **Performance**
   - Memory <40MB with 10+ buds
   - Smooth 60fps scrolling in jar lists

**See test plan in [`PHASE_10.1_BETA_READINESS.md`](./docs/planning/PHASE_10.1_BETA_READINESS.md)**

---

## Security & Privacy

**Threat Model:** See [`PRIVACY_ARCHITECTURE.md`](./docs/PRIVACY_ARCHITECTURE.md)

**Key Principles:**
- E2EE for jar sharing (server sees only ciphertext)
- Local-first (data never leaves device unless shared)
- Location OFF by default
- No PII in receipts (DIDs are cryptographic, not personal)
- Multi-device support with per-device key wrapping

**E2EE Verification:** ✅ Tested in Phase 10 - Signatures remain valid after jar deletion.

---

## Legal

- **Age:** 21+ only (federally illegal in US)
- **Disclaimer:** No medical advice, no sales facilitation
- **Privacy:** GDPR/CCPA-compliant design

---

## Roadmap

**Current Milestone:** TestFlight beta with 20-50 real users (2 weeks)

**Next Steps:**
1. ✅ Module 1.0: Simplified Create (DONE)
2. 🔜 Module 1.1: Memory Detail View
3. 🔜 Module 1.2: Edit Memory (Enrich)
4. 🔜 Module 1.3: Delete Memory
5. 🔜 Module 1.4: Reactions System
6. 🔜 Modules 2-6: Polish + TestFlight upload

**Post-Beta:**
- Phase 11: Map View
- Phase 12: Shop View
- Phase 13: AI Buds
- Phase 14: App Store Launch

**Goal:** Ship beta → Gather feedback → Iterate → App Store.

---

## Contributing

Private project. Architecture by Claude (Anthropic) + Eric.

---

## Build Progress Tracker

**Last Updated:** December 28, 2025
**Current Phase:** Phase 10.1 (Beta Readiness)
**Latest Commit:** Module 2 - Jar System Polish ✅

**Next Session:** User Guidance (Module 3)

---

**For detailed implementation context, always start with [`R1_MASTER_PLAN_UPDATED.md`](./docs/planning/R1_MASTER_PLAN_UPDATED.md)**
