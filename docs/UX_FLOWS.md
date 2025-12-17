# Buds UX Flows & Wireframes

**Last Updated:** December 16, 2025
**Version:** v0.1
**Design System:** iOS HIG + Custom Cannabis Aesthetic

---

## Core User Flows

### Flow 1: Onboarding (First Launch)

```
Launch App
  ↓
Splash Screen (2s)
  ↓
Welcome Screen
  "Remember your best experiences"
  [Get Started]
  ↓
Age Gate
  "Are you 21 or older?"
  [Yes, I'm 21+] [No]
  ↓
Account Setup (Optional)
  "Optional: Link your account for backup"

  Your identity is cryptographic (not tied to phone/email).
  Linking allows account recovery across devices.

  [Link with Phone] or [Continue without linking]
  ↓
Profile Setup
  "What should we call you?"
  [Display name: _______]
  [Skip]
  ↓
Permissions Screen
  "Buds works better with:"
  [ ] Location (for map)
  [ ] Notifications (for Circle updates)
  [ ] Photos (for memories)
  [All set, skip for now]
  ↓
Main Tab View (Timeline)
```

**Key UX decisions:**
- Age gate required (legal compliance)
- Phone auth optional (anonymous mode supported)
- Permissions can be skipped (ask in context later)
- No forced tutorial (learn by doing)

---

### Flow 2: Create Memory (Core Action)

```
Timeline Tab
  ↓
Tap [+ New Memory] (FAB)
  ↓
Create Memory Sheet
┌─────────────────────────────────┐
│ New Memory                  [X] │
├─────────────────────────────────┤
│ 🌿 What did you smoke?          │
│   [Search strains...]           │
│   Recent: Blue Dream, Gelato    │
│                                 │
│ 📦 Product Details (optional)   │
│   Brand: [_______]              │
│   Type: [Flower ▼]              │
│   THC%: [____] CBD%: [____]     │
│                                 │
│ 📝 Notes                        │
│   [How was it?_____________]    │
│   [_________________________]   │
│                                 │
│ ⭐ Rating                       │
│   ★★★★★                         │
│                                 │
│ 😊 Effects (tap to add)         │
│   [relaxed] [creative] [+]      │
│                                 │
│ 📷 Add Photo                    │
│   [+] Camera  [+] Library       │
│                                 │
│ 📍 Location [OFF ▼]             │
│   [ ] Capture location          │
│       (Must enable in Settings  │
│        → Privacy → Location)    │
│                                 │
│ 🌍 Share with Circle            │
│   ( ) Private (default)         │
│   ( ) Share to Circle           │
│                                 │
│         [Save Memory]           │
└─────────────────────────────────┘
```

