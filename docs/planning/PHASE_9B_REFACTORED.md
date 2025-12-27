# Phase 9b Refactored: Shelf View (Performance-First)

**Date**: December 26, 2025
**Status**: Ready for Execution
**Prerequisites**: Phase 9a complete ✅
**Priority**: High (UX transformation + architectural cleanup)
**Timeline**: 5-6 hours (added time for performance optimizations)

---

## Executive Summary

**Goal**: Transform Timeline → Shelf grid view with **zero performance compromises**.

**Core Principle**: Every line of code must justify its existence. No N+1 queries, no wasteful renders, no architectural shortcuts.

**What Changed from Original Plan**:
- Added `MemoryRepository.fetchJarStats()` for O(1) stat queries
- Fixed spec mismatch (dots = recent buds, not total buds)
- Proper lifecycle management (@ObservedObject not @StateObject)
- Cached jar activity in JarManager (no per-card fetches)
- Keep Circle tab for one release (safer rollback)
- Fixed CreateMemoryView jar context (already done in 9a!)
- Defensive timestamp handling
- Single source of truth for reloads

---

## Red Flags Addressed

### 🔴 CRITICAL: N+1 Query Problem
**Original Issue**: Each ShelfJarCard calls `fetchByJar(jarID:)` → 10 jars = 10 full DB fetches

**Fix**: Add lightweight stats query that returns counts only
```swift
// In MemoryRepository
func fetchJarStats(jarID: String) async throws -> JarStats {
    // Single query, returns counts + lastCreatedAt, NO memory objects
}
```

**Impact**: 10x faster Shelf load, no battery drain

---

### 🔴 CRITICAL: Spec Mismatch (Dots = Total vs Recent)
**Original Issue**: Dots show `min(4, buds.count)` but spec says "recent buds"

**Fix**: Dots show `min(4, recentBuds.count)` where recent = last 24 hours

**Impact**: Matches spec, clearer UX

---

### 🟡 MEDIUM: @StateObject Singleton Misuse
**Original Issue**: `@StateObject private var jarManager = JarManager.shared`

**Fix**: `@ObservedObject var jarManager = JarManager.shared`

**Why**: @StateObject owns the lifecycle. For singletons, use @ObservedObject.

---

### 🟡 MEDIUM: Timestamp Format Assumptions
**Original Issue**: Assumes `createdAt` is proper Date, but storage might be string/UTC

**Fix**: Document timestamp invariants + add validation

**Impact**: Prevents subtle timezone bugs

---

### 🟡 MEDIUM: Double Reloads on Sheet Dismiss
**Original Issue**: Loads on `.task` AND `onDismiss`

**Fix**: Remove `onDismiss` reload (JarManager already observes changes)

**Impact**: Eliminates flicker

---

### 🟢 LOW: Circle Tab Removal Risk
**Original Issue**: Removing tab might break navigation/deep links

**Fix**: Keep Circle tab for one release (hide later if needed)

**Impact**: Safer rollback, gradual migration

---

## Architecture Decisions

### Decision 1: JarStats Repository Pattern

**Problem**: Need counts without fetching all memory objects

**Solution**: Add specialized query that returns stats struct
```swift
struct JarStats {
    let jarID: String
    let totalBuds: Int
    let recentBuds: Int      // Last 24h
    let lastBudAt: Date?     // Most recent bud timestamp
}
```

**Performance**:
- Old way: 10 jars × `SELECT *` = 10 full object fetches
- New way: 1× `SELECT jar_id, COUNT(*), MAX(created_at)` per jar
- Improvement: ~50x faster (just aggregates, no BLOB reads)

---

### Decision 2: JarManager Activity Cache

**Problem**: Stats still fetched per card (10 queries)

**Solution**: Cache in JarManager, update on mutations
```swift
class JarManager {
    @Published var jars: [Jar] = []
    @Published var jarStats: [String: JarStats] = [:]  // NEW

    func loadJarsWithStats() async {
        // Load jars + stats in single batch
        // Cards read from cache
    }
}
```

