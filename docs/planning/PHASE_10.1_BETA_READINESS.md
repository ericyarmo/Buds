# Phase 10.1: Beta Readiness - 20-50 Real Users

**Date**: December 28, 2025
**Timeline**: 18-24 hours
**Status**: Ready for Approval → Implementation
**Goal**: Ship TestFlight beta that 20-50 real users can use without frustration

---

## Executive Summary

**What We're Building**:
- Simplified create flow (name → save → enrich)
- Visual enrichment signals (dashed borders for minimal buds)
- Full memory detail view
- Edit/enrich flow with all metadata
- Delete memory with confirmation
- Reactions system (5 emojis: ❤️ 😂 🔥 👀 😌)
- Onboarding, settings, polish

**Why This Matters**:
- Current create flow too complex → users abandon
- No detail view → dead end after creating buds
- No reactions → no social engagement in shared jars
- No visual feedback → users don't know buds need enrichment

**Success Criteria**:
- Create bud in <15 seconds (just name)
- Enrich buds incrementally (photos, rating, effects later)
- Visual cues show enrichment status
- 20-50 users can use without major friction

---

## Overview

**Current State**: All core infrastructure works (E2EE, DB, receipts, jars, members, create flows).
**Problem**: Missing connectors, polish, and user guidance make it feel "half-broken".
**Goal**: Fill gaps so users can create, view, edit, delete buds without hitting dead ends.

**Parallel Track**: While building this, developer continues Phases 11-14 (map, shop, AI) separately.

---

## Key UX Changes

### 🎯 **Simplified Create Flow**
**Old**: Long form with all fields required upfront
**New**: Two-step approach
1. **Quick Create**: Name + optional image(s) → Done!
2. **Enrich Later**: Tap into detail → Edit → Add rating, effects, flavors, notes

**Why**: Lower friction to log a bud. Enrichment can happen later when user has time.

### 💬 **Reactions System**
**What**: Members can react to buds in shared jars with 5 preset emojis
**Emojis**: ❤️ (heart), 😂 (laughing), 🔥 (fire), 👀 (eyes), 😌 (chilled)
**UI**: Stack reactions with counts (e.g., "❤️ 3  🔥 2")
**Why**: Social engagement, low-effort interaction

---

## Module 1: Memory System (Bud CRUD + Reactions)

**Current State**:
- ✅ Can create buds (camera, form, metadata, images) - BUT too complex
- ✅ Can view bud list (MemoryListCard in JarDetailView)
- ❌ Can't tap into bud detail
- ❌ Can't edit existing buds
- ❌ Can't delete individual buds
- ❌ No reactions system

### 1.0 Simplify Create Memory Flow (2-3 hours)

**Build**: Reduce create flow to bare minimum, then immediately show enrich view.

**Current Problem**: Long form is intimidating, slows down logging. Users abandon mid-flow.

**New Two-Step Flow**:
1. **Quick Create** (minimal friction):
   - Tap FAB or "Add Bud" → JarPickerView (or already in jar)
   - Simple form: Name (required) + Type (optional) + Save
   - **No images in create** - moved to enrich step
2. **Immediate Enrich Invitation** (post-save):
   - After save → Auto-navigate to EditMemoryView
   - Pre-filled with name + type
   - User can add photos, rating, effects, flavors, notes
   - "Skip" button to exit immediately
   - Toast on skip: "Bud saved! Enrich it anytime"

**Why This Works**:
- Lower barrier to start (just name!)
- Momentum: User already committed, more likely to enrich
- Optional: Can skip if in a hurry
- Visual signal: Unenriched buds look different in list

---

**Implementation Details**:

**Step 1: Simplify CreateMemoryView**

**Current State**:
```swift
// CreateMemoryView.swift - Current (long form)
- @State productName: String
- @State productType: String
- @State rating: Int
- @State effects: [String]
- @State flavors: [String]
- @State notes: String
- @State selectedImages: [UIImage]
```

**New State** (minimal):
```swift
// CreateMemoryView.swift - Simplified
- @State productName: String = ""          // Required
- @State productType: ProductType = .flower // Optional dropdown
- @Environment(\.dismiss) var dismiss
```

