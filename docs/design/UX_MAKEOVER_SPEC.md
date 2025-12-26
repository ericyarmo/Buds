# Buds UX Makeover — App Store V1 Spec

**Status**: Planning Complete
**Date**: December 25, 2025
**Vision**: Transform Buds from timeline-based memory tracker to jar-based shared spaces

---

## Terminology Lock (One Meaning Per Word)

| Term | Definition | Max | Example |
|------|-----------|-----|---------|
| **Jar** | Shared, encrypted space | 12 people | "Solo", "Friends", "Tahoe Trip" |
| **Bud** | A moment, multimodal container | ∞ per jar | Joint + photo + "felt relaxed" |
| **People** | Members of a jar | 1-12 | Charlie, Alex, Sam |

**What Changed**:
- ~~Circle~~ → **Jar**
- ~~Memory~~ → **Bud**
- ~~Timeline~~ → **Shelf**

**Why**: No overlap. One meaning per word. Clear mental model.

---

## Navigation (Fixed)

```
[ Shelf ]   [ Map ]   [ Shop ]   [ Profile ]
```

**Shelf**: Home. Grid of jars. Entry point.
**Map**: Legal cannabis regions (countries + US states). No memory pins in V1.
**Shop**: 30-60 SKUs, affiliate links. Support Buds by shopping.
**Profile**: You. Your jars. AI insights. Settings.

---

## Core Flows

### 1. Shelf (Home)

**What You See**:
- Grid of jars (2 per row)
- Dots inside = recent activity (up to 4)
- Glow = new buds added in last 24h
- Bud count below jar name
- "+ Add Jar" button always visible

**Tap Jar** → Opens Jar Feed

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

---

### 2. Add Jar Flow

**Lightweight. No ceremony.**

```
┌──────────────────────────────────────────┐
│          Create a Jar                    │
│                                          │
│   Name                                  │
│   [____________________]                │
│                                          │
│   Add people (optional)                 │
│   + Invite                              │
│                                          │
│          Create Jar                     │
└──────────────────────────────────────────┘
```

**Rules**:
- Jar exists even if solo (1 person)
- Max 12 people per jar
- Can create unlimited jars

---

### 3. Jar Feed (Inside a Jar)

**Media First. No Timelines. No Chat Metaphors.**

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
│ │ 🤖 "You often feel calm here."       │ │
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
- No like counts (just reaction emojis stacked)
- No ranking/algorithm
- Comments collapsed by default (tap to expand)

**This feels like shared recall, not posting.**

---

### 4. Reactions (V1)

**Lightweight emotional signals only.**

**Allowed**:
- ❤️ love
- 😂 laugh
- 🔥 hit hard
- 👀 noticed
- 😌 calm

**Rules**:
- Tap to react
- Tap again to remove
- Reactions stack visually (❤️❤️❤️ = 3 people loved it)
- No numeric counts (1,234 likes)
- No emphasis on popularity

---

### 5. Comments (V1)

**Secondary to media. Collapsed by default.**

**Rules**:
- Tap "💬 3" to expand comments
- No threading (flat list)
- Casual tone (no formal replies)
- Adds context without hijacking attention

---

### 6. Add Bud Flow

**Critical: Method Required First**

**Step 1: Method (REQUIRED)**
```
┌──────────────────────────────────────────┐
│      How are you consuming?              │
│                                          │
│  ○ Joint  ○ Bong  ○ Vape               │
│  ○ Edible ○ Dab    ○ Other               │
│                                          │
│           Continue                       │
└──────────────────────────────────────────┘
```

**Cannot skip. Core data point.**

**Step 2: Optional Enrichment (Multimodal)**
```
┌──────────────────────────────────────────┐
│   Add anything (optional)                │
│                                          │
│   📷 Photo (up to 3)                      │
│   🎥 Video                               │
│   🎙 Audio                               │
│   🤖 Talk to AI                          │
│                                          │
│   Save to                                │
│   [ Solo ▼ ]                            │
│                                          │
│          Save Bud                        │
└──────────────────────────────────────────┘
```

**Save immediately creates bud and inserts at top of jar feed.**

**Principle**: Super easy and low-friction to record a bud. Then opt-in to keep enriching.

---

### 7. Map View

**V1: Legal Regions Only (No Memory Pins)**

```
┌──────────────────────────────────────────┐
│           Cannabis Legal Map             │
│                                          │
│   [ WORLD MAP ]                          │
│                                          │
│   🟢 Green = Recreational Legal          │
│   🟡 Yellow = Medical Only               │
│                                          │
│   Countries: Canada, Uruguay, Mexico,    │
│             Thailand, Malta, Luxembourg  │
│                                          │
│   US States: CA, CO, WA, OR, AK, NV,     │
│             MI, IL, MA, ME, VT, NJ, NY,  │
│             VA, NM, CT, RI, MT, AZ, DC   │
│                                          │
│   Tap a region to learn more            │
└──────────────────────────────────────────┘
```

**Tap Region** → Detail sheet with legal info (possession limits, home cultivation)

**Deferred to V2**: Memory pins, clustering, jar filtering

---

### 8. Shop View

**Affiliate Marketplace (30-60 SKUs)**

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

**Tap Product** → Opens `/go/{slug}` in Safari → Redirects to affiliate URL

**Remote Config**: Catalog stored in Cloudflare KV (no app updates for new products)

