# Buds Dispensary Deals & Insights (B2B Product)

**Last Updated:** December 16, 2025
**Version:** v1.0 (Post-Consumer Launch)
**Target:** Dispensary Owners & Marketing Managers

---

## Product Vision

**Dispensary Deals** transforms how dispensaries promote products and get real customer feedback—all without creepy POS integration or compliance headaches.

**One-liner:** *"Post deals, get discovered on the map, see what customers actually think—all anonymously."*

---

## Problem Statement

### What Dispensaries Face Today

❌ **No real feedback loop** - Don't know if customers liked what they bought
❌ **Spray-and-pray promotions** - Blast discounts, hope something sticks
❌ **Yelp is fake/gamed** - Reviews are incentivized or competitors trolling
❌ **Can't track deal performance** - Which promos actually drive traffic?
❌ **No differentiation** - Every dispo has same brands, hard to stand out

**Result:** Wasted marketing spend, no product intelligence, generic experience

---

## Solution: Deals + Authentic Feedback

### The Model

```
Dispensary posts deal → "20% off Blue Dream this weekend"
  ↓
Deal shows as HIGHLIGHTED PIN on Buds map (near dispensary location)
  ↓
User sees deal, visits dispensary, uses deal
  ↓
User creates bud (memory) and links it to the deal
  ↓
"Used this deal, Blue Dream was 🔥 5★"
  ↓
Dispensary sees aggregate feedback (n ≥ 75 opted-in users)
  ↓
"Blue Dream deal: 4.6★ avg, 67% re-purchase intent, top effects: relaxed, creative"
```

### Why This Works

✅ **Viral loop** - Deals drive app usage, app drives dispensary traffic
✅ **Authentic feedback** - Users log real experiences, not paid reviews
✅ **No POS integration** - Just marketing (deals) + anonymous feedback
✅ **Compliance-friendly** - Deals = marketing, not sales tracking
✅ **Privacy-preserving** - Aggregate only, k-anonymity threshold (n ≥ 75)
✅ **Discovery tool** - Map becomes deal finder for users

---

## Core Features

### For Consumers (Free)

**Deal Discovery:**
- Browse deals on map (highlighted pins)
- Filter by product type, discount %, distance
- Save deals for later
- Share deals with Circle
- See aggregate ratings on deals

**Attach Buds to Deals:**
- After using a deal, link your bud (memory) to it
- Optional: opt-in to share with dispensary (anonymous)
- See what friends thought of deals (Circle view)

---

### For Dispensaries (Paid)

#### Tier 1: Deals Only ($99/month)

**Post unlimited deals:**
- Title, description, discount
- Product(s), validity dates
- Shows on map as highlighted pin
- Basic analytics:
  - Views (how many users saw deal on map)
  - Saves (how many saved for later)

---

#### Tier 2: Deals + Insights ($299/month)

**All Tier 1 features +**

**Aggregate feedback (n ≥ 75 opted-in users):**
- Average rating for deal
- Top effects reported
- Re-purchase intent (%)
- Age/gender demographics (if users share)
- Comparison to past deals

**Example dashboard:**

```
┌──────────────────────────────────────────────────────────┐
│  Deal: "20% off Blue Dream" (Dec 10-17)                  │
├──────────────────────────────────────────────────────────┤
│                                                           │
│  📊 Performance                                           │
│  • 1,247 map views                                        │
│  • 189 saves                                              │
│  • 87 buds attached (opted-in)                            │
│                                                           │
│  ⭐ Feedback (87 opted-in users)                          │
│  • Avg rating: 4.6★                                       │
│  • Top effects: relaxed (78%), creative (64%), happy (52%)│
│  • Re-purchase intent: 67%                                │
│                                                           │
│  💡 Insights                                              │
│  • Most popular time to redeem: Fri 5-8pm                 │
│  • 23% of users mentioned "great deal" in notes           │
│  • Compared to last Blue Dream promo: +12% rating         │
│                                                           │
│  🔄 Next Steps                                            │
│  • Run similar deal with Gelato (similar profile)         │
│  • Increase Friday inventory for peak demand              │
└──────────────────────────────────────────────────────────┘
```

---

#### Tier 3: Enterprise ($599/month)

