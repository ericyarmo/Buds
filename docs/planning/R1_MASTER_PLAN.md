# Buds R1 Master Plan — App Store V1

**Status**: Planning Phase
**Date**: December 25, 2025
**Goal**: Ship App Store V1 with Shelf (Jars), Map, Shop, Profile, AI Buds
**Target**: R1 (App Store ready), R2 (Shop infrastructure)

---

## Executive Summary

**Transformation**: Timeline/Circle/Profile → Shelf/Map/Shop/Profile

**Terminology Lock**:
- ~~Circle~~ → **Jar** (shared encrypted space, max 12 people)
- ~~Memory~~ → **Bud** (a moment, multimodal container, lives in exactly one jar)
- ~~Timeline~~ → **Shelf** (home view showing all jars)
- **People** = just people (not "buds")

**Core Principle**: One meaning per word. No overlap.

**What's NOT Changing** (Core Physics):
- ✅ Chainge Kernel (UCR, CID, signatures)
- ✅ E2EE messaging (X25519 + AES-256-GCM)
- ✅ Relay infrastructure (Cloudflare Workers + D1 + R2)
- ✅ Device management + multi-device sync
- ✅ Receipt verification

**What IS Changing** (UX/UI):
- Navigation: Timeline → Shelf, add Shop tab
- Data model: Memories now scoped to Jars (1 bud = 1 jar)
- Home screen: Feed of all buds → Grid of jars
- Add 3 major features: Map v1, Shop v1, AI Buds v1

---

## R1 vs R2 Breakdown

### R1 — App Store V1 (Core Product)

**Owner**: Product/Engineering
**Timeline**: Phases 8-14 (~40 hours total)

**Features**:
1. Shelf (home view with jars)
2. Jar Feed (inside a jar, media-first)
3. Add Bud flow (method required, enrichment optional)
4. Map v1 (legal regions only, no memories yet)
5. AI Buds v1 (reflection-only, safe framing)
6. Profile (enhanced with jar list)

**Definition of Done**:
- ✅ TestFlight build stable
- ✅ App Store submission package drafted
- ✅ All core flows tested end-to-end
- ✅ Screenshots + marketing copy ready

---

### R2 — Shop v1 (Infrastructure)

**Owner**: Product/Engineering
**Timeline**: 2 phases (~12 hours)

**Features**:
1. Remote-config catalog (JSON from Cloudflare KV)
2. Redirect tracking (`/go/{slug}`)
3. UTM/coupon support
4. Analytics: clicks, CTR, partner leaderboard

**Definition of Done**:
- ✅ End-to-end tracking verified across 3 partners
- ✅ Admin dashboard for catalog updates
- ✅ Analytics dashboard live

---

## Terminology Mapping

### UI-Facing Terms (User Sees)

| Old Term | New Term | Description |
|----------|----------|-------------|
| Circle | **Jar** | Encrypted space, max 12 people, unlimited buds |
| Memory | **Bud** | A moment, multimodal, belongs to exactly 1 jar |
| Timeline | **Shelf** | Home view showing all your jars |
| Circle Members | **People** | Members of a jar (not called "buds") |
| Share to Circle | **Share to Jar** | E2EE sharing with jar members |

### Internal/Kernel Terms (Unchanged)

| Term | Description | Example |
|------|-------------|---------|
| Receipt | UCR (Universal Content Receipt) | `bafyrei...` |
| CID | Content Identifier | `bafyrei...` |
| DID | Decentralized Identifier | `did:buds:3mVJm...` |
| Signature | Ed25519 signature (base64) | 88 chars |
| Device | Multi-device identity | UUID v4 |

**Principle**: Kernel/relay terminology stays technical, UI terminology becomes friendly.

---

## Database Architecture Changes

### Current Schema (Phase 7)

```
circles (table)
  - id, did, display_name, phone_number, status, ...

local_receipts (table)
  - uuid, header_cid, is_favorited, image_cids, ...
  - NO jar scoping (memories are global)

ucr_headers (table)
  - cid, did, device_id, parent_cid, receipt_type, ...
```

**Problem**: Memories are global, not scoped to jars/circles.

---

### New Schema (Phase 8: Migration v5)

