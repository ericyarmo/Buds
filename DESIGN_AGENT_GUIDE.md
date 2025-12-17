# Design Expert Agent - Buds UX/UI Guide

Complete design direction, component library, and UX patterns for Buds v0.1+.

**Context:** Private cannabis memory sharing app. Brand: forest premium, cozy dank café vibes. Not stoner kitsch.

---

## Part 1: Component Library

### Core Components to Build

#### 1. BudsButton (Reusable Button)
```swift
enum BudsButtonStyle {
    case primary    // Filled, budsPrimary
    case secondary  // Outlined, budsDivider border
    case destructive // Filled, budsDestructive
    case ghost      // Text only, no background
}

BudsButton("Save Memory", style: .primary) {
    // action
}
```

**Variants:**
- Full width vs. compact
- Icon + text
- Loading state (spinner)
- Disabled state (50% opacity)

---

#### 2. BudsCard (Container)
```swift
BudsCard {
    VStack(alignment: .leading) {
        // content
    }
}
.onTapGesture { /* optional tap handler */ }
```

**Features:**
- Auto padding (.m)
- Auto corner radius (.medium)
- Auto shadow
- Optional tap gesture
- Optional swipe actions

---

#### 3. BudsTag (Chip/Badge)
```swift
BudsTag("Relaxed", color: .budsPurple)
```

**Variants:**
- Selectable (toggle state)
- Dismissible (X button)
- Icon + text
- Size: small / medium / large

---

#### 4. BudsTextField (Styled Input)
```swift
BudsTextField("Strain name", text: $strainName)
    .keyboardType(.default)
    .submitLabel(.done)
```

**Features:**
- Floating label (optional)
- Error state (red border)
- Character count
- Clear button

---

#### 5. BudsRating (Star Rating)
```swift
BudsRating(rating: $rating, maxRating: 5)
```

**Features:**
- Interactive (tap to rate)
- Read-only mode
- Half stars (optional)
- Custom icon (star, leaf, etc.)

---

#### 6. ImageCarousel (Photo Swiper)
```swift
ImageCarousel(images: imageData, currentIndex: $currentIndex)
```

**Features:**
- Swipe left/right
- Page indicator dots
- Tap to fullscreen
- Pinch to zoom (fullscreen only)
- 3 images max per memory

---

#### 7. EmptyState (Placeholder)
```swift
EmptyState(
    icon: "photo.on.rectangle",
    title: "No photos yet",
    message: "Tap the camera to capture memories",
    action: ("Add Photo", addPhoto)
)
```

**Usage:**
- Empty timeline
- No photos selected
- No search results

---

#### 8. BudsNavigationBar (Custom Nav)
```swift
BudsNavigationBar(
    title: "Memory Details",
    leading: backButton,
    trailing: moreButton
)
```

**Features:**
- Large title / inline title
- Transparent scroll behavior
- Custom leading/trailing buttons

---

### Component File Structure
```
Shared/
├── Components/
│   ├── Buttons/
│   │   ├── BudsButton.swift
│   │   └── BudsIconButton.swift
│   ├── Cards/
│   │   ├── BudsCard.swift
│   │   └── MemoryCard.swift           (already exists)
│   ├── Inputs/
│   │   ├── BudsTextField.swift
│   │   ├── BudsTextEditor.swift
│   │   └── BudsRating.swift
│   ├── Tags/
│   │   └── BudsTag.swift
│   ├── Media/
│   │   ├── ImageCarousel.swift
│   │   ├── PhotoPicker.swift
│   │   └── CameraCapture.swift
│   └── States/
│       ├── EmptyState.swift
│       └── LoadingState.swift
```

---

## Part 2: Screen Designs

### Timeline View (Redesign)

**Current issues:**
- Generic empty state
- No visual hierarchy
- Missing filters

**New design:**

```
┌─────────────────────────────┐
│ Timeline            [filter]│ <- Nav bar
│                              │
│ ┌─────────────────────────┐ │
│ │ [Photo carousel]        │ │ <- Memory card
│ │ ○ ○ ●                   │ │    (3 dots = 3 photos)
│ │                         │ │
│ │ Blue Dream          ⭐⭐⭐⭐⭐│
│ │ Flower • Joint          │ │
│ │ "Felt super creative..." │
│ │                         │ │
│ │ [Relaxed] [Creative]    │ │ <- Effect tags
│ │                         │ │
│ │ 2 hours ago             │ │
│ └─────────────────────────┘ │
│                              │
│ ┌─────────────────────────┐ │
│ │ [Another card...]       │ │
│ └─────────────────────────┘ │
│                              │
│           [+]                │ <- FAB (floating action)
└─────────────────────────────┘
```