**All Tier 2 features +**

**Multi-location support:**
- Manage deals across 3+ locations
- Roll-up analytics
- Location comparison

**Advanced features:**
- API access (programmatic deal posting)
- Custom branding on deal pins
- Priority map placement
- White-label incentives ("Share on Buds, get extra 5% off")

---

## Privacy Architecture

### K-Anonymity Threshold

**Minimum 75 opted-in users** per deal before showing insights

**Why 75?**
- Statistically significant
- Prevents re-identification
- Achievable for medium-traffic dispensaries

**What happens below threshold?**
```
Dashboard shows:
"46 buds attached (need 29 more for insights)"

Dispensary can:
- See view/save counts (no user data)
- Promote deal to hit threshold
- Wait for more organic usage
```

---

### What Dispensaries See vs Don't See

| Can See ✅ | Cannot See ❌ |
|-----------|---------------|
| Aggregate ratings (n ≥ 75) | Individual user identities (DIDs, names) |
| Effect distributions | Specific user notes or memories |
| Re-purchase intent % | Precise user locations (any location data) |
| Time-of-day patterns (general) | User friend circles or social graph |
| Demographics (age/gender if opted-in) | Any PII (phone, email, address) |
| Product/strain preferences (aggregate) | Individual purchase history |

**Example:**
- ✅ "Blue Dream deal: 4.6★ avg from 87 users, top effects: relaxed (78%), creative (64%)"
- ❌ "Alice (did:buds:5dGHK7P9mN) rated Blue Dream 5★ on Dec 3 at [specific location]"

**Location Privacy Note:**
- Dispensary locations are PUBLIC (self-reported by dispensary owner)
- User locations are NEVER shared with dispensaries (not even fuzzy)
- Deal usage is indicated by linking bud to deal, not location tracking

---

## User Flow

### Consumer Side

**1. Discover Deal**
```
Open Buds → Map Tab → See highlighted deal pins
  ↓
Tap pin → "20% off Blue Dream @ Cookies SF"
  ↓
[Save Deal] or [Get Directions]
```

**2. Use Deal**
```
Visit dispensary → Buy Blue Dream with 20% off
  ↓
Open Buds → Create new bud
  ↓
Link to deal: [🎟️ Used deal: 20% off Blue Dream]
  ↓
Add rating + notes + effects
```

**3. Optional Opt-In**
```
After creating bud linked to deal:
  ↓
"Help dispensaries improve? Share anonymous feedback with Cookies SF."

What will be shared (anonymous aggregate only, n ≥ 75 threshold):
• Your rating (1-5 stars)
• Effects you selected (e.g., relaxed, creative)
• Product consumption method (if logged)
• General time-of-day (morning/afternoon/evening)

What will NEVER be shared:
• Your name, identity, or DID
• Your exact location
• Your personal notes
• Individual receipts (only aggregate statistics)

[✓] Share anonymous feedback with this dispensary
  ↓
Save bud
```

---

### Dispensary Side

**1. Create Deal**
```
Login to dashboard → [Create Deal]
  ↓
Fill form:
- Title: "20% off Blue Dream"
- Description: "Limited time! Our best hybrid."
- Product: Blue Dream (flower)
- Discount: 20%
- Dates: Dec 10-17
- Location: Auto-filled from account
  ↓
[Post Deal] → Goes live on map immediately
```

**2. Monitor Performance**
```
Dashboard shows real-time:
- Views: 1,247 (how many saw it on map)
- Saves: 189 (saved for later)
- Buds attached: 87 (opted-in feedback)
```

**3. See Insights (when threshold hit)**
```
After 75+ opted-in buds:
Dashboard unlocks:
- Ratings
- Effects
- Re-purchase intent
- Time patterns
- Comparisons
```

---

## Technical Architecture

### Data Model

**Deals are NOT stored as receipts.** They are a separate dispensary-managed entity stored server-side (not E2EE).

#### Deals Table (Server-Side)

