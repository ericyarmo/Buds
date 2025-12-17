# Buds Development Roadmap

**Last Updated:** December 16, 2025
**Target:** TestFlight v0.1 in 2-4 weeks

---

## Overview

This roadmap breaks Buds development into **4 phases** with clear milestones, dependencies, and success criteria.

---

## Phase 0: Foundation (Week 1)

**Goal:** Set up project infrastructure and core dependencies

### Tasks

#### 0.1 Project Setup
- [ ] Create Xcode project (Swift 6, iOS 17+, SwiftUI)
- [ ] Initialize Git repository
- [ ] Set up `.gitignore` (exclude secrets, build artifacts)
- [ ] Create GitHub repo (private)
- [ ] Add README with project overview

#### 0.2 Dependencies
- [ ] Install GRDB via SPM (database)
- [ ] Install Firebase via SPM (auth + push)
- [ ] Set up Cloudflare Workers project (relay server)
- [ ] Configure wrangler.toml (D1 database)
- [ ] Install CryptoKit (built-in, no SPM needed)

#### 0.3 Core Framework Structure
```
Buds/
├── App/
│   ├── BudsApp.swift
│   └── AppDelegate.swift
├── Core/
│   ├── ChaingeKernel/
│   │   ├── ReceiptManager.swift
│   │   ├── IdentityManager.swift
│   │   ├── CryptoManager.swift
│   │   └── SyncManager.swift
│   ├── Database/
│   │   ├── Database.swift
│   │   ├── Migrations/
│   │   └── Repositories/
│   └── Models/
│       ├── UCRHeader.swift
│       ├── Receipt.swift
│       ├── MemoryBud.swift
│       └── Circle.swift
├── Features/
│   ├── Timeline/
│   ├── Map/
│   ├── Circle/
│   ├── Profile/
│   └── Agent/
├── Shared/
│   ├── Views/
│   ├── Components/
│   └── Utilities/
└── Resources/
    ├── Assets.xcassets
    └── Info.plist
```

#### 0.4 Database Schema
- [ ] Implement GRDB migration system
- [ ] Create v1 migration (all tables from DATABASE_SCHEMA.md)
- [ ] Write unit tests for migrations
- [ ] Verify schema with GRDB Studio

#### 0.5 Firebase Setup
- [ ] Create Firebase project
- [ ] Enable Phone Authentication
- [ ] Download `GoogleService-Info.plist`
- [ ] Configure app for push notifications (APNS)
- [ ] Test Firebase connection

**Success Criteria:**
✅ Xcode project builds successfully
✅ GRDB database creates on first launch
✅ Firebase auth SDK initialized
✅ All dependencies resolved

**Time Estimate:** 2-3 days

---

## Phase 1: Core Kernel (Week 1-2)

**Goal:** Implement receipt creation, signing, and local storage

### Tasks

#### 1.1 Canonical CBOR Encoding
- [ ] Implement `CBOREncoder` (deterministic, sorted keys)
- [ ] Write unit tests with test vectors
- [ ] Verify CID computation matches spec

#### 1.2 Identity Management
- [ ] Generate Ed25519 keypair (signing)
- [ ] Generate X25519 keypair (E2EE)
- [ ] Store in iOS Keychain
- [ ] Implement DID generation (`did:buds:<base58(ed25519_pubkey_first_20_bytes)>`)
- [ ] Firebase UID mapping for device discovery (relay only)
- [ ] Write unit tests

#### 1.3 Receipt Manager
- [ ] Implement `createReceipt()` flow:
  - Build unsigned preimage
  - Encode to canonical CBOR
  - Compute CID
  - Sign with Ed25519
  - Store in GRDB
- [ ] Implement `fetchReceipts()` query
- [ ] Implement `updateReceipt()` (edit chain)
- [ ] Implement `deleteReceipt()`
- [ ] Write integration tests

#### 1.4 Receipt Schemas
- [ ] Define `SessionPayload` struct
- [ ] Define all receipt type payloads (from RECEIPT_SCHEMAS.md)
- [ ] Implement validation rules
- [ ] Write unit tests

**Success Criteria:**
✅ Can create a session receipt
✅ Receipt CID is deterministic
✅ Signature verifies correctly
✅ Receipt persists to GRDB
✅ Can query receipts by type/date

**Time Estimate:** 4-5 days

---

## Phase 2: UI Foundation (Week 2)

**Goal:** Build core UI for memory creation and timeline

### Tasks