**UI Layout**:
```
┌─────────────────────────────────────┐
│  New Bud                        [×] │
├─────────────────────────────────────┤
│                                     │
│  Strain Name *                      │
│  ┌────────────────────────────────┐│
│  │ Blue Dream                     ││
│  └────────────────────────────────┘│
│                                     │
│  Type                               │
│  ┌────────────────────────────────┐│
│  │ 🌿 Flower                  ▼  ││
│  └────────────────────────────────┘│
│  Options: Flower, Edible,          │
│  Concentrate, Vape, Tincture,      │
│  Topical, Other                    │
│                                     │
│  Spacer()                           │
│                                     │
│  ┌────────────────────────────────┐│
│  │      Continue to Details       ││  ← .budsPrimary
│  └────────────────────────────────┘│
│                                     │
│  Text: "Add photos, rating, and    │
│  notes on the next screen"         │
│  (.budsTextSecondary, .caption)    │
└─────────────────────────────────────┘
```

**Save Logic**:
```swift
func saveBud() async {
    guard !productName.isEmpty else {
        showError = true
        return
    }

    // Create minimal receipt
    let memory = try await repository.create(
        strainName: productName,
        productType: productType.rawValue,
        rating: 0,              // Default
        effects: [],            // Empty
        flavors: [],            // Empty
        notes: "",              // Empty
        imageCIDs: [],          // No images yet
        jarID: selectedJarID
    )

    dismiss()

    // CRITICAL: Navigate to EditMemoryView
    onSaveComplete(memory.id)  // Callback to parent
}
```

**Navigation Flow**:
```swift
// JarDetailView.swift or ShelfView.swift
@State private var showingCreateMemory = false
@State private var memoryToEnrich: UUID?

.sheet(isPresented: $showingCreateMemory) {
    CreateMemoryView(jarID: jar.id) { createdMemoryID in
        // On save complete, show enrich view
        memoryToEnrich = createdMemoryID
    }
}
.sheet(item: $memoryToEnrich) { memoryID in
    EditMemoryView(memoryID: memoryID, isEnrichMode: true)
}
```

---

**Step 2: Visual Signals for Unenriched Buds**

**Problem**: All buds look the same in list. Users don't know which need enrichment.

**Solution**: Different card design based on "enrichment score".

**Enrichment Score Logic**:
```swift
// MemoryListItem.swift - Add computed property
extension MemoryListItem {
    var enrichmentLevel: EnrichmentLevel {
        var score = 0
        if rating > 0 { score += 1 }
        if !effects.isEmpty { score += 1 }
        if !flavors.isEmpty { score += 1 }
        if !notes.isEmpty { score += 1 }
        if thumbnailCID != nil { score += 1 }

        switch score {
        case 0...1: return .minimal      // Just name, maybe type
        case 2...3: return .partial      // Some details
        case 4...5: return .complete     // Fully enriched
        default: return .minimal
        }
    }
}

enum EnrichmentLevel {
    case minimal   // Red/orange accent, dashed border
    case partial   // Yellow accent
    case complete  // Green accent, solid border
}
```

**Visual Design**:
```
Minimal (needs enrichment):
┌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┐  ← Dashed border
│ 📝 Blue Dream          │  ← 📝 icon
│ Flower                 │
│ ⭐️ Not rated yet       │  ← Text hint
│ Just now               │
│ [+ Add Details]        │  ← Orange button
└╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┘

Partial (some enrichment):
┌─────────────────────────┐  ← Solid border
│ 🌿 Blue Dream          │
│ ⭐️⭐️⭐️⭐️               │
│ 2 hours ago            │
│ [Enrich More]          │  ← Subtle link
└─────────────────────────┘

Complete (fully enriched):
┌─────────────────────────┐
│ [Image]  Blue Dream    │
│          ⭐️⭐️⭐️⭐️⭐️    │
│          Relaxed • Happy│
│          2 hours ago   │
└─────────────────────────┘
```