```sql
-- Migration v5: Jar architecture

-- 1. Rename "circles" → "jars" (terminology alignment)
ALTER TABLE circles RENAME TO jars;

-- 2. Add jar_id to local_receipts (scope buds to jars)
ALTER TABLE local_receipts ADD COLUMN jar_id TEXT NOT NULL DEFAULT 'solo';

-- 3. Create default "Solo" jar for existing buds
INSERT INTO jars (id, did, display_name, status, created_at, updated_at)
VALUES ('solo', (SELECT did FROM devices WHERE is_current_device = 1 LIMIT 1), 'Solo', 'active', ?, ?);

-- 4. Create jar_members table (N:M relationship)
CREATE TABLE jar_members (
  jar_id TEXT NOT NULL,
  member_did TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'member',  -- 'owner' or 'member'
  joined_at REAL NOT NULL,
  PRIMARY KEY (jar_id, member_did),
  FOREIGN KEY (jar_id) REFERENCES jars(id) ON DELETE CASCADE
);

-- 5. Migrate existing circle members to jar_members
INSERT INTO jar_members (jar_id, member_did, role, joined_at)
SELECT 'solo', did, 'member', created_at FROM jars WHERE id != 'solo';

-- 6. Add indexes
CREATE INDEX idx_local_receipts_jar_id ON local_receipts(jar_id);
CREATE INDEX idx_jar_members_jar_id ON jar_members(jar_id);
CREATE INDEX idx_jar_members_member_did ON jar_members(member_did);
```

---

### Updated Schema