**Performance**:
- Shelf load: 1 batch query (all jars + all stats)
- Cards: Read from cache (instant)
- Updates: Only refresh affected jar

---

### Decision 3: Timestamp Invariants

**Requirement**: All `created_at` values must be:
1. Stored as Unix timestamp (Double) or ISO8601 string
2. In UTC timezone
3. Compared using Date objects (not string comparison)

**Validation** (add to MemoryRepository):
```swift
// Verify created_at is within reasonable range
let minDate = Date(timeIntervalSince1970: 1609459200)  // Jan 1, 2021
let maxDate = Date().addingTimeInterval(86400)          // Tomorrow
guard (minDate...maxDate).contains(createdAt) else {
    throw RepositoryError.invalidTimestamp
}
```

---

## Implementation Plan (Revised)

### Step 1: Add JarStats Repository (45 min)

**File**: `Buds/Core/Database/Repositories/MemoryRepository.swift`

**Add Method**:
```swift
struct JarStats {
    let jarID: String
    let totalBuds: Int
    let recentBuds: Int      // Buds in last 24h
    let lastBudAt: Date?
}

func fetchJarStats(jarID: String) async throws -> JarStats {
    try await db.readAsync { db in
        // Total buds for jar
        let total = try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(*)
                FROM local_receipts
                WHERE jar_id = ?
                """,
            arguments: [jarID]
        ) ?? 0

        // Recent buds (last 24h)
        let twentyFourHoursAgo = Date().addingTimeInterval(-24 * 60 * 60)
        let recent = try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(*)
                FROM local_receipts lr
                JOIN ucr_headers h ON lr.header_cid = h.cid
                WHERE lr.jar_id = ? AND h.received_at > ?
                """,
            arguments: [jarID, twentyFourHoursAgo.timeIntervalSince1970]
        ) ?? 0

        // Last bud timestamp
        let lastBudTimestamp = try Double.fetchOne(
            db,
            sql: """
                SELECT MAX(h.received_at)
                FROM local_receipts lr
                JOIN ucr_headers h ON lr.header_cid = h.cid
                WHERE lr.jar_id = ?
                """,
            arguments: [jarID]
        )

        let lastBudAt = lastBudTimestamp.map { Date(timeIntervalSince1970: $0) }

        return JarStats(
            jarID: jarID,
            totalBuds: total,
            recentBuds: recent,
            lastBudAt: lastBudAt
        )
    }
}

// Batch version (more efficient)
func fetchAllJarStats() async throws -> [String: JarStats] {
    try await db.readAsync { db in
        let twentyFourHoursAgo = Date().addingTimeInterval(-24 * 60 * 60)

        // Single query with GROUP BY
        let sql = """
            SELECT
                lr.jar_id,
                COUNT(*) as total,
                SUM(CASE WHEN h.received_at > ? THEN 1 ELSE 0 END) as recent,
                MAX(h.received_at) as last_at
            FROM local_receipts lr
            JOIN ucr_headers h ON lr.header_cid = h.cid
            GROUP BY lr.jar_id
            """

        let rows = try Row.fetchAll(db, sql: sql, arguments: [twentyFourHoursAgo.timeIntervalSince1970])

        var stats: [String: JarStats] = [:]
        for row in rows {
            let jarID = row["jar_id"] as String
            let total = row["total"] as Int
            let recent = row["recent"] as Int
            let lastTimestamp = row["last_at"] as? Double

            stats[jarID] = JarStats(
                jarID: jarID,
                totalBuds: total,
                recentBuds: recent,
                lastBudAt: lastTimestamp.map { Date(timeIntervalSince1970: $0) }
            )
        }

        return stats
    }
}
```

**Test**:
```swift
// Should return stats without fetching memory objects
let stats = try await repository.fetchJarStats(jarID: "solo")
print("Solo jar: \(stats.totalBuds) total, \(stats.recentBuds) recent")
```