**MemoryListCard.swift Changes**:
```swift
struct MemoryListCard: View {
    let item: MemoryListItem
    let onTap: () async -> Void

    private var enrichmentLevel: EnrichmentLevel {
        item.enrichmentLevel
    }

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail or icon
            thumbnailView

            VStack(alignment: .leading, spacing: 4) {
                Text(item.strainName)
                    .font(.budsBodyBold)

                ratingView
                timestampView

                // Show enrichment hint if minimal
                if enrichmentLevel == .minimal {
                    Text("+ Add Details")
                        .font(.budsCaption)
                        .foregroundColor(.orange)
                }
            }

            Spacer()
            chevron
        }
        .padding()
        .background(cardBackground)
        .overlay(cardBorder)
        .cornerRadius(12)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(
                enrichmentLevel == .minimal
                    ? Color.orange.opacity(0.5)
                    : Color.clear,
                style: StrokeStyle(
                    lineWidth: 2,
                    dash: enrichmentLevel == .minimal ? [5, 5] : []
                )
            )
    }

    private var thumbnailView: some View {
        Group {
            if let cid = item.thumbnailCID {
                CachedAsyncImage(cid: cid)
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
            } else {
                // Different icon based on enrichment
                Rectangle()
                    .fill(iconBackgroundColor)
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
                    .overlay(
                        Image(systemName: iconName)
                            .foregroundColor(iconColor)
                    )
            }
        }
    }

    private var iconName: String {
        switch enrichmentLevel {
        case .minimal: return "pencil.circle"
        case .partial: return "leaf.circle"
        case .complete: return "leaf.fill"
        }
    }

    private var iconColor: Color {
        switch enrichmentLevel {
        case .minimal: return .orange
        case .partial: return .yellow
        case .complete: return .budsPrimary
        }
    }

    private var iconBackgroundColor: Color {
        switch enrichmentLevel {
        case .minimal: return .orange.opacity(0.2)
        case .partial: return .yellow.opacity(0.2)
        case .complete: return .budsPrimary.opacity(0.2)
        }
    }
}
```

---

**Files to Modify**:

1. **`Features/CreateMemory/CreateMemoryView.swift`**
   - Remove: rating, effects, flavors, notes, images state
   - Keep: productName, productType
   - Add: onSaveComplete callback
   - Simplify UI to 2 fields max
   - Change button text: "Continue to Details"

2. **`Features/Circle/JarDetailView.swift`**
   - Add: memoryToEnrich state
   - Update: sheet presentation logic for enrich flow

3. **`Features/Shelf/ShelfView.swift`**
   - Same as JarDetailView for FAB flow

4. **`Features/Circle/MemoryListCard.swift`**
   - Add: enrichmentLevel computed property
   - Add: visual variations (border, icon, hint text)
   - Update: card styling based on enrichment

5. **`Core/Models/MemoryListItem.swift`**
   - Add: effects, flavors, notes fields (for enrichment check)
   - Add: enrichmentLevel computed property

6. **`Core/Database/Repositories/MemoryRepository.swift`**
   - Update: fetchLightweightList to include effects/flavors/notes (for enrichment calc)
   - Ensure: create() works with default values (0 rating, empty arrays)

---

**Acceptance Criteria**:

**Quick Create**:
- [ ] Can create bud with just name (required field)
- [ ] Product type defaults to "Flower"
- [ ] No image picker in create view
- [ ] Form fits on one screen, no scrolling
- [ ] Takes <15 seconds to create minimal bud
- [ ] Button says "Continue to Details" not "Save"

**Enrich Flow**:
- [ ] After save, immediately shows EditMemoryView
- [ ] EditMemoryView pre-fills name + type
- [ ] Has "Skip" button in toolbar (exits immediately)
- [ ] Can add images, rating, effects, flavors, notes
- [ ] Skipping shows toast: "Bud saved! Enrich it anytime"

**Visual Signals**:
- [ ] Minimal buds (name only) show dashed orange border
- [ ] Minimal buds show pencil icon (no thumbnail)
- [ ] Minimal buds show "+ Add Details" text hint
- [ ] Partial buds show leaf.circle icon
- [ ] Complete buds show thumbnail or leaf.fill icon
- [ ] Tapping any card → MemoryDetailView (edit from there)

**Data Integrity**:
- [ ] Minimal buds save successfully with defaults:
  - rating: 0
  - effects: []
  - flavors: []
  - notes: ""
  - imageCIDs: []
- [ ] Enrichment level calculated correctly based on data
- [ ] No crashes with minimal data

---

**Testing Checklist**:

1. **Quick Create**:
   - Create bud with just name → Save → Should show enrich view
   - Create bud, set type → Save → Type should persist
   - Try to save without name → Should show error

2. **Enrich Flow**:
   - Save → Enrich view shows → Add photos → Skip → Check photos saved
   - Save → Enrich view shows → Skip immediately → Check minimal bud in list
   - Save → Enrich view → Add all data → Save → Check complete bud