**jars** (renamed from circles):
- `id` TEXT PRIMARY KEY (UUID)
- `name` TEXT (user-facing jar name)
- `description` TEXT (optional)
- `owner_did` TEXT (creator's DID)
- `created_at` REAL
- `updated_at` REAL

**jar_members** (N:M relationship):
- `jar_id` TEXT (FK → jars.id)
- `member_did` TEXT (person's DID)
- `role` TEXT ('owner' or 'member')
- `joined_at` REAL
- PRIMARY KEY (jar_id, member_did)

**local_receipts** (buds):
- `uuid` TEXT PRIMARY KEY
- `header_cid` TEXT (FK → ucr_headers.cid)
- `jar_id` TEXT (FK → jars.id) ← **NEW**
- `is_favorited` INTEGER
- `image_cids` TEXT (JSON array)
- `created_at` REAL
- `updated_at` REAL

**Key Changes**:
1. Each bud belongs to exactly 1 jar (`jar_id` NOT NULL)
2. Jars can have 1-12 members (N:M via jar_members)
3. Solo jar created by default for existing buds
4. Circle members migrated to jar_members

---

## Phase Breakdown (R1)

### Phase 8: Database Migration + Jar Model (3 hours)

**Goal**: Migrate from Circle-centric to Jar-centric architecture

**Tasks**:
1. Create migration v5 (schema changes above)
2. Create `Jar.swift` model (replaces CircleMember as primary UI model)
3. Create `JarMember.swift` model (N:M relationship)
4. Update `Memory.swift` to include `jarID` property
5. Create `JarRepository.swift` (CRUD for jars)
6. Update `CircleManager.swift` → `JarManager.swift`
7. Run migration locally, verify data integrity

**Files Created** (4):
- `Buds/Core/Models/Jar.swift` (80 lines)
- `Buds/Core/Models/JarMember.swift` (60 lines)
- `Buds/Core/Database/Repositories/JarRepository.swift` (200 lines)
- `Buds/Core/JarManager.swift` (renamed from CircleManager, 150 lines)

**Files Modified** (3):
- `Buds/Core/Models/Memory.swift` (+10 lines: jarID property)
- `Buds/Core/Database/Database.swift` (+80 lines: migration v5)
- `Buds/Core/Database/Repositories/MemoryRepository.swift` (+20 lines: jar filtering)

**Success Criteria**:
- ✅ Migration runs without errors
- ✅ Existing buds migrated to "Solo" jar
- ✅ No data loss
- ✅ Jar CRUD operations work

**Time**: 3 hours

---

### Phase 9: Shelf View (Home Redesign) (4 hours)

**Goal**: Replace Timeline with Shelf (grid of jars)

**Design Spec**:

```
┌──────────────────────────────────────────┐
│               B U D S                    │
│                                          │
│        + Add Jar                        │
│                                          │
│   ┌───────────────┐   ┌───────────────┐ │
│   │   ○ ○ ○ ○     │   │   ○ ○ ○        │ │
│   │   Solo        │   │   Friends      │ │
│   │   12 buds     │   │   8 buds       │ │
│   └───────────────┘   └───────────────┘ │
│                                          │
│   ┌───────────────┐   ┌───────────────┐ │
│   │   ○ ○ ○       │   │   ○            │ │
│   │   Tahoe Trip  │   │   Late Night   │ │
│   │   5 buds      │   │   2 buds       │ │
│   └───────────────┘   └───────────────┘ │
└──────────────────────────────────────────┘
```

**Visual Language**:
- Jars displayed as cards (2 per row)
- Dots inside = recent activity (up to 4 dots)
- Glow effect = new buds added in last 24h
- Bud count displayed below jar name

**Tasks**:
1. Create `ShelfView.swift` (replaces TimelineView as tab 0)
2. Create `JarCard.swift` component (card UI with dots/glow)
3. Create `AddJarView.swift` (sheet to create new jar)
4. Update `MainTabView.swift` (Timeline → Shelf, Circle → hidden)
5. Add jar activity logic (when was last bud added?)

**Files Created** (3):
- `Buds/Features/Shelf/ShelfView.swift` (180 lines)
- `Buds/Shared/Views/JarCard.swift` (120 lines)
- `Buds/Features/Shelf/AddJarView.swift` (100 lines)

**Files Modified** (1):
- `Buds/Features/MainTabView.swift` (change tab 0 from TimelineView to ShelfView)

**Success Criteria**:
- ✅ Shelf shows all jars (including Solo)
- ✅ Tapping jar opens Jar Feed
- ✅ Add Jar flow creates new jar
- ✅ Activity indicators work (dots + glow)

**Time**: 4 hours

---

### Phase 10: Jar Feed View (6 hours)

**Goal**: Inside a jar, show buds in media-first feed format

**Design Spec**:

```
┌──────────────────────────────────────────┐
│ ← Solo                    👥            │
│                                          │
│ ┌──────────────────────────────────────┐ │
│ │ [ IMAGE / VIDEO / AUDIO PREVIEW ]    │ │
│ │                                      │ │
│ │ Method: Joint                        │ │
│ │                                      │ │
│ │ ❤️ 😂 🔥 👀 😌        💬 3            │ │
│ │                                      │ │
│ │ Alex: unreal sunset                  │ │
│ │ Sam: this one hit                    │ │
│ └──────────────────────────────────────┘ │
│                                          │
│ ┌──────────────────────────────────────┐ │
│ │ [ AI CARD ]                          │ │
│ │                                      │ │
│ │ 🤖 "You usually feel calm here."     │ │
│ │                                      │ │
│ │ ❤️ 👀            💬 1                │ │
│ └──────────────────────────────────────┘ │
│                                          │
│            + Add Bud                     │
└──────────────────────────────────────────┘
```

**Principles**:
- Media always visible (no collapsed cards)
- No usernames in headers (just content)
- No timestamps by default (optional tap to show)
- No like counts (just reaction emojis)
- Comments collapsed by default (tap to expand)

**Tasks**:
1. Create `JarFeedView.swift` (main feed inside a jar)
2. Create `BudCard.swift` component (media-first card)
3. Create `ReactionBar.swift` component (5 emoji reactions)
4. Create `CommentSection.swift` component (collapsed by default)
5. Update `CreateMemoryView.swift` → `CreateBudView.swift` (method required first)
6. Add "Share to Jar" selector (dropdown of user's jars)

**Reactions (V1)**:
- ❤️ love
- 😂 laugh
- 🔥 hit hard
- 👀 noticed
- 😌 calm

**Files Created** (5):
- `Buds/Features/Jar/JarFeedView.swift` (250 lines)
- `Buds/Shared/Views/BudCard.swift` (200 lines)
- `Buds/Shared/Views/ReactionBar.swift` (80 lines)
- `Buds/Shared/Views/CommentSection.swift` (120 lines)
- `Buds/Features/CreateBud/CreateBudView.swift` (renamed from CreateMemoryView, 300 lines)

**Files Modified** (2):
- `Buds/Features/Shelf/ShelfView.swift` (add navigation to JarFeedView)
- `Buds/Core/Models/Memory.swift` (+30 lines: reactions, comments)

**Database Changes** (add reactions/comments):

```sql
-- Add reactions table
CREATE TABLE reactions (
  id TEXT PRIMARY KEY,
  memory_uuid TEXT NOT NULL,
  user_did TEXT NOT NULL,
  emoji TEXT NOT NULL,  -- '❤️', '😂', '🔥', '👀', '😌'
  created_at REAL NOT NULL,
  FOREIGN KEY (memory_uuid) REFERENCES local_receipts(uuid) ON DELETE CASCADE
);

CREATE INDEX idx_reactions_memory ON reactions(memory_uuid);

-- Add comments table
CREATE TABLE comments (
  id TEXT PRIMARY KEY,
  memory_uuid TEXT NOT NULL,
  user_did TEXT NOT NULL,
  text TEXT NOT NULL,
  created_at REAL NOT NULL,
  FOREIGN KEY (memory_uuid) REFERENCES local_receipts(uuid) ON DELETE CASCADE
);

CREATE INDEX idx_comments_memory ON comments(memory_uuid);
```

**Success Criteria**:
- ✅ Jar Feed shows all buds in jar (media-first)
- ✅ Reactions work (tap to add/remove)
- ✅ Comments work (collapsed by default, expandable)
- ✅ Add Bud flow requires method selection first
- ✅ Bud is saved to selected jar

**Time**: 6 hours

---

### Phase 11: Map View v1 (Legal Regions Only) (4 hours)

**Goal**: Show map highlighting where cannabis is legal (countries + US states)

**Design Spec**:

```
┌──────────────────────────────────────────┐
│           Cannabis Legal Map             │
│                                          │
│   [ WORLD MAP ]                          │
│                                          │
│   🟢 Countries: Canada, Uruguay, ...     │
│   🟢 US States: CA, CO, WA, OR, ...      │
│                                          │
│   (No memory pins in v1)                 │
└──────────────────────────────────────────┘
```

**Legal Regions (Hardcoded for V1)**:

**Countries** (recreational legal):
- 🇨🇦 Canada
- 🇺🇾 Uruguay
- 🇲🇽 Mexico
- 🇹🇭 Thailand
- 🇲🇹 Malta
- 🇱🇺 Luxembourg

**US States** (recreational legal):
- CA, CO, WA, OR, AK, NV, MI, IL, MA, ME, VT, NJ, NY, VA, NM, CT, RI, MT, AZ, DC

**Tasks**:
1. Create `MapView.swift` (replace "Coming Soon" placeholder)
2. Use MapKit to display world map
3. Add overlay polygons for legal regions (countries + states)
4. Green highlight for legal regions
5. Tap region → Show info sheet (country/state name, legal status)

**Files Created** (2):
- `Buds/Features/Map/MapView.swift` (200 lines)
- `Buds/Features/Map/LegalRegions.swift` (data: countries + states, 100 lines)

**Files Modified** (1):
- `Buds/Features/MainTabView.swift` (replace placeholder with MapView)

**Deferred to V2**:
- Memory pins on map (show where buds were created)
- Tap jar → Filter map to jar's buds
- Clustering for dense areas

**Success Criteria**:
- ✅ Map displays with legal regions highlighted
- ✅ Tapping region shows legal status info
- ✅ No memory pins (intentionally deferred)
- ✅ Fast load time (<1s)

**Time**: 4 hours

---

### Phase 12: Shop View + Remote Config (8 hours)

**Goal**: Affiliate marketplace with 30-60 SKUs, remote config catalog, tracking

**Design Spec**:

```
┌──────────────────────────────────────────┐
│           Shop                           │
│   Support Buds with your purchases       │
│                                          │
│   ┌────────────┐  ┌────────────┐        │
│   │ [ IMAGE ]  │  │ [ IMAGE ]  │        │
│   │ RAW Cones  │  │ Storz+Bick │        │
│   │ $12.99     │  │ $279       │        │
│   └────────────┘  └────────────┘        │
│                                          │
│   ┌────────────┐  ┌────────────┐        │
│   │ [ IMAGE ]  │  │ [ IMAGE ]  │        │
│   │ Grinder    │  │ Mason Jar  │        │
│   │ $24.99     │  │ $8.99      │        │
│   └────────────┘  └────────────┘        │
└──────────────────────────────────────────┘
```

**Architecture**:

```
Cloudflare KV (catalog storage)
  ↓
iOS app fetches catalog.json on launch
  ↓
Display in ShopView grid
  ↓
User taps product → Open /go/{slug} in Safari
  ↓
Relay tracks click, redirects to affiliate URL
```

**Catalog Schema** (catalog.json in KV):

```json
{
  "version": 1,
  "updated_at": "2025-12-25T12:00:00Z",
  "products": [
    {
      "id": "raw-cones-king",
      "name": "RAW King Size Cones (50 pack)",
      "brand": "RAW",
      "price": 12.99,
      "currency": "USD",
      "image_url": "https://cdn.getbuds.app/products/raw-cones.jpg",
      "slug": "raw-cones",
      "affiliate_url": "https://amzn.to/3XyZ...",
      "category": "papers"
    },
    // ... 29-59 more products
  ]
}
```

**Redirect Tracking** (relay):

```typescript
// New endpoint: GET /go/{slug}
app.get('/go/:slug', async (c) => {
  const slug = c.req.param('slug');

  // Lookup product in catalog (KV)
  const catalog = await c.env.KV_CATALOG.get('catalog.json', 'json');
  const product = catalog.products.find(p => p.slug === slug);

  if (!product) {
    return c.redirect('https://joinbuds.com');
  }

  // Track click in D1
  await c.env.DB.prepare(`
    INSERT INTO shop_clicks (product_id, slug, clicked_at, user_agent)
    VALUES (?, ?, ?, ?)
  `).bind(product.id, slug, Date.now(), c.req.header('User-Agent')).run();

  // Redirect to affiliate URL
  return c.redirect(product.affiliate_url);
});
```

**Database Schema** (relay D1):

```sql
-- Track shop clicks
CREATE TABLE shop_clicks (
  id TEXT PRIMARY KEY,
  product_id TEXT NOT NULL,
  slug TEXT NOT NULL,
  clicked_at REAL NOT NULL,
  user_agent TEXT,
  ip_address TEXT
);

CREATE INDEX idx_shop_clicks_product ON shop_clicks(product_id);
CREATE INDEX idx_shop_clicks_clicked_at ON shop_clicks(clicked_at DESC);
```

**Tasks**:

**iOS (4 hours)**:
1. Create `ShopView.swift` (grid of products)
2. Create `ProductCard.swift` (image, name, price)
3. Create `ShopManager.swift` (fetch catalog from KV, cache locally)
4. Add "Shop" tab to MainTabView
5. Open /go/{slug} in Safari when product tapped

**Relay (4 hours)**:
1. Add `/go/{slug}` redirect endpoint
2. Create `shop_clicks` table in D1
3. Add catalog.json to Cloudflare KV
4. Create admin script to update catalog (local JSON → KV)
5. Add analytics dashboard (product clicks, CTR)

**Files Created** (iOS: 3, Relay: 2):
- `Buds/Features/Shop/ShopView.swift` (180 lines)
- `Buds/Shared/Views/ProductCard.swift` (80 lines)
- `Buds/Core/ShopManager.swift` (120 lines)
- `buds-relay/src/handlers/shop.ts` (100 lines)
- `buds-relay/scripts/update-catalog.ts` (60 lines)

**Files Modified** (2):
- `Buds/Features/MainTabView.swift` (add Shop tab)
- `buds-relay/src/index.ts` (add /go/{slug} route)

**Success Criteria**:
- ✅ Catalog loads on app launch
- ✅ Products display in grid (2 per row)
- ✅ Tapping product opens /go/{slug} in Safari
- ✅ Redirect tracked in D1
- ✅ Analytics dashboard shows clicks, CTR
- ✅ Admin can update catalog without app update

**Time**: 8 hours (4 iOS + 4 relay)

---

### Phase 13: AI Buds v1 (Reflection-Only) (6 hours)

**Goal**: AI-generated insights shown in jar feed, reflection-only (no predictions)

**Design Principles**:
- **Reflection-only**: "You often..." not "You will..."
- **Opt-in**: User must enable in settings
- **Safe framing**: No health claims, no medical advice
- **Privacy**: AI runs on aggregated local data (no cloud inference)

**Example AI Bud Cards**:

```
┌──────────────────────────────────────┐
│ 🤖 AI Reflection                     │
│                                      │
│ "You often feel calm when using      │
│  edibles in the evening."            │
│                                      │
│ Based on 12 buds over 2 weeks        │
│                                      │
│ ❤️ 👀                                │
└──────────────────────────────────────┘

┌──────────────────────────────────────┐
│ 🤖 AI Reflection                     │
│                                      │
│ "Your most common method is joints." │
│                                      │
│ 8 joints, 3 vapes, 1 edible          │
│                                      │
│ 😌                                   │
└──────────────────────────────────────┘
```

**AI Insights (V1 - Simple Rules)**:

For V1, use **rule-based insights** (no LLM inference):

1. **Method frequency**: "Your most common method is {method}"
2. **Time of day patterns**: "You often consume at {time_of_day}"
3. **Effects correlation**: "You often feel {effect} when using {method}"
4. **Jar activity**: "You've added {count} buds to this jar this week"
5. **Streak**: "You've logged {count} days in a row"

**Implementation Strategy**:

```swift
class AIBudsManager {
    // Generate insights from local data (no cloud)
    func generateInsights(for jar: Jar) async -> [AIInsight] {
        let buds = try await MemoryRepository.shared.getMemories(jarID: jar.id)

        var insights: [AIInsight] = []

        // Insight 1: Method frequency
        let methodCounts = buds.map(\.consumptionMethod).countOccurrences()
        if let mostCommon = methodCounts.max(by: { $0.value < $1.value }) {
            insights.append(AIInsight(
                text: "Your most common method is \(mostCommon.key.displayName.lowercased()).",
                type: .methodFrequency,
                metadata: methodCounts
            ))
        }

        // Insight 2: Time of day patterns
        let hourCounts = buds.map { Calendar.current.component(.hour, from: $0.createdAt) }
        let avgHour = hourCounts.reduce(0, +) / hourCounts.count
        let timeOfDay = avgHour < 12 ? "morning" : avgHour < 18 ? "afternoon" : "evening"
        insights.append(AIInsight(
            text: "You often consume in the \(timeOfDay).",
            type: .timeOfDay
        ))

        // ... more insights

        return insights
    }
}
```

**Tasks**:
1. Create `AIBudsManager.swift` (rule-based insight generation)
2. Create `AIInsight.swift` model (text, type, metadata)
3. Create `AIBudCard.swift` component (special card in jar feed)
4. Add AI toggle in Profile settings ("Enable AI Reflections")
5. Insert AI bud cards in jar feed (1 insight per 10 buds)

**Files Created** (3):
- `Buds/Core/AIBudsManager.swift` (200 lines)
- `Buds/Core/Models/AIInsight.swift` (60 lines)
- `Buds/Shared/Views/AIBudCard.swift` (100 lines)

**Files Modified** (2):
- `Buds/Features/Jar/JarFeedView.swift` (+40 lines: inject AI cards)
- `Buds/Features/Profile/ProfileView.swift` (+20 lines: AI toggle)

**Deferred to V2** (LLM-based insights):
- OpenAI/Anthropic API integration
- Personalized reflections ("You seem more relaxed on Fridays")
- Conversational AI ("Ask me anything about your buds")

**Success Criteria**:
- ✅ AI insights generated locally (no cloud)
- ✅ Insights appear in jar feed (max 1 per 10 buds)
- ✅ User can toggle AI on/off in settings
- ✅ No health claims or medical advice
- ✅ Insights are reflection-only (no predictions)

**Time**: 6 hours

---

### Phase 14: App Store Prep + Polish (9 hours)

**Goal**: TestFlight build stable, App Store submission ready

**Tasks**:

**1. Screenshots (2 hours)**:
- Shelf view (home with jars)
- Jar feed (media-first)
- Add bud flow (method selection)
- Map view (legal regions)
- Shop view (product grid)
- Profile

**2. App Store Copy (1 hour)**:
- App name: "Buds — Cannabis Memory Journal"
- Subtitle: "Track your buds, share your jars"
- Description (280 chars):
  ```
  Buds is a private, encrypted journal for your cannabis experiences.

  • Create jars with friends (max 12)
  • Add buds (memories) with photos, audio, AI reflections
  • See where cannabis is legal (Map)
  • Support us by shopping our favorite brands

  Your memories, your control. E2EE. No ads.
  ```

**3. Bug Fixes (3 hours)**:
- Fix memory leaks (Instruments)
- Fix race conditions (Thread Sanitizer)
- Fix UI glitches (dark mode, iPad layout)
- Test on iOS 17-18

**4. Performance Optimization (2 hours)**:
- Lazy load images in jar feed
- Prefetch next 10 buds when scrolling
- Cache jar metadata (reduce DB queries)
- Optimize Inbox polling (APNs push instead of 30s poll)

**5. TestFlight Testing (1 hour)**:
- Invite 5-10 beta testers
- Collect feedback
- Fix critical bugs

**Files Modified** (~20 files):
- Various bug fixes across codebase

**Success Criteria**:
- ✅ No crashes in 1 hour stress test
- ✅ 60 FPS scrolling in jar feed
- ✅ < 100ms bud creation latency
- ✅ App Store screenshots + copy ready
- ✅ TestFlight build approved by 5+ testers

**Time**: 9 hours

---

## R1 Total Timeline

| Phase | Task | Time |
|-------|------|------|
| 8 | Database Migration + Jar Model | 3h |
| 9 | Shelf View (Home Redesign) | 4h |
| 10 | Jar Feed View | 6h |
| 11 | Map View v1 (Legal Regions) | 4h |
| 12 | Shop View + Remote Config | 8h |
| 13 | AI Buds v1 (Reflection-Only) | 6h |
| 14 | App Store Prep + Polish | 9h |
| **Total** | | **40 hours** |

**Timeline**: ~1-2 weeks (full-time) or 2-4 weeks (part-time)

---

## R2 Breakdown (Shop Infrastructure)

### Phase 15: Catalog Management + Analytics (6 hours)

**Goal**: Admin dashboard for catalog updates, analytics

**Tasks**:
1. Create web dashboard (simple HTML + JS)
2. Add catalog CRUD (create, update, delete products)
3. Upload images to R2
4. Push updated catalog.json to Cloudflare KV
5. View analytics: clicks, CTR, top products

**Files Created**:
- `buds-relay/admin/index.html` (catalog editor, 300 lines)
- `buds-relay/src/handlers/admin.ts` (auth + CRUD, 200 lines)

**Time**: 6 hours

---

### Phase 16: Advanced Tracking + UTM/Coupons (6 hours)

**Goal**: UTM parameter support, coupon codes, partner leaderboard

**Tasks**:
1. Add UTM tracking (source, medium, campaign)
2. Support coupon codes in redirect URLs
3. Build partner leaderboard (clicks, conversions)
4. Export analytics to CSV

**Files Modified**:
- `buds-relay/src/handlers/shop.ts` (+100 lines: UTM tracking)

**Time**: 6 hours

---

## R2 Total Timeline

| Phase | Task | Time |
|-------|------|------|
| 15 | Catalog Management + Analytics | 6h |
| 16 | Advanced Tracking + UTM/Coupons | 6h |
| **Total** | | **12 hours** |

---

## Risk Analysis

### Risk 1: Jar Architecture Breaking Change

**Symptom**: Existing users lose memories when migrating to jars

**Mitigation**:
- Migration v5 creates "Solo" jar for all existing buds
- No data loss (tested locally before deploy)
- Rollback plan: Revert to v4 schema, restore backup

---

### Risk 3: App Store Rejection (Cannabis Content)

**Symptom**: Apple rejects app for promoting illegal activity

**Mitigation**:
- Emphasize "legal regions only" (Map view)
- No buy/sell functionality (just tracking)
- Age gate (21+ only)
- Comply with App Store Review Guidelines 1.4.3

---

### Risk 4: Shop Affiliate Links Breaking

**Symptom**: Affiliate links expire, users get 404s

**Mitigation**:
- Monitor /go/{slug} errors in relay logs
- Set up alerts for 404s (Cloudflare Workers alerts)
- Fallback to product page if affiliate link broken

---

### Risk 5: AI Insights Accuracy

**Symptom**: AI says "You often use edibles" but user never logged edibles

**Mitigation**:
- Show sample size: "Based on 12 buds over 2 weeks"
- Allow user to dismiss/hide insights
- Only show insights with >10 data points

---

## Success Metrics (R1)

| Metric | Target |
|--------|--------|
| TestFlight installs | 100+ |
| Daily active users | 50+ |
| Avg buds per user per week | 3+ |
| Jar creation rate | 30% of users create 2+ jars |
| Shop click-through rate | 5%+ |
| AI insights engagement | 20% of users enable AI |
| Crash-free rate | 99%+ |
| App Store rating | 4.5+ stars |

---

## Success Metrics (R2)

| Metric | Target |
|--------|--------|
| Shop affiliate clicks | 1,000+/month |
| Conversion rate | 3%+ (clicks → purchases) |
| Top product CTR | 10%+ |
| Partner leaderboard accuracy | 100% (no lost clicks) |

---

## Next Steps

1. **Validate Plan**: Review this plan, confirm scope
2. **Start Phase 8**: Database migration + Jar model
3. **Iterate**: Build → Test → Ship each phase
4. **TestFlight**: Invite beta testers after Phase 10
5. **App Store**: Submit after Phase 14

---

## Open Questions

1. **Jar Limit**: Should we enforce max 12 jars per user? (Probably yes, UX simplicity)
2. **AI Opt-in**: Should AI be enabled by default? (Probably no, privacy-first)
3. **Map V2**: When do we add memory pins to map? (Defer to post-launch)
4. **Shop Categories**: Should we group products by category (papers, vapes, etc.)? (Yes, Phase 15)
5. **Reactions Storage**: Should reactions be encrypted and synced across devices? (Defer to V2)

---

## Appendix: File Structure (After R1)

```
Buds/
├── App/
│   └── BudsApp.swift
├── Core/
│   ├── Models/
│   │   ├── Jar.swift (NEW)
│   │   ├── JarMember.swift (NEW)
│   │   ├── Memory.swift (updated: jarID)
│   │   ├── AIInsight.swift (NEW)
│   │   ├── UCRHeader.swift
│   │   ├── Device.swift
│   │   └── EncryptedMessage.swift
│   ├── Database/
│   │   ├── Database.swift (migration v5)
│   │   └── Repositories/
│   │       ├── JarRepository.swift (NEW)
│   │       ├── MemoryRepository.swift (updated)
│   │       └── AIInsightRepository.swift (NEW)
│   ├── JarManager.swift (renamed from CircleManager)
│   ├── AIBudsManager.swift (NEW)
│   ├── ShopManager.swift (NEW)
│   ├── DeviceManager.swift
│   ├── E2EEManager.swift
│   └── RelayClient.swift
├── Features/
│   ├── Auth/
│   │   └── PhoneAuthView.swift
│   ├── Shelf/ (NEW - replaces Timeline)
│   │   ├── ShelfView.swift
│   │   └── AddJarView.swift
│   ├── Jar/ (NEW)
│   │   ├── JarFeedView.swift
│   │   └── JarSettingsView.swift
│   ├── CreateBud/ (renamed from CreateMemory)
│   │   ├── CreateBudView.swift
│   │   └── PhotoPicker.swift
│   ├── Map/ (NEW)
│   │   ├── MapView.swift
│   │   └── LegalRegions.swift
│   ├── Shop/ (NEW)
│   │   └── ShopView.swift
│   ├── Profile/
│   │   └── ProfileView.swift
│   └── MainTabView.swift (updated: 4 tabs)
├── Shared/
│   └── Views/
│       ├── JarCard.swift (NEW)
│       ├── BudCard.swift (NEW)
│       ├── AIBudCard.swift (NEW)
│       ├── ProductCard.swift (NEW)
│       ├── ReactionBar.swift (NEW)
│       └── CommentSection.swift (NEW)
└── Info.plist
```

---

## Conclusion

**R1 (App Store V1)**: 40 hours, 7 phases, complete UX/UI transformation

**R2 (Shop Infrastructure)**: 12 hours, 2 phases, advanced analytics

**Total**: 52 hours (~2 weeks full-time)

**Status**: Ready to execute. Start with Phase 8 (Database Migration).

🚀 Let's ship it.