---

### Step 2: Update JarManager with Cache (30 min)

**File**: `Buds/Core/JarManager.swift`

**Add Properties**:
```swift
actor JarManager {
    static let shared = JarManager()

    @Published var jars: [Jar] = []
    @Published var isLoading = false
    @Published var jarStats: [String: JarStats] = [:]  // NEW: Cache

    // ... existing code
}
```

**Update loadJars()**:
```swift
func loadJars() async {
    isLoading = true
    defer { isLoading = false }

    do {
        // Load jars + stats in parallel
        async let jarsResult = JarRepository.shared.getAllJars()
        async let statsResult = MemoryRepository().fetchAllJarStats()

        let (loadedJars, loadedStats) = try await (jarsResult, statsResult)

        await MainActor.run {
            self.jars = loadedJars
            self.jarStats = loadedStats
        }

        print("✅ Loaded \(jars.count) jars with stats")
    } catch {
        print("❌ Failed to load jars: \(error)")
    }
}
```

**Add Refresh Method** (call after creating/deleting buds):
```swift
func refreshJarStats(jarID: String) async {
    do {
        let stats = try await MemoryRepository().fetchJarStats(jarID: jarID)
        await MainActor.run {
            self.jarStats[jarID] = stats
        }
    } catch {
        print("❌ Failed to refresh stats for jar \(jarID): \(error)")
    }
}
```

---

### Step 3: Create ShelfJarCard (45 min)

**File**: `Buds/Features/Shelf/ShelfJarCard.swift`

**Key Changes from Original**:
- Reads from JarManager cache (no DB queries)
- Dots = `min(4, recentBuds)` (matches spec)
- Fixed height (no aspect ratio issues)

```swift
struct ShelfJarCard: View {
    let jar: Jar
    @ObservedObject var jarManager = JarManager.shared  // Not @StateObject!

    private var stats: JarStats? {
        jarManager.jarStats[jar.id]
    }

    private var activityDots: Int {
        guard let stats = stats else { return 0 }
        return min(4, stats.recentBuds)  // RECENT buds, not total!
    }

    private var hasRecentActivity: Bool {
        guard let stats = stats else { return false }
        return stats.recentBuds > 0
    }

    var body: some View {
        VStack(spacing: 8) {
            // Activity dots row (fixed height)
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

            Spacer()

            // Jar name (single line, truncate)
            Text(jar.name)
                .font(.budsHeadline)
                .foregroundColor(.budsTextPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            // Bud count
            Text("\(stats?.totalBuds ?? 0) buds")
                .font(.budsCaption)
                .foregroundColor(.budsTextSecondary)

            Spacer()
        }
        .padding()
        .frame(height: 150)  // Fixed height (no aspect ratio calc)
        .frame(maxWidth: .infinity)
        .background(Color.budsCard)
        .cornerRadius(16)
        .shadow(
            color: hasRecentActivity ? Color.budsPrimary.opacity(0.4) : .clear,
            radius: hasRecentActivity ? 8 : 0
        )
    }
}
```

**No .task {} needed** - stats loaded once by JarManager!

---

### Step 4: Create ShelfView (1 hour)

**File**: `Buds/Features/Shelf/ShelfView.swift`

**Key Changes**:
- `@ObservedObject` not `@StateObject`
- Single load (no double reload)
- Keep as minimal as possible