```sql
CREATE TABLE deals (
    deal_id TEXT PRIMARY KEY,  -- UUID
    dispensary_id TEXT NOT NULL,  -- Foreign key to dispensary account

    -- Deal content
    title TEXT NOT NULL,  -- "20% off Blue Dream"
    description TEXT,
    product_name TEXT,
    product_type TEXT,  -- flower, edible, concentrate, etc.
    discount_percent INTEGER,
    discount_amount_usd REAL,

    -- Validity
    start_date INTEGER NOT NULL,  -- Unix timestamp (ms)
    end_date INTEGER NOT NULL,  -- Unix timestamp (ms)
    is_active INTEGER NOT NULL DEFAULT 1,

    -- Location (PUBLIC - dispensary's physical location)
    dispensary_name TEXT NOT NULL,
    dispensary_lat REAL NOT NULL,  -- Precise OK (dispensary is public business)
    dispensary_lon REAL NOT NULL,
    dispensary_address TEXT,

    -- Metadata
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,

    FOREIGN KEY (dispensary_id) REFERENCES dispensaries(id) ON DELETE CASCADE
);

CREATE INDEX idx_deals_active_dates ON deals(is_active, start_date, end_date);
CREATE INDEX idx_deals_location ON deals(dispensary_lat, dispensary_lon);
```

#### Deal Usage Tracking (User's Local Device)

When a user links a bud (receipt) to a deal:

```sql
-- In ucr_headers or payload, add optional field:
ALTER TABLE ucr_headers ADD COLUMN deal_id TEXT;  -- Optional reference to deal

-- This is LOCAL ONLY by default
-- User must explicitly opt-in to share aggregate feedback with dispensary
```

#### Opt-In Table (Server-Side)

```sql
CREATE TABLE deal_feedback_optins (
    id TEXT PRIMARY KEY,
    user_did_hash TEXT NOT NULL,  -- SHA-256(user_did + salt) for privacy
    deal_id TEXT NOT NULL,

    -- Aggregate-only fields (no individual access)
    rating INTEGER CHECK(rating >= 1 AND rating <= 5),
    effects_json TEXT,  -- ["relaxed", "creative", "happy"]
    consumption_method TEXT,  -- "joint", "vape", "edible", etc.
    time_of_day TEXT,  -- "morning", "afternoon", "evening"

    -- Metadata
    opted_in_at INTEGER NOT NULL,

    FOREIGN KEY (deal_id) REFERENCES deals(deal_id) ON DELETE CASCADE
);

CREATE INDEX idx_deal_feedback_deal ON deal_feedback_optins(deal_id);

-- Dispensaries can ONLY query this table with GROUP BY and HAVING COUNT(*) >= 75
```

**Privacy enforced at API level:** All queries to `deal_feedback_optins` MUST use aggregate functions and k-anonymity threshold (n ≥ 75).

---

### API Endpoints

#### Consumer Endpoints

**GET** `/v1/deals/nearby`

**Request:**
```json
{
    "lat": 37.7749,  // User's current location (not stored)
    "lon": -122.4194,
    "radius_km": 10,
    "product_type": "flower",  // Optional filter
    "limit": 50
}
```

**Response:**
```json
{
    "deals": [
        {
            "deal_id": "550e8400-e29b-41d4-a716-446655440000",
            "title": "20% off Blue Dream",
            "description": "Limited time! Our best hybrid.",
            "product_name": "Blue Dream",
            "product_type": "flower",
            "discount_percent": 20,
            "start_date": 1702166400000,
            "end_date": 1702771200000,
            "dispensary": {
                "name": "Cookies SF",
                "lat": 37.7699,
                "lon": -122.4469,
                "address": "1781 Haight St, San Francisco, CA",
                "distance_km": 2.3
            },
            "aggregate_stats": {  // Only if n ≥ 75
                "avg_rating": 4.6,
                "total_feedback": 87,
                "top_effects": ["relaxed", "creative", "happy"]
            }
        }
    ]
}
```

**Note:** User's lat/lon is sent for proximity search but NOT stored server-side.

---

**POST** `/v1/deals/{deal_id}/optin`

**Request:**
```json
{
    "user_did": "did:buds:5dGHK7P9mN",
    "receipt_cid": "bafyreiabc123...",  // Receipt linked to deal
    "rating": 5,
    "effects": ["relaxed", "creative"],
    "consumption_method": "vape",
    "time_of_day": "evening"
}
```