3. **Visual Signals**:
   - Create 3 buds: minimal, partial, complete
   - Check list shows correct borders/icons/hints
   - Tap minimal bud → Should open detail view
   - Enrich minimal bud → Check visual updates in list

4. **Edge Cases**:
   - Very long strain name (100+ chars) → Should truncate
   - Special characters in name (emojis, etc.) → Should save
   - Create 10 minimal buds → Performance OK?
   - Delete jar with minimal buds → Cleanup OK?

---

### 1.1 Memory Detail View (4-5 hours)

**Build**: Full-screen view to display a single bud's data + reactions.

**Requirements**:
- Show all metadata (strain, type, rating, notes, effects, flavors)
- Display all images in scrollable gallery
- Show timestamps (created, last edited)
- Show jar name & members
- Show reactions with counts (e.g., "❤️ 3  🔥 2")
- Reaction picker at bottom (5 emoji buttons)
- Navigation from MemoryListCard tap

**Files to Create**:
- `Features/Memory/MemoryDetailView.swift`
- `Features/Memory/ReactionRow.swift` - Reactions display component

**Files to Modify**:
- `Features/Circle/MemoryListCard.swift` - Add navigation
- `Features/Circle/JarDetailView.swift` - Add NavigationLink

**Acceptance Criteria**:
- [x] Tap bud card → see full detail view
- [x] All images load in carousel (full resolution)
- [x] All metadata displays correctly
- [ ] Reactions row shows at bottom of scroll view (deferred to Module 1.4)
- [x] Empty fields handled gracefully
- [x] Close button returns to jar list
- [x] Works offline (no network calls)

---

### 1.2 Edit Memory Flow (Enrich) (3-4 hours)

**Build**: Full edit form to enrich bud data.

**This is where complexity lives**: All the fields removed from create are here.

**Requirements**:
- Pre-populate form with existing data
- Allow editing ALL fields:
  - Name, product type
  - Rating (1-5 stars)
  - Effects (checkboxes)
  - Flavors (checkboxes)
  - Notes (text area)
  - Images (add/remove)
- Update receipt system (create new receipt with same UUID)
- Show "Updated" timestamp
- Can't change jar (use "Move" for that)

**Files to Create**:
- `Features/Memory/EditMemoryView.swift` - Full edit form

**Files to Modify**:
- `Features/Memory/MemoryDetailView.swift` - Add "Edit" button in toolbar
- `Core/Database/Repositories/MemoryRepository.swift` - Add update method

**Acceptance Criteria**:
- [x] "Edit" button in MemoryDetailView toolbar
- [x] Form pre-fills with current values
- [x] Can add/remove images (camera + library buttons)
- [x] Can update rating, effects, notes (12 common effects)
- [x] Save creates new receipt (immutable audit trail)
- [x] Toast: "Bud updated! 🌿" (shows after sheet dismiss)
- [x] Returns to detail view
- [x] Proper layout (20px padding, white text in inputs)
- [x] Image carousel fits screen without cropping

---

### 1.3 Delete Memory ✅ COMPLETE (Dec 28, 2025)

**Build**: Delete individual buds with confirmation.

**Requirements**:
- Confirmation dialog before delete
- Remove receipt from database
- Remove blobs (images) if not referenced elsewhere
- Delete all reactions on this memory
- Update jar bud count
- Toast confirmation

**Files Modified**:
- `Features/Timeline/MemoryDetailView.swift` - Delete button with confirmation
- `Core/Database/Repositories/MemoryRepository.swift` - Improved delete() method with blob cleanup
- `Features/Circle/JarDetailView.swift` - Reload list after delete

**Acceptance Criteria**:
- [x] "Delete" button in MemoryDetailView with confirmation alert
- [x] Confirmation alert: "Delete [Strain Name]? This cannot be undone."
- [x] Removes from DB + cleans up blobs (images)
- [x] Toast: "Bud deleted" notification
- [x] Returns to jar list after delete
- [x] List refreshes after delete (bud removed)

**Note**: Swipe-to-delete not implemented - conflicts with navigation swipe-back gesture. Delete button in detail view is sufficient.

---

### 1.4 Reactions System ✅ COMPLETE (Dec 28, 2025)

**Build**: Social reactions for buds in shared jars.