#### 2.1 Design System
- [ ] Define color palette
- [ ] Define typography scale
- [ ] Create reusable components:
  - `MemoryCard`
  - `PrimaryButton`
  - `InputField`
  - `EffectTag`
- [ ] Implement dark mode support

#### 2.2 Timeline View
- [ ] Implement `TimelineView` (list of memories)
- [ ] Implement `MemoryCard` component
- [ ] Add pull-to-refresh
- [ ] Add infinite scroll (pagination)
- [ ] Add empty state

#### 2.3 Create Memory Flow
- [ ] Implement `CreateMemoryView` (sheet)
- [ ] Add strain search/autocomplete
- [ ] Add effect tag picker
- [ ] Add photo picker
- [ ] Add rating selector
- [ ] Implement save action
- [ ] Add validation + error handling

#### 2.4 Memory Detail View
- [ ] Implement `MemoryDetailView`
- [ ] Show all receipt fields
- [ ] Add edit button → `CreateMemoryView` (pre-filled)
- [ ] Add delete action (with confirmation)
- [ ] Add share preview

#### 2.5 Tab Bar Navigation
- [ ] Implement `MainTabView`
- [ ] Add Timeline tab
- [ ] Add Map tab (placeholder)
- [ ] Add FAB for create
- [ ] Add Circle tab (placeholder)
- [ ] Add Profile tab (placeholder)

**Success Criteria:**
✅ Can create a memory via UI
✅ Memory appears in timeline immediately
✅ Can edit existing memory (creates new version)
✅ Can delete memory
✅ UI follows design system

**Time Estimate:** 3-4 days

---

## Phase 3: Location & Map (Week 2-3)

**Goal:** Implement location capture and map view

### Tasks

#### 3.1 Location Manager
- [ ] Request location permission (with consent UI)
- [ ] Capture precise location
- [ ] Compute fuzzy location (grid snapping)
- [ ] Store in `locations` table
- [ ] Link to receipt via `location_cid`

#### 3.2 Map View
- [ ] Implement `MapView` (MapKit)
- [ ] Show user's memories as pins
- [ ] Implement pin annotations (strain name, rating)
- [ ] Add pin tap → show memory preview
- [ ] Add filter: show all vs favorites only

#### 3.3 Location Privacy
- [ ] Implement location OFF by default (critical privacy invariant)
- [ ] Add consent screen for first location enable
- [ ] Implement fuzzy location (500m grid snapping)
- [ ] Add "delay share until" option (for future Circle sharing in Phase 4)
- [ ] Ensure precise location NEVER shared without explicit per-memory consent
- [ ] Write privacy UI tests

**Success Criteria:**
✅ Can capture location with memory
✅ Location OFF by default
✅ Map shows pins for location-enabled memories
✅ Tapping pin opens memory detail
✅ Fuzzy location computed correctly

**Time Estimate:** 2-3 days

---

## Phase 4: Circle & E2EE (Week 3-4)

**Goal:** Implement Circle invites, E2EE sharing, and relay sync

### Tasks

#### 4.1 Device Registration
- [ ] Implement device keypair generation
- [ ] Register device with relay server
- [ ] Store device in local DB
- [ ] Implement FCM token registration

#### 4.2 Circle Management
- [ ] Implement `CircleView` (members list)
- [ ] Add invite creation flow
- [ ] Generate invite code + QR
- [ ] Add invite acceptance flow
- [ ] Implement member removal
- [ ] Enforce 12-member limit

#### 4.3 E2EE Implementation
- [ ] Implement X25519 key agreement
- [ ] Implement AES-256-GCM encryption
- [ ] Implement key wrapping (per device)
- [ ] Implement key unwrapping
- [ ] Write crypto unit tests

#### 4.4 Share Memory Flow
- [ ] Add "Share to Circle" button in detail view
- [ ] Implement consent UI (location sharing options)
- [ ] Encrypt memory payload
- [ ] Wrap keys for all Circle devices
- [ ] Post to relay server
- [ ] Show "Shared" badge in timeline

#### 4.5 Receive Shared Memories
- [ ] Fetch encrypted messages from relay
- [ ] Unwrap AES key
- [ ] Decrypt payload
- [ ] Verify signature
- [ ] Store as `received_memories`
- [ ] Show in Circle feed

#### 4.6 Relay Server (Cloudflare Workers)
- [ ] Implement `/v1/devices` endpoints
- [ ] Implement `/v1/messages` endpoints
- [ ] Add rate limiting
- [ ] Add signature verification
- [ ] Deploy to Cloudflare
- [ ] Test with iOS app

