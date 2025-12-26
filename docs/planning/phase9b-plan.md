# Phase 9b Plan: Shelf View (Home Redesign)
## Grid Layout + Activity Indicators

**Date**: December 25, 2025
**Status**: Ready for Execution
**Prerequisites**: Phase 9a complete ✅
**Difficulty**: Medium (UI transformation + grid layout)
**Timeline**: 4 hours
**Priority**: Medium (UX enhancement, not critical path)

---

## Executive Summary

**Goal**: Transform Timeline (list view with picker) → Shelf (grid view of jar cards) per R1 Master Plan Phase 9.

**User Story**: "As a user, I want to see all my jars at a glance on a grid, with visual indicators showing which jars have recent activity."

**What Changes**:
- Timeline list view → Grid of jar cards (2 per row)
- Jar picker (dropdown) → Visual grid navigation
- Activity indicators: dots (up to 4 recent buds) + glow (buds added <24h ago)
- Tab name: "Timeline" → "Shelf"

**What Stays the Same**:
- Backend: JarManager, JarRepository (untouched)
- Jar detail view: JarDetailView (untouched)
- Add bud flow: CreateMemoryView (untouched)
- All Phase 9a functionality preserved

---

## A. Current State (Post-Phase 9a)

### ✅ What Works
- Timeline shows buds filtered by selected jar
- Jar picker (dropdown) switches between jars
- Circle tab shows jar list (works but not primary nav)
- JarManager.shared provides @Published jars array
- MemoryRepository.fetchByJar(jarID:) filters buds

### ⚠️ What Needs Changing
- Timeline is still a list view (not grid)
- No visual activity indicators (dots/glow)
- Jar selection via dropdown (not visual cards)
- Tab bar still says "Timeline" (should be "Shelf")

---

## B. Design Specification

### Visual Language

**Shelf View Layout**:
```
┌──────────────────────────────────────────┐
│               B U D S                    │
│                                          │
│        + Add Jar                        │
│                                          │
│   ┌───────────────┐   ┌───────────────┐ │
│   │   ○ ○ ○ ○     │   │   ○ ○ ○        │ │ ← Activity dots (up to 4)
│   │   Solo        │   │   Friends      │ │
│   │   12 buds     │   │   8 buds       │ │
│   └───────────────┘   └───────────────┘ │
│                                          │
│   ┌───────────────┐   ┌───────────────┐ │
│   │   ○ ○ ○       │   │   ○            │ │
│   │   Tahoe Trip  │   │   Late Night   │ │
│   │   5 buds      │   │   2 buds       │ │ ← Bud count
│   └───────────────┘   └───────────────┘ │
└──────────────────────────────────────────┘
```

**Jar Card States**:
1. **Normal**: Gray card, no glow
2. **Active (buds <24h)**: Glow effect (budsPrimary shadow)
3. **Empty (0 buds)**: Dimmed, dashed border

**Activity Dots**:
- Up to 4 dots shown
- Each dot = 1 recent bud (most recent 4)
- Dots are small circles at top of card
- Dot color: budsPrimary

**Glow Effect**:
- Applied when ANY bud added in last 24 hours
- Glow = .shadow(color: .budsPrimary, radius: 8)
- Fades out as buds age (no animation, static check)

---

## C. Corrected Implementation Plan

### Step 1: Create ShelfJarCard Component (1 hour)

**File**: `Buds/Features/Shelf/ShelfJarCard.swift`

