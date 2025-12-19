# Buds v0.1 🌿

**Private cannabis memory sharing for you and up to 12 close friends**

Built on ChaingeOS principles: receipts-first, local-first, privacy by default.

---

## Project Status

🚀 **LIVE ON TESTFLIGHT** - Phase 4 Complete (December 19, 2025)

**Current Build:** v1.0 (Build 1) - Approved for external testing (10k users)
**Bundle ID:** `app.getbuds.buds`
**Latest:** Firebase Auth + Profile working
**Next Up:** Circle Mechanics (Phase 5) - See [PHASE_5_PLAN.md](./PHASE_5_PLAN.md)

---

## Quick Start

### 1. Read the Docs (Recommended Order)

All architecture documentation is in [`/docs/`](./docs/). **Read in this order:**

#### **Phase 1: Understanding the System (Critical - Read First)**

1. **[`ARCHITECTURE.md`](./docs/ARCHITECTURE.md)** - System overview, principles, layers
   - Start here for the big picture
   - Understand causality-first architecture (parentCID = truth, time = claim)

2. **[`CANONICALIZATION_SPEC.md`](./docs/CANONICALIZATION_SPEC.md)** - Receipt signing (CRITICAL)
   - **Must read carefully** - Defines exact bytes signed/hashed
   - Unsigned preimage pattern avoids CID/signature circularity
   - Strongly-typed payloads with `claimed_time_ms`

3. **[`DATABASE_SCHEMA.md`](./docs/DATABASE_SCHEMA.md)** - GRDB schema
   - Skim tables, understand `ucr_headers` vs `local_receipts`
   - Note: `received_at` for ordering, `claimed_time_ms` in payload