**Response:**
```json
{
    "success": true,
    "message": "Thanks! Your anonymous feedback will help dispensaries improve."
}
```

**Server processing:**
1. Hash user_did (SHA-256 + salt) to prevent re-identification
2. Store in `deal_feedback_optins` table
3. Do NOT store receipt_cid (verify locally for authenticity, then discard)
4. User's feedback is now part of aggregate pool

---

#### Dispensary Endpoints (Authenticated)

**POST** `/v1/dispensary/deals`

Create new deal (requires dispensary account).

---

**GET** `/v1/dispensary/deals/{deal_id}/insights`

**Response:**
```json
{
    "deal": {
        "deal_id": "550e8400-e29b-41d4-a716-446655440000",
        "title": "20% off Blue Dream",
        "start_date": 1702166400000,
        "end_date": 1702771200000
    },
    "performance": {
        "map_views": 1247,  // Approximation from client analytics
        "saves": 189,
        "feedback_count": 87
    },
    "insights": {  // Only shown if feedback_count >= 75
        "avg_rating": 4.6,
        "rating_distribution": {
            "5": 52,
            "4": 28,
            "3": 5,
            "2": 2,
            "1": 0
        },
        "top_effects": [
            {"effect": "relaxed", "percent": 78},
            {"effect": "creative", "percent": 64},
            {"effect": "happy", "percent": 52}
        ],
        "consumption_methods": {
            "vape": 45,
            "joint": 32,
            "bong": 10
        },
        "time_of_day": {
            "morning": 12,
            "afternoon": 23,
            "evening": 52
        }
    },
    "threshold_met": true  // false if feedback_count < 75
}
```

**Privacy guarantee:** All data is aggregate with n ≥ 75 threshold enforced at query level.

---

### Integration with Receipt Architecture

**Deals are orthogonal to receipts:**

- **Receipts** = User's private, E2EE memories (sessions, products, experiences)
- **Deals** = Public, dispensary-posted promotions (server-side, not encrypted)

**Linking:**
- Users can optionally reference a `deal_id` in their receipt payload
- This is LOCAL by default (not shared)
- If user opts in, aggregate feedback (rating + effects) is sent to server via `/v1/deals/{deal_id}/optin`
- Server never sees the full receipt, only the explicitly shared aggregate fields

**Privacy flow:**
```
User creates receipt → Receipt stored locally (E2EE)
  ↓
User optionally adds deal_id to receipt payload
  ↓
User sees opt-in prompt: "Share feedback with dispensary?"
  ↓
If YES: Extract (rating, effects, method, time) → Send to server (hashed DID)
  ↓
Server aggregates with n ≥ 75 threshold → Dispensary sees aggregate only
```

---

## Business Model

### Revenue Streams

**1. Subscription (Primary)**
- Tier 1: $99/month × 100 dispensaries = $9,900/month
- Tier 2: $299/month × 50 dispensaries = $14,950/month
- Tier 3: $599/month × 10 dispensaries = $5,990/month
- **Total MRR: $30,840/month = $370K ARR**

**2. Promoted Deals (Future)**
- Pay extra to feature deal at top of map view
- $50-200 per promotion depending on area

---

### Unit Economics

**Per Tier 2 Dispensary ($299/month):**

**Revenue:** $299/month
**COGS:**
- Cloud hosting: ~$10/month
- Support: ~$20/month
- Payment processing: ~$9/month

**Gross Margin:** $260/month (87%)

**CAC:** ~$400 (demo + onboarding + first-month support)
**Payback:** 1.3 months
**LTV (24-month retention):** $7,176

**LTV:CAC:** 18x 🎉

---

### Market Size

**TAM (Total Addressable Market):**
- ~10,000 dispensaries in US (legal states)
- Avg $299/month (Tier 2)
- **$36M/year opportunity**

**SAM (Serviceable Available Market):**
- Target: Urban dispensaries (higher traffic = easier to hit threshold)
- ~3,000 locations
- **$10.8M/year opportunity**

**SOM (Serviceable Obtainable Market):**
- Realistic 3-year capture: 5% of SAM
- 150 customers @ $299/month avg
- **$540K ARR in Year 3**

---