**Enhancements:**
- Pull to refresh
- Infinite scroll (pagination later)
- Swipe card left → Delete
- Swipe card right → Favorite
- Filter button → Modal sheet

---

### Memory Detail View (New)

**Full-screen modal when tapping a card:**

```
┌─────────────────────────────┐
│ [←]              [•••]       │ <- Nav: Back, More menu
│                              │
│ ┌─────────────────────────┐ │
│ │                         │ │
│ │   [Large photo]         │ │ <- Fullscreen image
│ │   Swipe for more        │ │    Tap to zoom
│ │                         │ │
│ │        ○ ● ○             │ │ <- Page dots
│ └─────────────────────────┘ │
│                              │
│ Blue Dream              ⭐⭐⭐⭐⭐│ <- Strain + rating
│ Flower • Joint              │ <- Type + method
│                              │
│ "This strain was perfect... │ <- Notes (full)
│  Really helped me focus..."  │
│                              │
│ Effects                      │
│ [Relaxed] [Creative] [Happy] │
│                              │
│ Product Details              │
│ Brand: Cookies               │
│ THC: 23.5% • CBD: 0.8%       │
│                              │
│ 📍 Home • 2 hours ago        │ <- Location + time
│                              │
│ ┌──────────┐ ┌──────────┐  │
│ │  Edit    │ │  Delete  │  │ <- Actions
│ └──────────┘ └──────────┘  │
│                              │
└─────────────────────────────┘
```

**Features:**
- Scroll to see all content
- Sticky header (title stays visible)
- Edit → Opens CreateMemoryView (pre-filled)
- Delete → Confirmation alert
- Share button (future: Circle sharing)

---

### Create Memory View (Enhanced)

**Add photo section at top:**

```
┌─────────────────────────────┐
│ New Memory          [Cancel] │
│                              │
│ Photos (3 max)               │
│ ┌─────┐ ┌─────┐ ┌─────┐    │
│ │Photo│ │Photo│ │ +   │    │ <- Tap + for picker
│ │  1  │ │  2  │ │     │    │    Tap photo to replace
│ └─────┘ └─────┘ └─────┘    │    Long press to delete
│                              │
│ Strain                       │
│ ┌─────────────────────────┐ │
│ │ Blue Dream             │ │
│ └─────────────────────────┘ │
│                              │
│ Product Type                 │
│ [Flower ▾]                   │
│                              │
│ Rating                       │
│ ⭐⭐⭐⭐⭐                         │
│                              │
│ Notes                        │
│ ┌─────────────────────────┐ │
│ │                         │ │
│ │ (TextEditor)            │ │
│ │                         │ │
│ └─────────────────────────┘ │
│                              │
│ Effects                      │
│ [Relaxed] [Creative] [Happy] │
│ [Focused] [Sleepy] [...]     │
│                              │
│ [Save Memory]                │
└─────────────────────────────┘
```

**New features:**
- Photo section at top (3 max)
- Camera + Library buttons
- Optional: "Scan & Fill" (image analysis)
- Validate: Strain name required

---

### Onboarding Flow (Phase 4)

#### 1. Welcome Screen
```
┌─────────────────────────────┐
│                              │
│         🌿 Buds              │
│                              │
│   Private cannabis memories  │
│   for you and 12 friends     │
│                              │
│                              │
│ ┌─────────────────────────┐ │
│ │  Get Started            │ │
│ └─────────────────────────┘ │
│                              │
│  By continuing, you agree to │
│  Terms & Privacy Policy      │
│                              │
└─────────────────────────────┘
```

#### 2. Phone Verification
```
┌─────────────────────────────┐
│ [←]  Phone Verification      │
│                              │
│ Enter your phone number      │
│ to secure your account       │
│                              │
│ ┌─────────────────────────┐ │
│ │ +1 (555) 123-4567      │ │
│ └─────────────────────────┘ │
│                              │
│ ┌─────────────────────────┐ │
│ │  Send Code              │ │
│ └─────────────────────────┘ │
│                              │
│ Your number is never shared  │
│                              │
└─────────────────────────────┘
```

#### 3. Code Verification
```
┌─────────────────────────────┐
│ [←]  Enter Code              │
│                              │
│ Enter the 6-digit code sent  │
│ to +1 (555) 123-4567         │
│                              │
│  ┌───┐ ┌───┐ ┌───┐          │
│  │ 1 │ │ 2 │ │ 3 │ ...      │
│  └───┘ └───┘ └───┘          │
│                              │
│ Didn't receive? Resend       │
│                              │
└─────────────────────────────┘
```