4. **[`RECEIPT_SCHEMAS.md`](./docs/RECEIPT_SCHEMAS.md)** - All receipt types
   - Reference as needed (don't memorize)
   - All payloads have `claimed_time_ms` (author's time claim)

#### **Phase 2: Feature Deep Dives (Skim, Read When Implementing)**

5. **[`E2EE_DESIGN.md`](./docs/E2EE_DESIGN.md)** - Circle sharing encryption
   - X25519 key agreement + AES-GCM
   - Multi-device key wrapping

6. **[`PRIVACY_ARCHITECTURE.md`](./docs/PRIVACY_ARCHITECTURE.md)** - Location privacy
   - Fuzzy grid snapping, delayed sharing
   - OFF by default

7. **[`AGENT_INTEGRATION.md`](./docs/AGENT_INTEGRATION.md)** - Cannabis expert AI
   - DeepSeek/Qwen integration (20x cheaper than Claude)
   - Read-only queries with citations

8. **[`UX_FLOWS.md`](./docs/UX_FLOWS.md)** - User flows & wireframes
   - Reference when building UI

#### **Phase 3: Backend & Business (Backend Developers)**

9. **[`RELAY_SERVER.md`](./docs/RELAY_SERVER.md)** - Cloudflare Workers API
   - E2EE message relay (server sees only ciphertext)
   - Device registration, message delivery

10. **[`DISPENSARY_INSIGHTS.md`](./docs/DISPENSARY_INSIGHTS.md)** - B2B product
    - Deals-based revenue model ($99-599/month tiers)
    - K-anonymity threshold (n≥75)

#### **Phase 4: Implementation (When Ready to Build)**

11. **[`DEVELOPMENT_ROADMAP.md`](./docs/DEVELOPMENT_ROADMAP.md)** - 4-week build plan
    - Phase 0: Foundation (2-3 days)
    - Phase 1: Core Kernel (4-5 days)
    - Phase 2-7: UI, Location, Circle, Agent, Polish

---

**tl;dr - Absolute minimum:**
- Read: `ARCHITECTURE.md` (30 min)
- Read carefully: `CANONICALIZATION_SPEC.md` (30 min)
- Skim: `DATABASE_SCHEMA.md` (15 min)
- Reference others as needed

### 2. Set Up Project

```bash
# Clone repo (after creating on GitHub)
git clone <repo_url>
cd Buds

# Open in Xcode (create project first)
open Buds.xcodeproj
```

### 3. Install Dependencies

**Swift Package Manager (SPM):**
- GRDB: `https://github.com/groue/GRDB.swift`
- Firebase: `https://github.com/firebase/firebase-ios-sdk`

**External Services:**
- Firebase project (phone auth + push)
- Cloudflare Workers account (relay server)
- LLM API key (Agent: DeepSeek/Qwen/Claude - see AGENT_INTEGRATION.md)

### 4. Follow the Roadmap

See [`DEVELOPMENT_ROADMAP.md`](./docs/DEVELOPMENT_ROADMAP.md) for detailed phase breakdown.

**Quick overview:**
- **Week 1:** Foundation + Core Kernel
- **Week 2:** UI + Location + Map
- **Week 3-4:** Circle + E2EE + Agent
- **Week 4:** Polish + TestFlight

---

## Architecture Highlights

### Causality-First Receipt Architecture
Every event is a signed, content-addressed receipt (UCRHeader):
```swift
struct UCRHeader {
    let cid: String                    // CIDv1 (dag-cbor, sha2-256)
    let did: String                    // Author DID
    let parentCID: String?             // Edit chain parent (CAUSAL TRUTH)
    let rootCID: String                // First version in chain
    let receiptType: String            // app.buds.session.created/v1
    let payload: ReceiptPayload        // Strongly-typed (contains claimed_time_ms)
    let signature: String              // Ed25519 (base64)
    // NO timestamp! Time is in payload as claimed_time_ms (author's claim, not truth)
}
```

**Key principle:** Causality (parentCID chains) = verifiable truth. Time (claimed_time_ms) = unverifiable claim.

### Local-First Storage
- **GRDB (SQLite)** for local persistence
- **Optimistic updates** (UI updates immediately, sync background)
- **Offline-first** (full functionality without network)

### E2EE Circle Sharing
- **X25519 key agreement** for key wrapping
- **AES-256-GCM** for payload encryption
- **Device-based keys** (multi-device support)
- **Max 12 members** (manageable key distribution)

### Privacy by Default
- **Location OFF** by default
- **Fuzzy locations** for Circle sharing (~500m grid)
- **Explicit consent** for every share
- **E2EE relay** (server sees only ciphertext)

---

## Tech Stack

| Component | Technology | Why |
|-----------|-----------|-----|
| Language | Swift 6 | Latest features, concurrency |
| UI | SwiftUI | Declarative, native |
| Database | GRDB | Production SQLite wrapper |
| Crypto | CryptoKit | Apple's native (Ed25519, X25519, AES) |
| Auth | Firebase Auth | Phone verification |
| Backend | Cloudflare Workers | Edge compute, E2EE relay |
| Agent | Pluggable LLM | DeepSeek/Qwen recommended (20x cheaper than Claude) |

---

## Project Structure

```
Buds/
├── docs/                   # Architecture documentation (YOU ARE HERE)
├── Buds/                   # iOS app (create in Xcode)
│   ├── App/
│   ├── Core/
│   │   ├── ChaingeKernel/
│   │   ├── Database/
│   │   └── Models/
│   ├── Features/
│   │   ├── Timeline/
│   │   ├── Map/
│   │   ├── Circle/
│   │   └── Agent/
│   └── Shared/
└── worker/                 # Cloudflare Workers (relay server)
```

---

## Key Architectural Fixes

✅ **Causality-first** - parentCID chains = truth, time = claim (in payload as claimed_time_ms)
✅ **CID/signature circularity** - Unsigned preimage pattern avoids circular dependency
✅ **Deterministic CBOR** - Strongly-typed payloads, sorted keys, Int64 timestamps
✅ **Device vs DID** - Multi-device model with per-device key wrapping
✅ **Append-only** - Edits create new receipts, deletions create tombstones (no mutations)

---

## Contributing

This is a private project (for now). Architecture by Claude (Anthropic) + Eric. Vaksman will be coming soon...

---

## Security

**Threat model:** See [`PRIVACY_ARCHITECTURE.md`](./docs/PRIVACY_ARCHITECTURE.md)

**Key principles:**
- E2EE for Circle sharing
- Local-first (data never leaves device unless shared)
- Relay server is untrusted (sees only ciphertext)
- **No PII in receipts**: Phone numbers live only in Firebase Auth layer; receipts never include phone/email/name. Circle uses local nicknames (displayName) stored only on your device. DIDs are derived from cryptographic keys, not personal identifiers.

---

## Legal

**Age:** 21+ only (federally illegal in US)
**Disclaimer:** No medical advice, no sales facilitation
**Privacy:** Designed for GDPR/CCPA compliance; export/delete/portability planned in v0.2+

---

## Build Progress

### Phase 0: Foundation ✅
- ✅ Architecture documentation complete (11 docs)
- ✅ Project structure created
- ✅ Core files wired (18 production files)
- ✅ `.gitignore` + build guides configured

### Phase 1: Core Kernel ✅ (Physics-Tested)
- ✅ **IdentityManager** - Ed25519/X25519 keypairs + DID generation + Keychain storage
- ✅ **CBOREncoder** - **Physics-tested canonical CBOR (0.11ms p50)** from BudsKernelGolden
- ✅ **CBORCanonical** - RFC 8949 compliant encoder with lexicographic key sorting
- ✅ **ReceiptCanonicalizer** - Struct-to-CBOR converter for deterministic encoding
- ✅ **ReceiptManager** - Create/sign receipts with unsigned preimage pattern
- ✅ **Database** - GRDB with all 7 tables + migrations
- ✅ **Models** - UCRHeader, SessionPayload, Memory (user-facing)
- ✅ **MemoryRepository** - GRDB queries (fetch/create/update/delete)

### Phase 2: UI Foundation ✅
- ✅ **Design System** - Colors, Typography, Spacing (16 colors, 5 fonts)
- ✅ **MainTabView** - Tab navigation (Timeline, Map, Circle, Profile)
- ✅ **TimelineView** - Empty state + memory list with pull-to-refresh
- ✅ **CreateMemoryView** - Full form (strain, rating, effects, notes, details)
- ✅ **MemoryCard** - Production-ready card component with all fields
- ✅ **EffectTag** - Color-coded effect chips

### Phase 3: Image Support + Memory Enhancement ✅
- ✅ **Multi-Image Support** - Up to 3 photos per memory (camera + library)
- ✅ **Photo Picker** - Camera flip, multi-select, compression (2MB max)
- ✅ **Image Carousel** - Swipeable with page indicators
- ✅ **Photo Management** - Reorder, delete, visual feedback
- ✅ **Memory Detail View** - Hero images, card layout, better hierarchy
- ✅ **Timeline Enhancement** - Image previews, gradient headers
- ✅ **Database Migration v2** - image_cid → image_cids (JSON array)
- ✅ **Blob Storage** - CID-based image retrieval

**See [PHASE_3_COMPLETE.md](./PHASE_3_COMPLETE.md)** for full Phase 3 details.

### Current Status: 🚀 **LIVE ON TESTFLIGHT** (Dec 18, 2025)

**What's working:**
- ✅ Create memory with up to 3 photos
- ✅ Swipeable image carousel with page indicators
- ✅ Photo reordering with visual feedback
- ✅ Full memory timeline with image previews
- ✅ Receipt signing with Ed25519 (physics-tested)
- ✅ Production CBOR encoder (0.11ms p50 latency)
- ✅ All UI components styled and functional

**TestFlight:**
- Build: v1.0 (Build 1)
- Status: Approved for external testing
- Testers: Up to 10,000 external testers
- Bundle ID: `app.getbuds.buds`

### Phase 4: Firebase Auth + Profile ✅ (COMPLETE - Dec 19, 2025)
- ✅ Firebase Phone Authentication (SMS verification)
- ✅ APNs integration for silent push
- ✅ AuthManager with phone verification flow
- ✅ ProfileView with editable display name
- ✅ Identity section (DID + Firebase UID)
- ✅ Storage info + account settings
- ✅ Sign out / delete account
- ✅ Privacy-first: phone numbers only in Firebase Auth layer

**See [`PHASE_4_COMPLETE.md`](./PHASE_4_COMPLETE.md) for full details.**

### Phase 5: Circle Mechanics (NEXT UP)

**Focus:** Add friends, local Circle management, UI foundation

**Tasks:**
- [ ] Database migration v3 (circles + devices tables)
- [ ] CircleMember + Device models
- [ ] CircleManager for CRUD operations
- [ ] CircleView UI (list, add, remove members)
- [ ] Member detail view
- [ ] Max 12 member limit enforcement

**See [`PHASE_5_PLAN.md`](./PHASE_5_PLAN.md) for implementation guide.**

### Phase 6: E2EE Sharing + Relay (PLANNED)
- [ ] Relay server integration (DID lookup)
- [ ] E2EE encryption (X25519 + AES-256-GCM)
- [ ] Share memories with Circle
- [ ] Message delivery via Cloudflare Workers

### Future Phases
- [ ] Map view + fuzzy location privacy (Phase 7)
- [ ] Agent integration - DeepSeek/Qwen (Phase 8)
- [ ] Polish + TestFlight v2 (Phase 9)

**Current file count:** 29 Swift files + PHASE_5_PLAN.md = Ready for Circle mechanics

**December 19, 2025: Phase 4 complete! Firebase Auth + Profile working perfectly. 🎉🌿**