**Purpose**: Shelf-specific jar card with activity indicators (replaces Phase 9a's simple JarCard)

**Features**:
- Grid-optimized layout (square aspect ratio)
- Activity dots (up to 4)
- Glow effect for buds <24h
- Bud count
- Tap gesture → Navigate to JarFeedView (Phase 10) or JarDetailView (Phase 9a fallback)

**Code Structure**:
```swift
struct ShelfJarCard: View {
    let jar: Jar

    @State private var budCount: Int = 0
    @State private var recentBudCount: Int = 0  // Buds added in last 24h
    @State private var activityDots: Int = 0    // Min(4, total buds)

    private var hasRecentActivity: Bool {
        recentBudCount > 0
    }

    var body: some View {
        VStack(spacing: 8) {
            // Activity dots row
            HStack(spacing: 6) {
                ForEach(0..<activityDots, id: \.self) { _ in
                    Circle()
                        .fill(Color.budsPrimary)
                        .frame(width: 8, height: 8)
                }
                Spacer()
            }
            .frame(height: 20)
            .padding(.horizontal, 12)

            // Jar name
            Text(jar.name)
                .font(.budsHeadline)
                .foregroundColor(.white)
                .lineLimit(1)

            // Bud count
            Text("\(budCount) buds")
                .font(.budsCaption)
                .foregroundColor(.budsTextSecondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .aspectRatio(1.0, contentMode: .fit)  // Square cards
        .background(Color.budsCard)
        .cornerRadius(16)
        .shadow(
            color: hasRecentActivity ? .budsPrimary.opacity(0.4) : .clear,
            radius: hasRecentActivity ? 8 : 0
        )
        .task {
            await loadActivity()
        }
    }

    private func loadActivity() async {
        do {
            let buds = try await MemoryRepository().fetchByJar(jarID: jar.id)

            // Calculate recent activity (buds in last 24h)
            let twentyFourHoursAgo = Date().addingTimeInterval(-24 * 60 * 60)
            let recentBuds = buds.filter { $0.createdAt > twentyFourHoursAgo }

            await MainActor.run {
                budCount = buds.count
                recentBudCount = recentBuds.count
                activityDots = min(4, buds.count)
            }
        } catch {
            print("❌ Failed to load jar activity: \(error)")
        }
    }
}
```

**Acceptance Criteria**:
- Card is square (1:1 aspect ratio)
- Shows up to 4 dots
- Glow appears when buds added <24h
- Tap navigates to jar detail

---

### Step 2: Create ShelfView (1.5 hours)

**File**: `Buds/Features/Shelf/ShelfView.swift`

**Purpose**: Replace TimelineView as primary home screen, shows grid of jars

**Features**:
- LazyVGrid with 2 columns
- + Add Jar button in toolbar
- Empty state (no jars)
- NavigationStack for drill-down to JarDetailView

**Code Structure**:
```swift
struct ShelfView: View {
    @StateObject private var jarManager = JarManager.shared
    @State private var showingCreateJar = false

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if jarManager.isLoading {
                    ProgressView("Loading jars...")
                        .tint(.budsPrimary)
                } else if jarManager.jars.isEmpty {
                    emptyState
                } else {
                    jarGrid
                }
            }
            .navigationTitle("Shelf")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreateJar = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.budsPrimary)
                    }
                }
            }
            .sheet(isPresented: $showingCreateJar, onDismiss: {
                Task { await jarManager.loadJars() }
            }) {
                CreateJarView()
            }
            .task {
                await jarManager.loadJars()
            }
        }
    }

    private var jarGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(jarManager.jars) { jar in
                    NavigationLink(destination: JarDetailView(jar: jar)) {
                        ShelfJarCard(jar: jar)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 80))
                .foregroundColor(.budsPrimary.opacity(0.3))

            VStack(spacing: 12) {
                Text("No Jars Yet")
                    .font(.budsTitle)
                    .foregroundColor(.white)

                Text("Create jars to organize your buds")
                    .font(.budsBody)
                    .foregroundColor(.budsTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                showingCreateJar = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle")
                    Text("Create Jar")
                }
                .font(.budsBodyBold)
                .foregroundColor(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .background(Color.budsPrimary)
                .cornerRadius(12)
            }
        }
        .padding()
    }
}
```

**Acceptance Criteria**:
- Grid shows 2 jars per row
- All jars visible (including Solo)
- Empty state shown when no jars
- Navigation to JarDetailView works

---

### Step 3: Update MainTabView (30 min)

**File**: `Buds/Features/MainTabView.swift`

**Changes**:
1. Replace TimelineView → ShelfView in Tab 0
2. Update tab label: "Timeline" → "Shelf"
3. Update tab icon: "clock" → "square.stack.3d.up"
4. Hide Circle tab (jar management now happens in Shelf → JarDetailView)

**Code Changes**:
```swift
// OLD
TabView(selection: $selectedTab) {
    TimelineView()
        .tabItem {
            Label("Timeline", systemImage: "clock.fill")
        }
        .tag(0)

    CircleView()
        .tabItem {
            Label("Circle", systemImage: "person.2.fill")
        }
        .tag(1)

    // ... rest
}

// NEW
TabView(selection: $selectedTab) {
    ShelfView()
        .tabItem {
            Label("Shelf", systemImage: "square.stack.3d.up.fill")
        }
        .tag(0)

    // Circle tab removed (jar management in Shelf now)

    ProfileView()
        .tabItem {
            Label("Profile", systemImage: "person.fill")
        }
        .tag(1)  // Was tag 2, now tag 1
}
```

**Acceptance Criteria**:
- Tab 0 shows ShelfView
- Tab label says "Shelf"
- Tab icon is square.stack.3d.up
- Circle tab no longer visible

---

### Step 4: Preserve Timeline as Legacy View (Optional, 15 min)

**Decision Point**: Keep TimelineView.swift or delete?

**Option A: Keep as fallback** (recommended)
- Rename: `TimelineView.swift` → `TimelineView_Legacy.swift`
- Keep file but don't import anywhere
- Useful for comparison during testing

**Option B: Delete**
- Remove file entirely
- Cleaner codebase
- Can always restore from git

**Recommendation**: Keep as `TimelineView_Legacy.swift` during Phase 9b testing, delete after Phase 10 ships.

---

### Step 5: Update CreateMemoryView Jar Context (30 min)

**File**: `Buds/Features/Timeline/CreateMemoryView.swift`

**Problem**: CreateMemoryView currently defaults jar_id to "solo", but user might be viewing a specific jar in Shelf

**Solution Options**:

**Option A: Add jarID parameter** (recommended for Phase 10)
```swift
struct CreateMemoryView: View {
    let jarID: String = "solo"  // Default for now

    // When creating: MemoryRepository.create(..., jarID: jarID)
}
```

**Option B: Always use "solo"** (acceptable for Phase 9b)
- CreateMemoryView always creates in Solo jar
- User can't specify jar during creation
- Simpler, fewer edge cases

**Recommendation**: Use Option B for Phase 9b (always solo), defer Option A to Phase 10 (Jar Feed).

---

### Step 6: Test Activity Indicators (30 min)

**Manual Tests**:

1. **Activity Dots Test**:
   - Create jar with 0 buds → 0 dots
   - Add 1 bud → 1 dot
   - Add 3 more buds → 4 dots (max)
   - Add 10 more buds → still 4 dots

2. **Glow Effect Test**:
   - Create jar with old buds (>24h ago) → no glow
   - Add new bud → glow appears
   - Wait 24 hours → glow disappears
   - Simulate: Use `.addingTimeInterval(-25 * 60 * 60)` for old buds

3. **Grid Layout Test**:
   - 1 jar → Left column, top row
   - 2 jars → Both columns, top row
   - 3 jars → Top row + left column second row
   - 10 jars → 5 rows of 2

**SQL Verification**:
```sql
-- Verify buds have correct created_at timestamps
SELECT jar_id, COUNT(*), MAX(created_at), MIN(created_at)
FROM local_receipts
GROUP BY jar_id;

-- Verify recent activity (buds <24h)
SELECT jar_id, COUNT(*) as recent_buds
FROM local_receipts
WHERE created_at > datetime('now', '-24 hours')
GROUP BY jar_id;
```

---

## D. Risk Register

### Risk 1: Grid Performance with Many Jars (Low)

**Symptom**: Scroll lag with 50+ jars

**Mitigation**:
- Using LazyVGrid (only loads visible cells)
- ShelfJarCard.loadActivity() runs in .task {} (async)
- If >20 jars, consider pagination or "Show More"

**Acceptable**: Most users will have <10 jars

---

### Risk 2: Activity Calculation on Every Render (Medium)

**Symptom**: Fetching all buds for every jar card on every Shelf load is expensive

**Mitigation**:
- Cache activity in JarManager (add `jarActivity: [String: (budCount: Int, recentCount: Int)]`)
- Refresh cache on jar load, bud creation, bud deletion
- ShelfJarCard reads from cache instead of querying

**Implementation** (if needed):
```swift
// In JarManager
@Published var jarActivity: [String: (budCount: Int, recentCount: Int, lastBudAt: Date?)] = [:]

func updateJarActivity(jarID: String) async {
    let buds = try await MemoryRepository().fetchByJar(jarID: jarID)
    let twentyFourHoursAgo = Date().addingTimeInterval(-24 * 60 * 60)
    let recentBuds = buds.filter { $0.createdAt > twentyFourHoursAgo }

    await MainActor.run {
        jarActivity[jarID] = (
            budCount: buds.count,
            recentCount: recentBuds.count,
            lastBudAt: buds.first?.createdAt
        )
    }
}
```

**Decision**: Implement if Shelf load takes >2 seconds with 5+ jars

---

### Risk 3: Navigation Stack Depth (Low)

**Symptom**: ShelfView → JarDetailView → MemberDetailView → 3 levels deep

**Mitigation**:
- NavigationStack handles this natively
- Use .navigationBarTitleDisplayMode(.inline) for child views
- Use Environment(\.dismiss) for consistent back behavior

**Acceptable**: 3 levels is standard iOS pattern

---

### Risk 4: Circle Tab Removal Breaks Existing Flows (Medium)

**Symptom**: Users can't manage jar members without Circle tab

**Mitigation**:
- Jar management still accessible via Shelf → Tap jar → JarDetailView → Members
- Add "Manage Members" button to JarDetailView toolbar
- Consider adding "All Jars" view in Profile tab

**Verification**:
- User can add member: Shelf → Jar → "+" button ✅
- User can remove member: Shelf → Jar → Tap member → Remove ✅

---

## E. Diff-Ready Checklist

### Files to Create (2)

1. `Buds/Features/Shelf/ShelfView.swift` (~180 lines)
2. `Buds/Features/Shelf/ShelfJarCard.swift` (~120 lines)

**Total New Code**: ~300 lines

---

### Files to Modify (2)

1. `Buds/Features/MainTabView.swift` (~20 lines changed)
   - Replace TimelineView → ShelfView
   - Update tab labels and icons
   - Remove Circle tab

2. `Buds/Features/Timeline/TimelineView.swift` (optional rename)
   - Rename to `TimelineView_Legacy.swift`
   - No code changes

**Total Modified Code**: ~20 lines

---

### Files to Delete (Optional)

1. `Buds/Features/Circle/CircleView.swift` (if Circle tab removed)
   - Alternative: Keep but don't reference in MainTabView

**Recommendation**: Keep CircleView.swift as legacy for 1 release, delete after Phase 10

---

## F. Execution Order

**Phase 1: Components** (1.5 hours)
1. Create ShelfJarCard.swift
2. Test in isolation (Preview)
3. Verify activity dots + glow logic

**Phase 2: View** (1.5 hours)
4. Create ShelfView.swift
5. Test grid layout with mock jars
6. Verify navigation to JarDetailView

**Phase 3: Integration** (30 min)
7. Update MainTabView.swift
8. Build and verify tab switching
9. Test end-to-end: Shelf → Jar → Member

**Phase 4: Testing** (30 min)
10. Manual test: Activity dots (0, 1, 4, 10 buds)
11. Manual test: Glow effect (recent vs old buds)
12. Manual test: Grid layout (1, 2, 3, 10 jars)

---

## G. Acceptance Tests

### Test 1: Shelf Grid Layout ✅

**Steps**:
1. Launch app → Shelf tab (was Timeline)
2. Verify grid shows 2 jars per row
3. Create new jar → Verify it appears in grid
4. Delete jar → Verify it disappears from grid

**Expected**:
- Grid layout (2 columns)
- Cards are square
- Smooth scrolling

---

### Test 2: Activity Dots ✅

**Steps**:
1. Create jar "Dot Test" with 0 buds → 0 dots
2. Add 1 bud → 1 dot appears
3. Add 3 more buds → 4 dots total
4. Add 6 more buds (10 total) → still 4 dots (max)

**Expected**:
- Dots update in real-time
- Max 4 dots shown
- Dots are small, visible, budsPrimary color

---

### Test 3: Glow Effect ✅

**Steps**:
1. Create jar with old buds (>24h ago)
2. Verify no glow on card
3. Add new bud (now)
4. Verify glow appears (green shadow)
5. Simulate time passing (change device time +25 hours)
6. Verify glow disappears

**Expected**:
- Glow only when buds <24h old
- Glow is subtle (radius 8, opacity 0.4)
- Glow fades naturally as buds age

---

### Test 4: Navigation Flow ✅

**Steps**:
1. Shelf → Tap "Solo" jar
2. Verify JarDetailView opens
3. Tap "+" to add member
4. Add member, verify success
5. Back to Shelf
6. Verify Solo jar still shows (no navigation bugs)

**Expected**:
- NavigationStack works correctly
- Back button returns to Shelf
- State preserved (jar list doesn't reload)

---

### Test 5: Circle Tab Removal ✅

**Steps**:
1. Check tab bar
2. Verify Circle tab is gone
3. Verify Shelf tab (icon: square.stack.3d.up)
4. Verify Profile tab (now tab 1, was tab 2)

**Expected**:
- 2 tabs total (Shelf, Profile)
- Circle functionality accessible via Shelf → Jar
- No broken navigation

---

## H. Success Criteria

- ✅ Shelf shows all jars in 2-column grid
- ✅ Tapping jar opens JarDetailView
- ✅ Activity dots show up to 4 recent buds
- ✅ Glow effect appears for buds <24h
- ✅ Empty state shown when 0 jars
- ✅ "Add Jar" creates new jar
- ✅ Circle tab removed (jar management via Shelf)
- ✅ Build succeeds with no errors
- ✅ All acceptance tests pass

---

## I. Phase Comparison

### Phase 9a (Multi-Jar UI)
- **Goal**: Make jar backend functional
- **Scope**: Backend + CRUD UI
- **Complexity**: High (data model + device pinning)
- **Timeline**: 6-8 hours
- **Deliverable**: Jars work end-to-end

### Phase 9b (Shelf View)
- **Goal**: Make jar UI beautiful
- **Scope**: UX transformation
- **Complexity**: Medium (grid layout + activity logic)
- **Timeline**: 4 hours
- **Deliverable**: Grid view with visual indicators

**Relationship**: Phase 9b builds on 9a, no backend changes needed.

---

## J. Future Enhancements (Phase 10+)

**Phase 10: Jar Feed View**
- Inside jar, show buds in media-first feed format
- Replace JarDetailView → JarFeedView
- Comments, reactions, AI cards

**Post-R1**:
- Jar color customization
- Jar cover images
- Activity timeline ("3 buds added yesterday")
- Jar sharing (send invite link)

---

## K. Estimated Timeline

| Task | Time |
|------|------|
| Create ShelfJarCard | 1 hour |
| Create ShelfView | 1.5 hours |
| Update MainTabView | 30 min |
| Test activity indicators | 30 min |
| Integration testing | 30 min |
| **Total** | **4 hours** |

---

## L. Dependencies

**Prerequisites** (must be complete):
- ✅ Phase 9a: Multi-Jar UI (jars, members, device pinning)
- ✅ JarManager.shared with @Published jars
- ✅ MemoryRepository.fetchByJar(jarID:)
- ✅ JarDetailView exists

**Blocks** (Phase 9b blocks):
- Phase 10: Jar Feed View (needs Shelf as home screen)

---

## M. Notes for Execution Agent

1. **Preserve Phase 9a**: Do NOT modify existing JarManager, JarRepository, or JarDetailView
2. **Grid is King**: Focus on making grid layout smooth and responsive
3. **Activity is Nice-to-Have**: If activity indicators are complex, ship without glow first
4. **Navigation Simplicity**: Shelf → JarDetailView is the only nav needed for Phase 9b
5. **Circle Tab**: Removing it is optional; can hide instead of delete for easier rollback

---

**Ready to transform Timeline → Shelf! 🫙✨**