#### 4. Profile Setup
```
┌─────────────────────────────┐
│      Set Up Profile          │
│                              │
│ What should we call you?     │
│ (Only visible to you)        │
│                              │
│ ┌─────────────────────────┐ │
│ │ Display Name            │ │
│ └─────────────────────────┘ │
│                              │
│ Preferences                  │
│                              │
│ ┌─────────────────────────┐ │
│ │ Track location     [○]  │ │ <- Toggle (default OFF)
│ └─────────────────────────┘ │
│                              │
│ ┌─────────────────────────┐ │
│ │  Continue               │ │
│ └─────────────────────────┘ │
│                              │
└─────────────────────────────┘
```

---

## Part 3: UX Patterns

### Navigation Patterns

#### Primary Nav (Tab Bar)
```
┌─────────────────────────────┐
│                              │
│      [Content Area]          │
│                              │
└─────────────────────────────┘
  Timeline   Map   Circle  You
     ●        ○      ○      ○
```

**Tabs:**
1. **Timeline** (book.fill) - Main feed
2. **Map** (map.fill) - Location-based (Phase 5+)
3. **Circle** (person.2.fill) - Friends (Phase 6)
4. **You** (person.fill) - Profile/Settings

#### Modal Patterns
- **Full screen:** Onboarding, Create/Edit memory
- **Sheet (half):** Filters, Settings
- **Alert:** Delete confirmation, Errors

#### Gestures
- **Tap card:** Open detail view
- **Long press card:** Quick actions (favorite, delete)
- **Swipe left:** Delete
- **Swipe right:** Favorite (toggle)
- **Pull down:** Refresh timeline

---

### Loading States

#### Timeline Loading
```
┌─────────────────────────────┐
│ Timeline                     │
│                              │
│ ┌─────────────────────────┐ │
│ │ ░░░░░░░░░░░░░░░░░░░░░░  │ │ <- Skeleton cards
│ │ ░░░░░░░░░░░░░░░░░░░░░░  │ │
│ └─────────────────────────┘ │
└─────────────────────────────┘
```

#### Image Loading
```
┌───────────┐
│           │
│     ⌛     │ <- Spinner while loading
│           │
└───────────┘
```

#### Button Loading
```
┌──────────────┐
│  Saving... ⌛ │ <- Disable + spinner
└──────────────┘
```

---

### Error States

#### Form Error
```
┌─────────────────────────────┐
│ Strain                       │
│ ┌─────────────────────────┐ │
│ │                         │ │ <- Red border
│ └─────────────────────────┘ │
│ ⚠ Strain name is required    │ <- Error message
└─────────────────────────────┘
```

#### Network Error
```
┌─────────────────────────────┐
│         ⚠                    │
│  Couldn't load memories      │
│                              │
│  [Try Again]                 │
└─────────────────────────────┘
```

#### Empty Search
```
┌─────────────────────────────┐
│         🔍                   │
│   No results for "indica"    │
│                              │
│   Try a different search     │
└─────────────────────────────┘
```

---

### Confirmation Patterns

#### Delete Confirmation
```
Alert:
┌─────────────────────────────┐
│  Delete this memory?         │
│                              │
│  This can't be undone.       │
│                              │
│  [Cancel]     [Delete]       │
└─────────────────────────────┘
```

#### Success Toast
```
┌─────────────────────────────┐
│  ✓ Memory saved              │ <- Toast at top
└─────────────────────────────┘
(Auto-dismiss after 2s)
```

---

## Part 4: Animation Guidelines

### Micro-interactions

#### Button Press
- Scale: 0.95 on press
- Duration: 0.2s
- Spring: dampingFraction 0.6

#### Card Tap
- Scale: 0.98 on press
- Transition to detail: sheet from bottom
- Duration: 0.3s

#### Photo Swipe
- Spring animation
- Resistance at edges
- Snap to closest photo

#### Tag Toggle
- Fade background color
- Scale icon slightly
- Duration: 0.15s

---

### Transitions

#### Screen Transitions
```swift
.transition(.move(edge: .bottom))  // Sheet from bottom
.transition(.opacity)              // Fade in/out
.transition(.slide)                // Horizontal slide
```

#### List Updates
```swift
.animation(.default, value: memories.count)  // Smooth insert/delete
```

---

## Part 5: Responsive Design

### iPhone Sizes

#### iPhone 15 Pro (393pt wide)
- **Card padding:** 16pt sides
- **Max card width:** 361pt
- **Image aspect:** 4:3 or 16:9

#### iPhone SE (375pt wide)
- Same padding
- Slightly smaller cards
- Text scales down via Dynamic Type