**Categories** (30-60 SKUs):
- Papers/Cones (RAW, Elements, Zig-Zag)
- Vaporizers (Storz & Bickel, Pax, DynaVap)
- Grinders (Santa Cruz Shredder, Brilliant Cut)
- Storage (Mason jars, Cvault, Boveda packs)
- Accessories (Lighters, ashtrays, rolling trays)
- Lifestyle (Books, art, home goods)

**How We Make Money**: Affiliate commissions (5-15% per sale)

---

### 9. AI Buds (V1: Reflection-Only)

**Safe Framing. Opt-In. Privacy-First.**

**Example AI Bud Card**:
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
```

**Insights (V1 - Rule-Based)**:
1. Method frequency: "Your most common method is joints."
2. Time of day patterns: "You often consume in the evening."
3. Effects correlation: "You often feel relaxed when using edibles."
4. Jar activity: "You've added 5 buds to this jar this week."
5. Streak: "You've logged 7 days in a row."

**Rules**:
- Reflection-only (no predictions: "You will...")
- Local processing (no cloud inference)
- Opt-in (disabled by default in settings)
- Show sample size ("Based on 12 buds")
- No health claims, no medical advice

**Deferred to V2**: LLM-based insights (OpenAI/Anthropic API)

---

### 10. Profile

**Minimal. Identity Only.**

```
┌──────────────────────────────────────────┐
│          ○                               │
│       Charlie                            │
│                                          │
│  Your Jars                              │
│  ○ Solo  ○ Friends  ○ Trips              │
│                                          │
│  AI Insights                            │
│  ○ Enable AI Reflections                │
│  "You often relax in the evening."       │
│                                          │
│  Settings                                │
│  - Storage: 1.2 GB                       │
│  - Privacy & Security                    │
│  - Notifications                         │
│  - Sign Out                              │
└──────────────────────────────────────────┘
```

**No follower counts. No social graph. No public profile.**

---

## Engagement + Growth (Inherent)

**How Buds Grows (No Gamification)**:

1. **Feed creates return loops**: Reactions/comments trigger re-entry
2. **Each bud and jar has a deep link**: Share via iMessage, WhatsApp
3. **Sharing happens at moment of meaning**: "Look at this sunset I just captured"
4. **Jars are invite-only**: Word-of-mouth (Venmo-style)
5. **Shop earns commissions**: Sustainable business model (no ads)

**No explicit referral system. Growth is behavioral.**

---

## What's NOT Changing (Core Physics)

**✅ Kernel**: UCR (Universal Content Receipts), CID, Ed25519 signatures
**✅ E2EE**: X25519 + AES-256-GCM encryption
**✅ Relay**: Cloudflare Workers + D1 + R2
**✅ Multi-device**: Device syncing, E2EE sharing
**✅ Receipt verification**: CID + signature validation

**Only UX/UI is changing. Core security model stays intact.**

---

## Design Language

### Colors
- **Primary**: Green (cannabis-themed, natural)
- **Secondary**: Earthy tones (brown, tan, cream)
- **Accents**: Warm yellows (glow effect), soft blues

### Typography
- **Headlines**: SF Pro Rounded (friendly, approachable)
- **Body**: SF Pro Text (readable, system default)
- **Monospace**: SF Mono (for DIDs, CIDs, technical details)

### Components
- **Cards**: Rounded corners (12pt radius), subtle shadows
- **Buttons**: Filled (primary actions), outlined (secondary actions)
- **Inputs**: Minimal borders, clear focus states
- **Jars**: Circle icons with dots (mason jar metaphor)

### Animations
- **Glow effect**: Subtle pulsing on new buds
- **Card transitions**: Smooth slide-in from bottom
- **Reactions**: Bounce effect when tapping emoji

---

## App Store Marketing

### Name
**"Buds — Cannabis Memory Journal"**

### Subtitle
**"Track your buds, share your jars"**

### Description (280 chars)
```
Buds is a private, encrypted journal for your cannabis experiences.

• Create jars with friends (max 12)
• Add buds (memories) with photos, audio, AI reflections
• See where cannabis is legal (Map)
• Support us by shopping our favorite brands

Your memories, your control. E2EE. No ads.
```

### Keywords
- cannabis journal
- weed tracker
- marijuana diary
- strain notes
- consumption log
- private journal
- encrypted chat

### Screenshots (7)
1. Shelf (home with jars)
2. Jar Feed (media-first)
3. Add Bud (method selection)
4. Map (legal regions)
5. Shop (product grid)
6. AI Buds (reflection card)
7. Profile (your jars)

---

## Success Metrics (V1)

| Metric | Target |
|--------|--------|
| Daily active users | 50+ |
| Avg buds per user per week | 3+ |
| Jar creation rate | 30% create 2+ jars |
| Shop CTR | 5%+ |
| AI insights engagement | 20% enable AI |
| App Store rating | 4.5+ stars |
| Crash-free rate | 99%+ |

---

## Conclusion

**Transformation**: Timeline/Circle/Profile → Shelf/Map/Shop/Profile

**Vision**: Shared, encrypted spaces (jars) for cannabis memories (buds)

**Timeline**: 40 hours (Phases 8-14)

**Status**: Ready to build. Start with Phase 8 (Database Migration).

🫙 Let's fill those jars.