## Go-to-Market Strategy

### Phase 1: Pilot (Month 1-3)

**Goal:** 5 dispensaries posting deals

**Approach:**
- Free for 90 days
- High-traffic locations (SF, LA, Denver)
- Help them hit threshold with in-store promotion

**In-store materials:**
```
QR code poster:
"Download Buds → Link your experience → Help us improve!"

"First 100 users to share feedback get 10% off next visit"
```

**Success criteria:**
- 5 deals posted
- 3 deals hit threshold (75+ opted-in users)
- Dispensaries see actionable insights

---

### Phase 2: Local Expansion (Month 4-6)

**Goal:** 20 paying customers in 3 cities

**Sales motion:**
- Case studies from pilot
- "Your competitor is already using Buds"
- Live demo with their location on map

**Pricing:**
- Tier 1 ($99) for smaller dispos
- Tier 2 ($299) for high-traffic

**Channels:**
- Direct outreach (owner/marketing manager)
- Industry events (MJBizCon)
- Cannabis industry Facebook groups

---

### Phase 3: National Scale (Month 7-12)

**Goal:** 100 paying customers across 10+ states

**Channels:**
- POS provider partnerships (Dutchie, Treez)
- Industry publications (MG Magazine, Leafly)
- Webinars ("How to drive traffic with deals")

**Product additions:**
- API for programmatic deal posting
- Integration with dispensary websites
- White-label incentive programs

---

## Competitive Landscape

| Competitor | Offering | Weakness | Our Advantage |
|------------|----------|----------|---------------|
| **Yelp** | Reviews | Fake/incentivized | Real users, verified purchases (via deal link) |
| **Weedmaps** | Menus/ads | Pay-to-play, no feedback | Authentic feedback, deals-driven |
| **Leafly** | Reviews/menus | Same as Yelp | Better incentive alignment (deals) |
| **Dutchie/Jane** | E-commerce | No post-purchase feedback | Close the loop with buds |
| **Springbig** | Loyalty/SMS | No product insights | Show what customers actually like |

**Our moat:** Only platform with deals → discovery → authentic feedback loop

---

## Key Metrics (Dispensary Success)

### What Dispensaries Care About

1. **Foot traffic** - More customers through the door
2. **Inventory turnover** - Move slow products faster
3. **Customer retention** - Build loyalty
4. **Marketing ROI** - Know which promos work

### How Buds Helps

**Before Buds:**
- Post deal on Instagram → no idea if it worked
- Discount everything → margin erosion
- No feedback on what customers liked

**After Buds:**
- Post deal on Buds → see exactly how many engaged
- Target deals based on what works (past data)
- Feedback loop: "Blue Dream deal worked, Gelato next"

**ROI Example (Illustrative - Unvalidated):**

**Assumptions (need real-world validation):**
- Subscription cost: $299/month
- Deals posted: 4 deals in December
- Conversion rate: 1.5% from deal view → purchase (optimistic estimate)
- Average purchase: $65

**Projected result (if assumptions hold):**
- 487 customers discovered via deals (1.5% of 32,000+ views)
- Revenue: ~$31,655
- ROI: ~106x

**Important caveats:**
- ⚠️ Conversion rate (1.5%) is unvalidated and likely optimistic
- ⚠️ Attribution is difficult (did they buy because of the deal or would they have anyway?)
- ⚠️ Actual results will vary significantly by location, deal quality, and market
- ⚠️ These are illustrative projections, not guarantees

**To validate:** Run pilot with real dispensaries and measure actual conversion with tracking codes or unique SKUs.

---

## Compliance & Legal

### Why This Model is Lower-Risk (Not Risk-Free)

**What we're NOT doing (lower-risk activities):**
- ❌ POS integration (no sales tracking)
- ❌ Individual purchase records storage
- ❌ Facilitating direct sales between users
- ❌ Making medical/health claims about products

**What we ARE doing:**
- ✅ Marketing platform (deals are advertisements)
- ✅ Aggregate feedback system (anonymous, n ≥ 75 threshold)
- ✅ Discovery tool (map shows public business locations)