**Database Schema**:
```sql
CREATE TABLE reactions (
    id TEXT PRIMARY KEY NOT NULL,
    memory_id TEXT NOT NULL,
    user_phone TEXT NOT NULL,
    reaction_type TEXT NOT NULL,
    created_at REAL NOT NULL,
    FOREIGN KEY (memory_id) REFERENCES local_receipts(uuid) ON DELETE CASCADE
);
CREATE INDEX idx_reactions_memory ON reactions(memory_id);
CREATE UNIQUE INDEX idx_reactions_unique ON reactions(memory_id, user_phone);
```

**Files Created**:
- `Core/Models/Reaction.swift` - Model + enum with emoji mappings
- `Core/Database/Repositories/ReactionRepository.swift` - CRUD operations
- `Features/Memory/ReactionPicker.swift` - 5 emoji buttons (tap to toggle)
- `Features/Memory/ReactionSummary.swift` - Stacked display with counts

**Files Modified**:
- `Core/Database/Database.swift` - Added v6 migration for reactions table
- `Features/Timeline/MemoryDetailView.swift` - Integrated reactions UI + ViewModel
- `Core/Database/Repositories/MemoryRepository.swift` - Cascade delete reactions

**Implementation Details**:
- ✅ 5 emoji reactions: ❤️ (heart), 😂 (laughing), 🔥 (fire), 👀 (eyes), 😌 (chilled)
- ✅ Tap to toggle: Add reaction → Tap again to remove → Tap different to change
- ✅ Summary view shows grouped counts (e.g., "❤️ 3  🔥 2")
- ✅ Database migration v6 with ON DELETE CASCADE
- ✅ ReactionRepository with toggle logic
- ✅ MemoryDetailView loads reactions on appear
- ✅ Delete memory cascades to reactions
- ✅ Unique constraint: one reaction per user per memory

**Acceptance Criteria**:
- [x] Database table created with migration v6
- [x] Can add reaction to bud (tap emoji button)
- [x] Can remove own reaction (tap same emoji again)
- [x] Can change reaction (tap different emoji)
- [x] Only one reaction per user per bud (unique constraint)
- [x] Reactions grouped and counted (❤️ 3, 🔥 2)
- [x] Deleting memory deletes reactions (cascade)
- [x] UI shows reaction picker below memory details
- [x] Selected reaction highlighted with border

**Note**: Using placeholder phone number (+1234567890) until AuthManager phone integration added.

**Future Enhancements** (deferred):
- Push notifications on reactions
- Tap count to see who reacted (list view)
- Animated reaction bubbles

---

### 1.5 Multi-User Reactions Sync (2-3 hours) - DEFERRED

**Build**: E2EE sync for reactions in shared jars (same pattern as memories)

**Current Problem**: Reactions work locally only, using placeholder phone number

**Solution**: Receipt-based reactions that sync via relay

**Requirements**:
1. **Get real user phone** (30 min)
   - Replace placeholder with `AuthManager.shared.currentUser?.phoneNumber`
   - Store real phone in reactions table

2. **Receipt-based sync** (2h)
   - New receipt type: `app.buds.reaction.added/v1`
   - Payload: `{ memoryID, reactionType }`
   - Sign receipt when user reacts
   - Send via relay to jar members
   - Receive → verify → store in DB

3. **Display combined reactions** (30 min)
   - Merge local + received reactions
   - Show counts from all jar members
   - Tap count to see who reacted (future)

**Files to Modify**:
- `Core/Auth/AuthManager.swift` - Add phone number accessor
- `Core/Receipt/ReceiptManager.swift` - Add `createReactionReceipt()`
- `Core/Database/Repositories/ReactionRepository.swift` - Store sender_did for received reactions
- `Features/Timeline/MemoryDetailView.swift` - Use real phone instead of placeholder
- `Core/Relay/RelayClient.swift` - Handle reaction receipts (maybe already works?)

**Acceptance Criteria**:
- [ ] Uses real user phone from AuthManager
- [ ] Creates signed receipt when reacting
- [ ] Sends reaction to jar members via relay
- [ ] Receives reactions from jar members
- [ ] Verifies signatures on received reactions
- [ ] Displays combined counts (local + received)
- [ ] Deleting memory deletes reactions (already works via cascade)

**Why Defer**:
- Core infrastructure already proven (E2EE, relay, receipts)
- Local-only reactions work fine for solo jars
- Can ship beta without this, add in next iteration
- Gives us time to gather feedback on basic reactions first