**UX patterns:**
- Progressive disclosure (optional fields collapsed)
- Smart defaults (private, location off)
- Quick entry (tap effects, don't type)
- Photo optional but prominent

**User journey:**
1. Tap FAB → Sheet slides up
2. Type strain name → Autocomplete suggests
3. Add quick note + rating → Done
4. Advanced users: Add all details
5. Save → Optimistic UI update, sync background

---

### Flow 3: View Timeline

```
Timeline Tab
┌─────────────────────────────────┐
│ [Search] [Filter ▼]   [@][+]   │
├─────────────────────────────────┤
│                                 │
│ ┌─────────────────────────────┐ │
│ │ 🌿 Blue Dream         [♡] │ │
│ │ Yesterday, 8:32pm          │ │
│ │ ──────────────────────────── │ │
│ │ Perfect for creative work.  │ │
│ │ Felt super focused but...   │ │
│ │                             │ │
│ │ ★★★★★  relaxed • creative  │ │
│ │ 📍 Home  🔐 Private         │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ 🌿 Gelato             [♡] │ │
│ │ 3 days ago                  │ │
│ │ ──────────────────────────── │ │
│ │ [Photo]                     │ │
│ │ Great evening smoke. Super  │ │
│ │ relaxed but not too sleepy. │ │
│ │                             │ │
│ │ ★★★★☆  relaxed • happy     │ │
│ │ 📍 Park  🌍 Shared          │ │
│ └─────────────────────────────┘ │
│                                 │
│ [Load more...]                  │
└─────────────────────────────────┘
```

**Card design:**
- Strain name prominent (biggest text)
- Timestamp relative (Yesterday, 3 days ago)
- Notes truncated (tap to expand)
- Visual indicators: ♡ favorite, 📍 location, 🔐/🌍 share state
- Photo preview if attached

**Interactions:**
- Tap card → Open detail view
- Swipe left → Quick actions (Edit, Delete, Share)
- Pull to refresh → Fetch new Circle memories
- Long press → Context menu

---

### Flow 4: Memory Detail

```
Memory Detail View
┌─────────────────────────────────┐
│ [← Back]              [• • •]   │
├─────────────────────────────────┤
│ 🌿 Blue Dream                   │
│ Hybrid • 23.5% THC • 0.8% CBD   │
│ Cookies • Flower                │
│                                 │
│ Yesterday, 8:32pm               │
│ 📍 Home (Private)               │
│                                 │
│ [Photo - full width]            │
│                                 │
│ ★★★★★ (5/5)                    │
│                                 │
│ 😊 Effects                      │
│ [relaxed] [creative] [focused]  │
│                                 │
│ 📝 Notes                        │
│ Perfect for creative work.      │
│ Felt super focused but relaxed. │
│ No anxiety, clear-headed high.  │
│                                 │
│ 💨 Method: Joint                │
│ ⏱️ Duration: ~2 hours           │
│                                 │
│ ──────────────────────────────  │
│                                 │
│ [🌍 Share to Circle]            │
│ [✏️ Edit]  [🗑️ Delete]         │
│                                 │
└─────────────────────────────────┘
```

**[• • •] Menu options:**
- Edit Memory
- Share to Circle / Unshare
- Add to Favorites
- Export as Image
- Delete Memory

---

### Flow 5: Circle Management

```
Circle Tab
┌─────────────────────────────────┐
│ My Circle (3/12)     [+ Invite] │
├─────────────────────────────────┤
│ [Feed] [Members] [Invites]      │
├─────────────────────────────────┤
│ Circle Feed                     │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ Alice shared                │ │
│ │ 🌿 Sour Diesel              │ │
│ │ 2 hours ago                 │ │
│ │ ──────────────────────────── │ │
│ │ "Too intense for me, made   │ │
│ │ me anxious. Your mileage    │ │
│ │ may vary."                  │ │
│ │                             │ │
│ │ ★★☆☆☆  anxious • energized │ │
│ │ 📍 SF (~500m)               │ │
│ │                             │ │
│ │ [View Details]              │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ Bob shared                  │ │
│ │ 🌿 Blue Dream               │ │
│ │ Yesterday                   │ │
│ │ ──────────────────────────── │ │
│ │ [Photo]                     │ │
│ │ "Perfect for gaming night!" │ │
│ │                             │ │
│ │ ★★★★★  happy • focused     │ │
│ │ [View Details]              │ │
│ └─────────────────────────────┘ │
└─────────────────────────────────┘
```

**Members Tab:**
```
┌─────────────────────────────────┐
│ Circle Members (3/12)           │
├─────────────────────────────────┤
│ [Alice]     [avatar]            │
│ 47 shared memories              │
│ Member since Dec 2024           │
│             [View] [Remove]     │
│ ──────────────────────────────  │
│ [Bob]       [avatar]            │
│ 12 shared memories              │
│ Member since Jan 2025           │
│             [View] [Remove]     │
│ ──────────────────────────────  │
│ [Carol]     [avatar]            │
│ 3 shared memories               │
│ Member since Jan 2025           │
│             [View] [Remove]     │
└─────────────────────────────────┘
```

**Invite Flow:**
```
Tap [+ Invite]
  ↓
Create Invite Sheet
┌─────────────────────────────────┐
│ Invite to Circle            [X] │
├─────────────────────────────────┤
│ Invite a friend to share        │
│ memories privately.             │
│                                 │
│ Optional message:               │
│ [Let's track our sessions!__]   │
│                                 │
│ Invite code:                    │
│ ┌─────────────────────────────┐ │
│ │   BUDS-A7F3-92B1            │ │
│ │   [QR code]                 │ │
│ └─────────────────────────────┘ │
│                                 │
│ Expires in 7 days               │
│                                 │
│ [Share Link] [Copy Code]        │
└─────────────────────────────────┘
```

**Accept Invite Flow (Recipient):**
```
Tap invite link / scan QR
  ↓
Accept Invite Sheet
┌─────────────────────────────────┐
│ Join Alice's Circle             │
├─────────────────────────────────┤
│ Alice invited you to Buds!      │
│                                 │
│ Share your cannabis memories    │
│ privately with up to 12 friends.│
│                                 │
│ By joining, you can:            │
│ • See memories Alice shares     │
│ • Share your own memories       │
│ • View shared locations on map  │
│                                 │
│ Your data stays private unless  │
│ you explicitly share it.        │
│                                 │
│ [Join Circle] [Decline]         │
└─────────────────────────────────┘
```

---

### Flow 6: Map View

```
Map Tab
┌─────────────────────────────────┐
│ [Personal] [Circle]    [⚙️]     │
├─────────────────────────────────┤
│                                 │
│         [Map View]              │
│                                 │
│    📍 (Your memories)           │
│    📍 📍                        │
│         📍                      │
│                                 │
│    📍 (Alice's shares)          │
│         📍                      │
│                                 │
│  [Current Location 🎯]          │
│                                 │
├─────────────────────────────────┤
│ [List View Toggle]              │
└─────────────────────────────────┘
```

**Tap pin → Annotation:**
```
┌─────────────────────────────────┐
│ 🌿 Blue Dream                   │
│ Yesterday • ★★★★★              │
│ 📍 Home                         │
│                                 │
│ [View Memory]                   │
└─────────────────────────────────┘
```

**Map Settings (⚙️):**
```
┌─────────────────────────────────┐
│ Map Settings                    │
├─────────────────────────────────┤
│ Show my memories                │
│ [✓] All locations               │
│ [ ] Favorites only              │
│                                 │
│ Show Circle memories            │
│ [✓] All members                 │
│ [✓] Alice                       │
│ [✓] Bob                         │
│ [ ] Carol                       │
│                                 │
│ Pin Style                       │
│ ( ) Strain name                 │
│ (•) Effect (color-coded)        │
│ ( ) Rating                      │
│                                 │
│ Privacy                         │
│ Fuzzy locations only (~500m)    │
└─────────────────────────────────┘
```

---

### Flow 6.5: Discover & Use Dispensary Deals

**Discover Deals on Map**
```
Map Tab → Toggle [Personal] [Circle] [Deals]
┌─────────────────────────────────┐
│ [Personal] [Circle] [Deals] ⚙️  │
├─────────────────────────────────┤
│         [Map View]              │
│                                 │
│    📍 (Your memories)           │
│    🎟️ (Deal pins - highlighted) │
│    🎟️ 20% off                  │
│       Blue Dream                │
│                                 │
│  [Current Location 🎯]          │
└─────────────────────────────────┘
```

**Tap Deal Pin → Deal Details:**
```
┌─────────────────────────────────┐
│ 🎟️ Deal at Cookies SF          │
├─────────────────────────────────┤
│ 20% off Blue Dream              │
│ Valid Dec 10-17                 │
│                                 │
│ Limited time! Our best hybrid.  │
│ Perfect for creativity & focus. │
│                                 │
│ ⭐ 4.6★ from 87 users           │
│ Top effects: relaxed, creative  │
│                                 │
│ 📍 0.3 mi away                  │
│ Cookies SF • 1234 Haight St     │
│                                 │
│ [Get Directions] [Save Deal]    │
└─────────────────────────────────┘
```

**After Using Deal → Link Bud:**
```
Create Memory View
┌─────────────────────────────────┐
│ New Bud                     [X] │
├─────────────────────────────────┤
│ 🌿 What did you smoke?          │
│   [Blue Dream_______________]   │
│                                 │
│ 🎟️ Used a deal?                │
│   [✓] 20% off @ Cookies SF      │
│                                 │
│ ⭐ Rating                       │
│   ★★★★★                         │
│                                 │
│ 📝 Notes                        │
│   [Great deal, quality was...]  │
│                                 │
│ 😊 Effects                      │
│   [relaxed] [creative] [+]      │
│                                 │
│ ──────────────────────────────  │
│                                 │
│ 💡 Help Cookies SF improve?     │
│ [ ] Share anonymous feedback    │
│                                 │
│ Tapping opens:                  │
│ ┌───────────────────────────┐   │
│ │ Share anonymous feedback? │   │
│ │                           │   │
│ │ What's shared (aggregate  │   │
│ │ only, n ≥ 75 threshold):  │   │
│ │ • Rating (1-5 stars)      │   │
│ │ • Effects selected        │   │
│ │ • Consumption method      │   │
│ │ • Time of day (general)   │   │
│ │                           │   │
│ │ NEVER shared:             │   │
│ │ • Your identity/DID       │   │
│ │ • Your location           │   │
│ │ • Personal notes          │   │
│ │                           │   │
│ │ [Share] [No Thanks]       │   │
│ └───────────────────────────┘   │
│                                 │
│         [Save Bud]              │
└─────────────────────────────────┘
```

**Saved Deals (Optional Tab):**
```
Profile Tab → Saved Deals
┌─────────────────────────────────┐
│ Saved Deals (3)                 │
├─────────────────────────────────┤
│ ┌─────────────────────────────┐ │
│ │ 🎟️ 20% off Blue Dream       │ │
│ │ Cookies SF • Expires Dec 17 │ │
│ │ 0.3 mi away                 │ │
│ │ [View on Map] [Remove]      │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ 🎟️ BOGO Edibles             │ │
│ │ SPARC • Expires Dec 20      │ │
│ │ 1.2 mi away                 │ │
│ │ [View on Map] [Remove]      │ │
│ └─────────────────────────────┘ │
└─────────────────────────────────┘
```

---

### Flow 7: Ask Buds (Agent)

```
Agent Tab
┌─────────────────────────────────┐
│ Ask Buds                        │
├─────────────────────────────────┤
│                                 │
│ 💬 Your Cannabis Expert         │
│                                 │
│ Quick questions:                │
│ [What strains made me anxious?] │
│ [Best for creative work?]       │
│ [Where to buy Blue Dream?]      │
│                                 │
│ Or ask anything...              │
│ [Type your question_________]   │
│                           [Send]│
│                                 │
├─────────────────────────────────┤
│ Recent queries:                 │
│ • What's the entourage effect?  │
│ • Best vape temperature?        │
└─────────────────────────────────┘
```

**Query Response:**
```
┌─────────────────────────────────┐
│ [← Back]                        │
├─────────────────────────────────┤
│ Q: What strains made me anxious?│
│                                 │
│ 🤖 Based on your 47 sessions:   │
│                                 │
│ You experienced anxiety with:   │
│                                 │
│ 1. Sour Diesel (3/3 sessions)   │
│    • High THC (26-28%)          │
│    • Sativa-dominant            │
│    [View sessions]              │
│                                 │
│ 2. Super Lemon Haze (2/2)       │
│    • Also sativa-dominant       │
│    • You noted: "Too intense"   │
│    [View sessions]              │
│                                 │
│ 💡 Recommendation:              │
│ Stick to hybrids or indicas     │
│ under 22% THC, especially with  │
│ CBD (>1%) or linalool.          │
│                                 │
│ Suggested: [Blue Dream] [Gelato]│
│                                 │
│ ──────────────────────────────  │
│ Helpful? [👍] [👎]             │
│                                 │
│ [Ask follow-up_____________]    │
└─────────────────────────────────┘
```

**Citations (tappable):**
```
Tap [View sessions]
  ↓
Opens list of relevant memories
with highlighted text
```

---

### Flow 8: Profile & Settings

```
Profile Tab (Me)
┌─────────────────────────────────┐
│ [avatar]                        │
│ Alice                           │
│ @alice                          │
│ Member since Dec 2024           │
│                                 │
│ [Edit Profile]                  │
│                                 │
├─────────────────────────────────┤
│ Your Stats (Private)            │
│ ┌────────┬────────┬───────────┐ │
│ │   47   │   23   │    4.2★   │ │
│ │Sessions│Strains │Avg Rating │ │
│ └────────┴────────┴───────────┘ │
│                                 │
│ Top Strains                     │
│ 1. Blue Dream (6 sessions)      │
│ 2. Gelato (4 sessions)          │
│ 3. Jack Herer (3 sessions)      │
│                                 │
│ Top Effects                     │
│ [relaxed] [creative] [happy]    │
│                                 │
├─────────────────────────────────┤
│ Settings                        │
│ > Privacy                       │
│ > Notifications                 │
│ > Data & Storage                │
│ > Help & Support                │
│ > About                         │
│                                 │
│ [Sign Out]                      │
└─────────────────────────────────┘
```

**Privacy Settings:**
```
┌─────────────────────────────────┐
│ Privacy                    [←]  │
├─────────────────────────────────┤
│ Location                        │
│ [ ] Enable location capture     │
│     (OFF by default)            │
│                                 │
│ Default share mode:             │
│ (•) Private                     │
│ ( ) Share to Circle             │
│                                 │
│ Location sharing:               │
│ ( ) Never share location        │
│ (•) Fuzzy location (~500m)      │
│ ( ) Precise location (NOT       │
│     RECOMMENDED - reduces       │
│     privacy)                    │
│                                 │
│ [ ] Delay location share        │
│     When ON: Location only      │
│     shared after 2+ hours       │
│                                 │
├─────────────────────────────────┤
│ AI Assistant (Agent)            │
│ [ ] Enable AI Assistant         │
│     Tap to see privacy notice   │
│                                 │
│ When first enabled, shows:      │
│ ┌───────────────────────────┐   │
│ │ Enable AI Assistant?      │   │
│ │                           │   │
│ │ Privacy notice:           │   │
│ │ • Receipts sent to LLM    │   │
│ │ • NOT stored by provider  │   │
│ │ • Disable anytime         │   │
│ │                           │   │
│ │ [Enable] [Not Now]        │   │
│ └───────────────────────────┘   │
│                                 │
├─────────────────────────────────┤
│ Data Export                     │
│ [Export all memories (JSON)]    │
│ [Request data deletion]         │
│ [Delete account permanently]    │
└─────────────────────────────────┘
```

---

## Navigation Structure

```
Main Tab Bar (Bottom)
┌─────────────────────────────────┐
│ [Timeline] [Map] [+] [Circle] [@]│
└─────────────────────────────────┘
```

| Tab | Icon | Function |
|-----|------|----------|
| Timeline | 📖 | Your memories (chronological) |
| Map | 🗺️ | Memories with location |
| + (FAB) | ➕ | Create new memory (primary action) |
| Circle | 👥 | Shared memories + members |
| Profile | @ | Your profile + settings |

**Optional 6th tab (v0.2):**
| Agent | 💬 | Ask Buds questions |

---

## Design System

### Colors

**Primary Palette:**
- Primary: `#4CAF50` (Cannabis green)
- Secondary: `#8BC34A` (Light green)
- Accent: `#FF6B35` (Orange for CTA)
- Background: `#F5F5F5` (Light gray)
- Surface: `#FFFFFF` (White cards)

**Semantic Colors:**
- Success: `#4CAF50`
- Warning: `#FFC107`
- Error: `#F44336`
- Info: `#2196F3`

**Effect Tags:**
- Relaxed: Soft blue
- Creative: Purple
- Energized: Yellow
- Happy: Orange
- Anxious: Red (warning)

### Typography

**System Font:** SF Pro (iOS native)

| Style | Size | Weight |
|-------|------|--------|
| Title | 28pt | Bold |
| Headline | 22pt | Semibold |
| Body | 17pt | Regular |
| Caption | 13pt | Regular |
| Tag | 12pt | Medium |

### Spacing

- XS: 4pt
- S: 8pt
- M: 16pt
- L: 24pt
- XL: 32pt

### Components

**Memory Card:**
- Corner radius: 12pt
- Shadow: 0 2pt 8pt rgba(0,0,0,0.1)
- Padding: 16pt

**Buttons:**
- Primary: Filled, accent color
- Secondary: Outlined, primary color
- Tertiary: Text only

**Input Fields:**
- Corner radius: 8pt
- Border: 1pt solid gray
- Focus: 2pt accent color

---

## Accessibility

**WCAG 2.1 AA Compliance:**

✅ Color contrast ratio ≥ 4.5:1
✅ Touch targets ≥ 44pt × 44pt
✅ VoiceOver labels on all interactive elements
✅ Dynamic Type support (text scales)
✅ Reduce Motion support (disable animations)

**Voice Over labels:**
```swift
// Memory card
.accessibilityLabel("Blue Dream memory, 5 stars, yesterday at 8:32pm, private")

// FAB
.accessibilityLabel("Add new memory")
.accessibilityHint("Opens form to create a memory")
```

---

## Animations & Transitions

**Timing:**
- Quick: 0.2s (button press)
- Standard: 0.3s (sheet present)
- Slow: 0.5s (page transition)

**Easing:**
- Standard: `easeInOut`
- Spring: `spring(response: 0.3, dampingFraction: 0.7)`

**Examples:**
```swift
// Sheet presentation
.sheet(isPresented: $showCreate) {
    CreateMemoryView()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
}

// Card tap
.onTapGesture {
    withAnimation(.spring()) {
        selectedMemory = memory
    }
}
```

---

## Empty States

**Timeline (no memories yet):**
```
┌─────────────────────────────────┐
│                                 │
│           🌿                    │
│                                 │
│   Start tracking your           │
│   cannabis experiences          │
│                                 │
│   Tap + to create your          │
│   first memory                  │
│                                 │
│      [Create Memory]            │
│                                 │
└─────────────────────────────────┘
```

**Circle (no members):**
```
┌─────────────────────────────────┐
│                                 │
│           👥                    │
│                                 │
│   Your Circle is empty          │
│                                 │
│   Invite up to 12 close friends │
│   to share memories privately   │
│                                 │
│      [Invite Friends]           │
│                                 │
└─────────────────────────────────┘
```

---

## Error States

**Network error:**
```
┌─────────────────────────────────┐
│ ⚠️ Connection Error             │
│                                 │
│ Unable to sync with Circle.     │
│ Your data is saved locally.     │
│                                 │
│ [Retry]  [Dismiss]              │
└─────────────────────────────────┘
```

**Location permission denied:**
```
┌─────────────────────────────────┐
│ 📍 Location Access Needed       │
│                                 │
│ To capture location with        │
│ memories, enable location in    │
│ Settings.                       │
│                                 │
│ [Open Settings]  [Skip]         │
└─────────────────────────────────┘
```

---

**Next:** See [DISPENSARY_INSIGHTS.md](./DISPENSARY_INSIGHTS.md) for B2B product spec.