**Legal considerations:**
- Deals = commercial speech (generally 1st Amendment protected, subject to state cannabis advertising laws)
- Feedback = anonymous reviews (similar to Yelp, Leafly model)
- No controlled substance transactions occur on platform
- Platform does not handle payment or fulfillment

**State-specific compliance:**
- Cannabis advertising laws vary significantly by state
- Some states restrict:
  - Claims about effects or benefits
  - Targeting specific demographics
  - Certain promotional language
- Dispensaries are responsible for ensuring their deals comply with local regulations
- Platform should include Terms of Service requiring dispensary compliance

**Risk areas to monitor:**
- Federal illegality of cannabis (Schedule I) creates inherent legal uncertainty
- State advertising regulations may evolve
- Privacy laws (CCPA, state-specific) require ongoing compliance
- Data breach liability (even with k-anonymity, breach could expose aggregate patterns)

**Recommended safeguards:**
- Legal review in each target state before launch
- Clear Terms of Service holding dispensaries liable for compliance
- Regular compliance audits
- Liability insurance

**This is NOT legal advice.** Consult qualified cannabis attorneys in each jurisdiction before launch.

---

## Implementation Checklist

### Backend (Server-Side)
- [ ] Create `deals` table schema (PostgreSQL or similar)
- [ ] Create `deal_feedback_optins` table with k-anonymity enforcement
- [ ] Create `dispensaries` table for account management
- [ ] Implement GET `/v1/deals/nearby` endpoint (proximity search)
- [ ] Implement POST `/v1/deals/{deal_id}/optin` endpoint (with DID hashing)
- [ ] Implement POST `/v1/dispensary/deals` endpoint (authenticated)
- [ ] Implement GET `/v1/dispensary/deals/{deal_id}/insights` endpoint (with n ≥ 75 threshold)
- [ ] Add SQL-level enforcement: `HAVING COUNT(*) >= 75` on all aggregate queries
- [ ] Set up Stripe billing integration (subscription tiers)
- [ ] Build dispensary authentication system (accounts, API keys)

### iOS App (Consumer)
- [ ] Add `deal_id` optional field to receipt payload schema
- [ ] Build "Deals" map view with highlighted pins
- [ ] Implement deal detail view (title, description, dispensary info)
- [ ] Add "Link to deal" option when creating new bud/receipt
- [ ] Build opt-in consent screen with explicit field disclosure
- [ ] Implement POST to `/v1/deals/{deal_id}/optin` on user consent
- [ ] Add "Saved deals" feature (local bookmarks)
- [ ] Add deal filtering (product type, distance, discount %)

### Dispensary Web Dashboard
- [ ] Build dispensary signup/login flow
- [ ] Build deal creation form (title, product, dates, discount)
- [ ] Build deal management view (edit, deactivate, extend)
- [ ] Build analytics dashboard with threshold indicator ("46/75 feedback needed")
- [ ] Show aggregate insights when threshold met (ratings, effects, time patterns)
- [ ] Add subscription tier management (upgrade/downgrade)
- [ ] Add billing portal (Stripe integration)

### Marketing & Launch
- [ ] Create in-store promo materials (QR codes, posters)
- [ ] Design pitch deck with case studies
- [ ] Launch pilot with 5 dispensaries (free 90-day trial)
- [ ] Collect feedback from pilot dispensaries
- [ ] Validate conversion rates and ROI assumptions
- [ ] Iterate based on pilot learnings
- [ ] Scale sales motion (direct outreach, industry events)

### Legal & Compliance
- [ ] Legal review in target states (CA, CO, WA, OR, etc.)
- [ ] Draft Terms of Service for dispensaries
- [ ] Draft Privacy Policy covering aggregate data
- [ ] Add state-specific advertising compliance checks
- [ ] Obtain liability insurance
- [ ] Set up regular compliance audits

---

## Future Enhancements

### Post-v1.0

1. **Loyalty integration** - Users attach loyalty cards, get points
2. **Group deals** - "Bring 3 friends, get 30% off"
3. **Flash deals** - "Next 10 users to redeem get 50% off"
4. **Deal marketplace** - Users can gift/trade deals
5. **White-label app** - Dispensary-branded Buds instance

---

**Next:** See [UX_FLOWS.md](./UX_FLOWS.md) for deal discovery user flows.