---

## Module 2: Jar System Polish

**Current State**:
- ✅ Can create/delete jars
- ✅ Can view jar list & detail
- ✅ Can add/remove members
- ❌ No edit jar name/color
- ❌ Delete confirmation too subtle
- ❌ No "Move bud to different jar"

### 2.1 Edit Jar (1-2 hours)

**Build**: Edit jar name and color.

**Requirements**:
- Reuse CreateJarView in edit mode
- Update jar metadata
- Refresh Shelf after edit

**Files to Modify**:
- `Features/Jar/CreateJarView.swift` - Add edit mode
- `Features/Shelf/ShelfView.swift` - Add edit navigation

**Acceptance Criteria**:
- [ ] Long-press jar card → "Edit Jar" option
- [ ] Can change name & color
- [ ] Save updates immediately
- [ ] Toast: "Jar updated"

---

### 2.2 Jar Delete Confirmation (30 min)

**Build**: More prominent delete warning.

**Requirements**:
- Clear alert dialog
- Show bud count in warning
- Red destructive button

**Files to Modify**:
- `Features/Shelf/ShelfView.swift` - Update alert

**Acceptance Criteria**:
- [ ] Alert shows: "Delete '[Jar Name]'? This jar has X buds. They will move to Solo."
- [ ] Destructive button styled red
- [ ] Works as expected

---

### 2.3 Move Bud Between Jars (2-3 hours)

**Build**: Move a bud from one jar to another.

**Requirements**:
- "Move to..." option in MemoryDetailView
- Picker sheet with jar list
- Update jar_id in local_receipts
- Refresh both source & destination jars

**Files to Create**:
- `Features/Memory/MoveMemoryView.swift`

**Files to Modify**:
- `Features/Memory/MemoryDetailView.swift` - Add "Move" button
- `Core/Database/Repositories/MemoryRepository.swift` - Add move method

**Acceptance Criteria**:
- [ ] "Move" button in MemoryDetailView toolbar
- [ ] Sheet shows all jars except current
- [ ] Tap jar → moves bud
- [ ] Toast: "Moved to [Jar Name]"
- [ ] Returns to new jar's detail view

---

## Module 3: User Guidance ✅ COMPLETE

**Status**: ✅ All sections complete (Dec 29, 2025)

**What Was Built**:
- ✅ Onboarding (3 screens, first-launch only)
- ✅ ProfileView enhanced with privacy links
- ✅ Empty states polished across all views
- ✅ Tab bar simplified to 2 tabs (Shelf + Profile)

### 3.1 Simple Onboarding (2-3 hours)

**Build**: 2-3 screen intro explaining the app.

**Requirements**:
- Show on first launch only
- Explain: What is a jar? What is a bud? Why E2EE?
- Skip button on all screens
- Store "onboarding_completed" flag

**Files to Create**:
- `Features/Onboarding/OnboardingView.swift`
- `Features/Onboarding/OnboardingStep.swift`

**Files to Modify**:
- `ContentView.swift` - Check onboarding flag

**Screens**:
1. "Welcome to Buds" - Track your cannabis journey
2. "Organize with Jars" - Solo vs shared jars
3. "Your Data is Private" - E2EE explanation

**Acceptance Criteria**:
- [x] Shows on first launch
- [x] Never shows again after completion
- [x] Skip button works
- [x] Clean, minimal design

---

### 3.2 Settings Screen (2-3 hours)

**Build**: Basic app settings.

**Requirements**:
- Account info (phone number, device ID)
- Privacy policy link
- Terms of service link
- App version
- "Clear local data" (dev tool)
- "Log out" button

**Files to Create**:
- `Features/Settings/SettingsView.swift`

**Files to Modify**:
- `ContentView.swift` - Add settings tab/button

**Acceptance Criteria**:
- [x] Accessible from main navigation (ProfileView in tab bar)
- [x] Shows phone number (read-only)
- [x] Privacy policy + Terms links added
- [x] Reset all data (dev tool) with confirmation
- [x] "Sign out" returns to auth screen
- [x] Version number displayed
- [x] E2EE test view accessible

---

### 3.3 Empty State Improvements (1 hour)

**Build**: Better empty states throughout app.

**Requirements**:
- Empty jars list (Shelf)
- Empty members list (JarDetailView)
- Empty buds list (JarDetailView) - already done!
- Consistent design