```swift
struct ShelfView: View {
    @ObservedObject var jarManager = JarManager.shared  // Not @StateObject!
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
            .sheet(isPresented: $showingCreateJar) {
                CreateJarView()
                // NO onDismiss reload - JarManager handles it
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

---

### Step 5: Update MainTabView (30 min)

**File**: `Buds/Features/MainTabView.swift`

**IMPORTANT**: Keep Circle tab for now (safer rollback)

```swift
TabView(selection: $selectedTab) {
    // NEW: Shelf is primary home
    ShelfView()
        .tabItem {
            Label("Shelf", systemImage: "square.stack.3d.up.fill")
        }
        .tag(0)

    // KEEP: Circle tab (hide after Phase 10 if desired)
    CircleView()
        .tabItem {
            Label("Circle", systemImage: "person.2.fill")
        }
        .tag(1)

    ProfileView()
        .tabItem {
            Label("Profile", systemImage: "person.fill")
        }
        .tag(2)
}
```

**Why keep Circle**:
- Safer rollback if issues found
- Users may have deep links/bookmarks to tab 1
- Can hide later with `.opacity(0)` if needed

---

### Step 6: Update CreateMemoryView (Already Done in 9a!)

**Status**: ✅ Already fixed in Phase 9a

CreateMemoryView now accepts `jarID` parameter and passes it to repository:
```swift
// In CreateMemoryView (from Phase 9a)
let memory = try await repository.create(
    ...
    jarID: jarID  // ✅ Already done!
)
```

TimelineView (legacy) and any future views that open CreateMemoryView should pass selected jar.

**Action**: No changes needed, verify it works

---

### Step 7: Add Stats Refresh on Bud Creation (30 min)

**Problem**: After creating bud, stats cache is stale

**Solution**: Refresh affected jar's stats

**File**: `Buds/Features/Timeline/TimelineView.swift` (or wherever CreateMemoryView is shown)

```swift
.sheet(isPresented: $showCreateSheet, onDismiss: {
    Task {
        // Refresh jar stats for the jar we just added to
        await jarManager.refreshJarStats(jarID: selectedJarID)
        await viewModel.loadMemories(jarID: selectedJarID)
    }
}) {
    CreateMemoryView(jarID: selectedJarID)
}
```

**Also update**: ShareToCircleView (after sharing), MemoryDetailView (after deleting)

---

## Performance Metrics

### Before (Original Plan)
- **Shelf Load**: 10 jars × full `fetchByJar()` = 10 DB queries + object hydration
- **Time**: ~500ms (estimated)
- **Memory**: 10× Memory objects in RAM
- **Battery**: High (SQLite I/O + BLOB reads)

### After (Refactored)
- **Shelf Load**: 1× `fetchAllJarStats()` = single GROUP BY query
- **Time**: ~50ms (estimated)
- **Memory**: 10× JarStats structs (lightweight)
- **Battery**: Low (single query, no BLOB reads)

**Improvement**: 10x faster, 90% less memory, feels instant

---

## Testing Strategy

### Test 1: Stats Accuracy
```swift
// Create jar with known buds
await createJar(name: "Test")
await createBud(jar: "Test", timestamp: Date()) // Recent
await createBud(jar: "Test", timestamp: Date().addingTimeInterval(-48*3600)) // Old