#### iPhone 15 Pro Max (430pt wide)
- Same padding (not stretched)
- Consider 2-column grid (Phase 7+)

---

### Keyboard Handling

#### TextEditor with Keyboard
```swift
.ignoresSafeArea(.keyboard, edges: .bottom)  // Scroll with keyboard
```

#### TextField in Form
- Auto-scroll to focused field
- "Done" button dismisses keyboard
- Submit label: `.done` or `.next`

---

## Part 6: Accessibility

### VoiceOver

#### Button Labels
```swift
Button {
    deleteMemory()
} label: {
    Image(systemName: "trash")
}
.accessibilityLabel("Delete memory")
.accessibilityHint("Removes this memory from your timeline")
```

#### Custom Controls
```swift
ImageCarousel(...)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Memory photos, \(currentIndex + 1) of \(images.count)")
    .accessibilityAddTraits(.isImage)
```

---

### Dynamic Type

#### Scalable Layouts
```swift
@ScaledMetric var iconSize: CGFloat = 24
@ScaledMetric var spacing: CGFloat = 16

Image(systemName: "star")
    .font(.system(size: iconSize))
```

#### Fixed Sizes (When Necessary)
- Tab bar icons: Fixed 28pt
- Photos: Fixed aspect, but responsive width

---

### Color Contrast

All text meets WCAG AA minimum:

| Text | Background | Ratio | Pass |
|------|------------|-------|------|
| budsTextPrimary | budsCream | 18:1 | ✅ |
| budsTextSecondary | budsCream | 7:1 | ✅ |
| White | budsPrimary | 12:1 | ✅ |
| White | budsPurple | 10:1 | ✅ |

---

## Part 7: Performance

### Image Optimization

#### Compression
```swift
// When saving to blobs table:
let compressed = image.jpegData(compressionQuality: 0.7)
// Target: <2MB per image
```

#### Thumbnails
- Generate 400x300 thumbnail for cards
- Store full resolution for detail view
- Lazy load images (only in viewport)

---

### List Performance

#### LazyVStack
```swift
ScrollView {
    LazyVStack(spacing: .m) {
        ForEach(memories) { memory in
            MemoryCard(memory: memory)
        }
    }
}
```

**Benefits:**
- Only renders visible cards
- Smooth scrolling
- Low memory usage

---

## Part 8: Testing Checklist

### Visual Testing

- [ ] Light mode + Dark mode
- [ ] iPhone SE (small screen)
- [ ] iPhone 15 Pro Max (large screen)
- [ ] Dynamic Type (smallest + largest)
- [ ] VoiceOver enabled
- [ ] Reduce Motion enabled
- [ ] High Contrast mode

---

### Interaction Testing

- [ ] All buttons tappable
- [ ] All gestures work (swipe, long press)
- [ ] Forms validate correctly
- [ ] Keyboard doesn't hide inputs
- [ ] Navigation works both ways
- [ ] Alerts/sheets dismiss properly

---

### Edge Cases

- [ ] Empty states (no memories, no photos)
- [ ] Single item (no scrolling needed)
- [ ] Max items (performance acceptable)
- [ ] Long text (wraps properly)
- [ ] Special characters in text
- [ ] Network offline
- [ ] Low battery mode

---

## Part 9: Implementation Priorities

### Phase 3 (Images) - Critical
1. ImageCarousel component
2. PhotoPicker component
3. Update MemoryCard with carousel
4. MemoryDetailView (new)
5. Update CreateMemoryView (photo section)

### Phase 4 (Auth) - Critical
1. PhoneAuthView
2. VerificationCodeView
3. ProfileSetupView
4. OnboardingCoordinator
5. Update BudsApp (conditional nav)

### Phase 5+ (Future)
1. BudsButton component library
2. BudsCard standardization
3. BudsTextField component
4. Filter modal
5. Settings screen
6. Search functionality

---

## Part 10: Brand Voice Examples

### Onboarding
- ✅ "Welcome to Buds"
- ✅ "Your private memory space"
- ❌ "Get lit with Buds!"

### Empty States
- ✅ "No memories yet"
- ✅ "Start by adding your first memory"
- ❌ "Nothing to see here"

### Errors
- ✅ "Couldn't save that"
- ✅ "Check your connection and try again"
- ❌ "Error 500: Internal server error"

### Success
- ✅ "Memory saved"
- ✅ "Photo added"
- ❌ "Operation successful"

---

**Status:** Complete design system + UX guide ready.

**Next:** Build components, implement screens, test thoroughly.

**Vibe check:** Forest premium ✅ Stoner kitsch ❌