**Files to Modify**:
- `Features/Shelf/ShelfView.swift` - Better empty state
- Various other views

**Acceptance Criteria**:
- [x] All empty states have icon + text + CTA
- [x] Consistent visual style
- [x] Clear guidance on what to do
- [x] ShelfView, JarDetailView (buds + members) all have empty states

---

## Module 4: Error Handling & Feedback ✅ COMPLETE

**Status**: ✅ All sections complete (Dec 29, 2025)

**What Was Built**:
- ✅ Error toast system (tap-to-dismiss, 5s duration, 90% opacity)
- ✅ Loading states audited (all consistent with .budsPrimary)
- ✅ Confirmation dialogs for all destructive actions
- ✅ Toast enhancements (auto-duration based on style)

### 4.1 Error Toast System (2 hours)

**Build**: Show errors to users, not just console.

**Requirements**:
- Red error toasts (vs green success)
- Common error messages (DB failure, no network, etc.)
- Auto-dismiss after 5 seconds
- Dismiss on tap

**Files to Modify**:
- `Shared/Toast.swift` - Add error variant
- All repositories - Show error toasts

**Acceptance Criteria**:
- [x] DB errors show toast: "Something went wrong. Please try again."
- [x] Red background for errors (90% opacity)
- [x] User can tap to dismiss
- [x] Auto-dismiss after 5 seconds (errors) or 2 seconds (success)

---

### 4.2 Loading States Audit (1-2 hours)

**Build**: Ensure all data loads show spinners.

**Requirements**:
- Shelf loading jars
- JarDetailView loading buds
- MemoryDetailView loading images
- Consistent spinner design

**Files to Modify**:
- Various views

**Acceptance Criteria**:
- [x] No blank screens during load
- [x] Spinner uses .budsPrimary color
- [x] Text: "Loading jars...", "Loading buds...", "Loading..." where appropriate
- [x] All major views have loading states (ShelfView, JarDetailView, EditMemoryView)

---

### 4.3 Confirmation Dialogs (1 hour)

**Build**: Confirm destructive actions.

**Requirements**:
- Delete jar (already exists, improve)
- Delete bud (new)
- Remove member (new)
- Clear local data (new)

**Files to Modify**:
- Various views

**Acceptance Criteria**:
- [x] All destructive actions ask for confirmation
- [x] Red destructive buttons (role: .destructive)
- [x] Clear warning text
- [x] Delete jar: Shows bud count + warning
- [x] Delete bud: Shows strain name + "cannot be undone"
- [x] Remove member: Explains access removal
- [x] Delete account: "Permanently delete... cannot be undone"
- [x] Reset data: Detailed warning about what gets deleted

---

## Module 5: Performance & Testing ✅ COMPLETE

**Status**: ✅ All sections complete (Dec 29, 2025)

**What Was Built**:
- ✅ Stress test generator tool (UI + backend)
- ✅ Fresh install testing checklist (10 detailed tests)
- ✅ Multi-device testing checklist (10 tests across devices)
- ✅ Performance monitoring guide

### 5.1 Stress Testing (1-2 hours)

**Test**: App with 100+ buds across multiple jars.

**Requirements**:
- Create test script to generate buds
- Test scrolling performance
- Test memory usage
- Test search (when built)

**Acceptance Criteria**:
- [x] Stress test generator created
- [x] Can generate 50/100/200 test buds
- [x] Can clear test buds
- [x] Testing checklist created
- [ ] 100 buds: Memory <60MB (manual test)
- [ ] Smooth 60fps scrolling (manual test)
- [ ] No crashes (manual test)
- [ ] DB queries <100ms (manual test)

---

### 5.2 Fresh Install Testing (1 hour)

**Test**: Delete app, reinstall, go through onboarding.

**Requirements**:
- Test on physical device
- Document any confusing UX
- Fix critical issues

**Acceptance Criteria**:
- [x] Fresh install checklist created (10 tests)
- [x] Covers onboarding → auth → first jar → first bud
- [x] Empty states verified
- [x] Sign out/re-auth tested
- [ ] Onboarding shows correctly (manual test)
- [ ] Can create first jar (manual test)
- [ ] Can create first bud (manual test)
- [ ] Solo jar exists by default (manual test)

---

### 5.3 Multi-Device Testing (2 hours)

**Test**: Install on 2-3 different devices.