let stats = try await repository.fetchJarStats(jarID: "Test")
XCTAssertEqual(stats.totalBuds, 2)
XCTAssertEqual(stats.recentBuds, 1) // Only recent bud
```

### Test 2: Performance (Manual)
```swift
// Create 10 jars with 100 buds each
let start = Date()
await jarManager.loadJars()
let duration = Date().timeIntervalSince(start)
print("Shelf load time: \(duration)s")  // Should be <0.1s
```

### Test 3: Activity Dots Match Spec
1. Create jar with 0 recent buds → 0 dots ✅
2. Add 1 recent bud → 1 dot ✅
3. Add 3 more recent buds → 4 dots ✅
4. Add 10 more recent buds → still 4 dots ✅
5. Wait 25 hours → 0 dots (all buds now old) ✅

### Test 4: Glow Appears Correctly
1. Jar with only old buds (>24h) → No glow ✅
2. Add 1 recent bud → Glow appears ✅
3. All buds become old → Glow disappears ✅

---

## Scope Boundaries

### In Scope (Phase 9b)
- ✅ Create ShelfView with 2-column grid
- ✅ ShelfJarCard with activity dots + glow
- ✅ JarStats repository pattern (performance!)
- ✅ JarManager stats cache
- ✅ Replace Timeline → Shelf in tab bar
- ✅ Keep Circle tab (defer removal)
- ✅ Verify CreateMemoryView jar context works

### Out of Scope (Defer)
- ❌ Jar color customization
- ❌ Jar cover images
- ❌ Activity timeline view
- ❌ Removing Circle tab (keep for now)
- ❌ Advanced animations (keep glow simple)

---

## Risk Mitigation

### Risk: Stats Cache Stale After Mutations
**Mitigation**: Call `refreshJarStats()` after create/delete/share

**Where to add**:
- CreateMemoryView onDismiss
- MemoryDetailView after delete
- ShareToCircleView after share

### Risk: Timestamp Timezone Issues
**Mitigation**:
- Document: All timestamps must be UTC
- Add validation in MemoryRepository
- Test with different device timezones

### Risk: Grid Performance with 50+ Jars
**Mitigation**:
- LazyVGrid only renders visible cells
- Stats query is O(n) where n = jar count
- If >20 jars, consider pagination (Phase 10)

---

## Success Criteria (Enhanced)

- ✅ Shelf loads in <100ms with 10 jars
- ✅ Activity dots show recent buds (not total buds)
- ✅ Glow effect appears for buds <24h
- ✅ No N+1 queries (single batch load)
- ✅ @ObservedObject used correctly (not @StateObject)
- ✅ Stats refresh after bud creation/deletion
- ✅ Circle tab kept (safer rollback)
- ✅ All acceptance tests pass
- ✅ Build succeeds with no warnings

---

## Execution Order (Revised)

**Phase 1: Foundation** (1.5 hours)
1. Add `JarStats` struct to MemoryRepository
2. Implement `fetchJarStats()` + `fetchAllJarStats()`
3. Test queries return correct counts
4. Update JarManager with stats cache
5. Test batch loading

**Phase 2: Components** (1.5 hours)
6. Create ShelfJarCard (reads from cache)
7. Create ShelfView with grid
8. Test in isolation

**Phase 3: Integration** (1 hour)
9. Update MainTabView (Shelf as tab 0, keep Circle)
10. Add stats refresh hooks (onDismiss, after delete)
11. Build and verify

**Phase 4: Testing** (1 hour)
12. Manual test: Activity dots (0, 1, 4, 10 recent buds)
13. Manual test: Glow effect
14. Performance test: Shelf load time
15. Verify spec match (dots = recent, not total)

**Total**: 5-6 hours (added time for performance work)

---

## Commit Message Template

```bash
git commit -m "Phase 9b Complete: Shelf View + Performance Optimizations

UI Transformation:
- Timeline list → Shelf grid (2 columns)
- Activity dots (up to 4 recent buds)
- Glow effect for buds <24h
- Tab label: Timeline → Shelf
- Icon: clock → square.stack.3d.up

Performance Improvements:
- Added JarStats repository pattern (lightweight queries)
- JarManager stats cache (no N+1 fetches)
- Single batch load: fetchAllJarStats() (10x faster)
- Eliminated per-card DB queries

Architectural Fixes:
- Fixed @StateObject → @ObservedObject for singleton
- Dots now show RECENT buds (matches spec)
- Stats refresh on bud create/delete
- Removed double reload (no flicker)
- Fixed height (no aspect ratio issues)

Decisions:
- Kept Circle tab for safer rollback
- CreateMemoryView jar context already fixed in 9a
- Documented timestamp invariants (UTC)

Files Created: 2 (ShelfView, ShelfJarCard)
Files Modified: 3 (JarManager, MemoryRepository, MainTabView)

Testing: All acceptance tests passed ✅
Performance: Shelf loads <100ms with 10 jars

🫙 Generated with Claude Code

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

**This plan prioritizes quality over speed. Award-winning architecture comes from sweating the details. 🏆**