**Success Criteria:**
✅ Can invite friend to Circle
✅ Friend can accept invite
✅ Can share memory to Circle
✅ Circle member receives encrypted message
✅ Circle member can decrypt and view memory
✅ Relay server stores only ciphertext

**Time Estimate:** 5-7 days

---

## Phase 5: Agent Integration (Week 4)

**Goal:** Implement "Ask Buds" cannabis knowledge assistant

**Note:** v0.1 uses DeepSeek/Qwen/Kimi (NOT Claude) for cost optimization (~20x cheaper)

### Tasks

#### 5.1 Agent Query Parser
- [ ] Implement query classification (personal memory, strain info, etc.)
- [ ] Build context from local receipts
- [ ] Format context for LLM API

#### 5.2 LLM API Integration
- [ ] Set up DeepSeek/Qwen/Kimi API key (NOT Anthropic - see AGENT_INTEGRATION.md)
- [ ] Implement pluggable `LLMProvider` interface
- [ ] Implement `DeepSeekProvider.query()` wrapper
- [ ] Add cannabis knowledge assistant system prompt
- [ ] Parse response + extract citations
- [ ] Handle errors (rate limits, network)
- [ ] Add required privacy opt-in flow (user must consent to sending data to LLM)

#### 5.3 Agent UI
- [ ] Implement `AgentView` (chat interface)
- [ ] Add suggested queries (quick actions)
- [ ] Show streaming response (optional)
- [ ] Render citations as tappable links
- [ ] Add disclaimer screen (first use)

#### 5.4 Local Knowledge Base (Optional)
- [ ] Embed strain database (if offline mode desired)
- [ ] Implement vector search
- [ ] Fall back to embedded KB if no network

**Success Criteria:**
✅ Can ask "What strains made me anxious?"
✅ Agent returns answer with deterministic citations (type field + safety_flags)
✅ Tapping citation opens relevant memory
✅ Privacy disclosure + opt-in shown on first use (required!)
✅ Disclaimer shown with legal/medical guardrails
✅ Works with 50+ logged memories
✅ Cost per query < $0.01 (using DeepSeek)

**Time Estimate:** 3-4 days

**Note:** Can defer to v0.2 if timeline is tight (not blocking for TestFlight)

---

## Phase 6: Profile & Settings (Week 4)

**Goal:** Complete profile view and settings

### Tasks

#### 6.1 Profile View
- [ ] Show user stats (sessions, strains, avg rating)
- [ ] Show top strains
- [ ] Show top effects
- [ ] Add edit profile button

#### 6.2 Settings
- [ ] Implement Privacy settings
- [ ] Implement Notification settings
- [ ] Add data export (JSON)
- [ ] Add delete account (with confirmation)
- [ ] Add sign out (if authenticated)

#### 6.3 Onboarding (Optional)
- [ ] Add welcome screen
- [ ] Add age gate (21+)
- [ ] Add phone auth screen
- [ ] Add permissions screen

**Success Criteria:**
✅ Profile shows accurate stats
✅ Can export all receipts
✅ Can delete account
✅ Privacy settings work

**Time Estimate:** 2-3 days

---

## Phase 7: Polish & Testing (Week 4)

**Goal:** Bug fixes, performance optimization, TestFlight prep

### Tasks

#### 7.1 Testing
- [ ] Write unit tests (80% coverage goal)
- [ ] Write integration tests (key flows)
- [ ] Manual QA on device
- [ ] Test on multiple iOS versions (17, 18)
- [ ] Test Circle with 2+ devices

#### 7.2 Performance
- [ ] Profile app launch time (< 3s cold)
- [ ] Profile memory save time (< 150ms)
- [ ] Optimize image compression
- [ ] Add database indexes (already in schema)
- [ ] Test with 500+ receipts

#### 7.3 Error Handling
- [ ] Add error alerts (network, permissions, etc.)
- [ ] Add retry logic for sync failures
- [ ] Add offline mode indicator
- [ ] Add loading states (spinners, skeletons)

#### 7.4 Accessibility
- [ ] Add VoiceOver labels
- [ ] Test with VoiceOver enabled
- [ ] Ensure touch targets ≥ 44pt
- [ ] Test Dynamic Type (text scaling)

#### 7.5 TestFlight Prep
- [ ] Set up App Store Connect
- [ ] Create app record
- [ ] Upload build via Xcode
- [ ] Write TestFlight release notes
- [ ] Invite internal testers (10-20 friends)