**Requirements**:
- iPhone SE (small screen)
- iPhone Pro Max (large screen)
- Different iOS versions if possible

**Acceptance Criteria**:
- [x] Multi-device checklist created (10 tests)
- [x] Covers iPhone SE, 15, Pro Max
- [x] Layout, tap targets, performance tests
- [x] Edge cases documented
- [ ] UI works on small screens (manual test)
- [ ] UI works on large screens (manual test)
- [ ] No layout bugs (manual test)
- [ ] Performance acceptable (manual test)

---

## Module 6: TestFlight Prep

### 6.1 Version & Changelog (30 min)

**Requirements**:
- Bump version to 1.0.0 (build 1)
- Create CHANGELOG.md
- Add "What's New" for TestFlight

**Acceptance Criteria**:
- [ ] Version updated in Xcode
- [ ] CHANGELOG created
- [ ] "What to Test" notes for testers

---

### 6.2 Archive & Upload (1 hour)

**Requirements**:
- Archive build
- Upload to TestFlight
- Add external tester notes
- Invite first testers

**Acceptance Criteria**:
- [ ] Build uploaded successfully
- [ ] Beta info complete
- [ ] First 5-10 testers invited
- [ ] Feedback channel set up (Discord/Slack)

---

## Priority Order (Recommended)

**Week 1 (12-14 hours)**: Core UX + Functionality
1. **Simplify Create Memory Flow** (2-3h) ← Do first! Makes app usable
2. **Memory Detail View** (4-5h) ← Critical for viewing buds
3. **Edit Memory (Enrich)** (3-4h) ← Where complexity lives
4. **Delete Memory** (2h)
5. **Error Toasts** (2h)

**Week 2 (10-12 hours)**: Social + Polish
6. **Reactions System** (3-4h) ← Social engagement feature
7. **Onboarding** (2-3h)
8. **Settings** (2-3h)
9. **Move Bud Between Jars** (2-3h)
10. **Edit Jar** (1-2h)

**Week 3 (4-6 hours)**: Final Polish + Ship
11. **Loading States Audit** (1-2h)
12. **Confirmation Dialogs** (1h)
13. **Stress Testing** (1-2h)
14. **Fresh Install Test** (1h)
15. **TestFlight Upload** (1h)

---

## Success Metrics for Beta

**Minimum Viable Beta**:
- [ ] Users can create buds (simplified flow: name + images)
- [ ] Users can view bud details
- [ ] Users can edit/enrich buds (rating, effects, flavors, notes)
- [ ] Users can delete buds
- [ ] Users can react to buds (5 emoji reactions)
- [ ] Users can manage jars (create, edit, delete)
- [ ] Onboarding explains the app
- [ ] Errors show helpful messages
- [ ] No crashes on common flows
- [ ] Memory <60MB with 20 buds

**Nice to Have**:
- [ ] Search/filter buds
- [ ] Export data (CSV/JSON)
- [ ] Dark/light mode toggle
- [ ] Animations on transitions
- [ ] Tap reaction count to see who reacted

---

## Out of Scope (Phases 11-14)

**Not in this phase**:
- Map view
- Shop integration
- AI recommendations
- Social features
- Analytics
- Push notifications

These come AFTER beta feedback from 20-50 users.

---

## Notes

- **Parallel development**: Developer builds map/shop/AI while this gets polished
- **User feedback**: After TestFlight ships, gather feedback before more features
- **Iterative**: Ship beta → test with users → fix critical issues → ship again
- **No scope creep**: Stick to making existing features work well

**Remember**: The goal is not perfection. The goal is 20-50 people can use the app without frustration.

---

## Implementation Roadmap (Ready to Execute)

**Module 1.0 is fully specced and ready to build**:
- ✅ UI mockups defined
- ✅ Navigation flow mapped
- ✅ Data model changes identified
- ✅ Visual design system (dashed borders, icons)
- ✅ Acceptance criteria written
- ✅ Testing checklist created
- ✅ All file changes documented

**Next Steps**:
1. Get user approval on this plan
2. Start implementation of Module 1.0 (Simplify Create Flow)
3. Test create → enrich flow
4. Move to Module 1.1 (Memory Detail View)

**Estimated Completion**:
- Module 1.0: 2-3 hours
- Full Phase 10.1: 18-24 hours over 3 weeks
- TestFlight ship date: ~3 weeks from start