**Success Criteria:**
✅ No critical bugs
✅ App launches < 3s cold
✅ All core flows work end-to-end
✅ TestFlight build distributed

**Time Estimate:** 3-4 days

---

## Summary Timeline

| Phase | Duration | Milestone |
|-------|----------|-----------|
| **Phase 0: Foundation** | 2-3 days | Project setup + dependencies |
| **Phase 1: Core Kernel** | 4-5 days | Receipt creation working |
| **Phase 2: UI Foundation** | 3-4 days | Can create + view memories |
| **Phase 3: Location & Map** | 2-3 days | Map shows memories |
| **Phase 4: Circle & E2EE** | 5-7 days | Sharing works end-to-end |
| **Phase 5: Agent** | 3-4 days | Ask Buds works |
| **Phase 6: Profile** | 2-3 days | Profile + settings complete |
| **Phase 7: Polish** | 3-4 days | TestFlight ready |
| **Total** | **24-33 days** | **~4 weeks** |

---

## Parallel Work Streams

**Backend (Relay Server) can be built in parallel:**

Week 1-2:
- iOS: Phase 0-2 (Foundation + Kernel + UI)
- Backend: Relay server API (devices, messages)

Week 3-4:
- iOS: Phase 3-4 (Location + Circle)
- Backend: Testing, deployment, monitoring

---

## Dependencies & Blockers

### Critical Path
```
Phase 0 → Phase 1 → Phase 2 → TestFlight
         ↓
         Phase 3 (can happen after Phase 2)
         ↓
         Phase 4 (requires Phase 1 + relay server)
         ↓
         Phase 5 (requires Phase 1, optional for v0.1)
```

### External Dependencies
- **Firebase project setup** (blocks Phase 0.5)
- **Cloudflare account** (blocks Phase 4.6)
- **LLM API key** (DeepSeek/Qwen/Kimi - blocks Phase 5.2, NOT Anthropic)
- **Apple Developer account** ($99/year, blocks TestFlight)

---

## Post-v0.1 Roadmap

### v0.2 (Month 2-3)
- [ ] Export/import receipts
- [ ] Advanced search (by strain, effect, location)
- [ ] Circle map (show shared memories on map)
- [ ] Push notifications for Circle updates
- [ ] Strain database integration (Leafly API)

### v0.3 (Month 3-4)
- [ ] Agent improvements (RAG, better citations)
- [ ] Photo gallery view
- [ ] Favorites collection
- [ ] Daily summaries (auto-generated)
- [ ] Widget support (iOS home screen)

### v1.0 (Month 4-6)
- [ ] Dispensary insights dashboard (B2B)
- [ ] Multi-device support refinement
- [ ] Onboarding tutorial
- [ ] Public TestFlight (scale to 100 users)
- [ ] App Store submission

---

## Success Metrics (v0.1)

### Technical
- ✅ App launches < 3s cold
- ✅ Memory save < 150ms
- ✅ 0 critical bugs
- ✅ E2EE verified working

### Product
- ✅ 10+ alpha testers using daily
- ✅ 50+ memories created total
- ✅ 3+ Circle relationships established
- ✅ 0 major privacy concerns

### User Feedback
- ✅ NPS ≥ 8 (would recommend)
- ✅ "Easy to use" rating ≥ 4/5
- ✅ 0 reports of lost data

---

## Risk Mitigation

| Risk | Mitigation |
|------|-----------|
| **Scope creep** | Defer Agent to v0.2 if timeline tight |
| **E2EE complexity** | v0.1 uses stable device keys (not ephemeral), simplify key rotation for later |
| **Relay server costs** | Stay within Cloudflare free tier (100K req/day) |
| **Firebase costs** | Use Firebase Spark (free tier, 10K phone auths/month) |
| **LLM API costs** | Use DeepSeek (~$0.005/query) instead of Claude (~$0.015/query) for v0.1 |
| **Apple rejection** | Review App Store guidelines (no cannabis sales, 21+ age gate, clear disclaimers) |
| **Privacy violations** | Follow privacy invariants strictly (location OFF by default, no PII in receipts, E2EE verified) |

---

## Next Steps (Today)

1. ✅ Review all architecture docs
2. [ ] Create GitHub repo
3. [ ] Initialize Xcode project
4. [ ] Set up dependencies (GRDB, Firebase)
5. [ ] Implement Phase 0.3 (core framework structure)
6. [ ] Start Phase 1.1 (CBOR encoding)

**Let's build! 🌿**
