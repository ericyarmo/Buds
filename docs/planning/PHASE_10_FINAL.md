# Phase 10: Production Hardening & TestFlight

**Date**: December 26, 2025
**Timeline**: 7-9 hours
**Status**: Ready for implementation
**Goal**: Ship R1 to TestFlight with NO critical bugs, NO broken crypto, NO crashes

---

## Overview

This is the final phase before TestFlight. Focus is on **hardening, not features**. Every change must pass the question: "Will this break in production?"

After Phase 10 ships:
- Multi-device testing begins
- You build map/shop infrastructure
- Actual UX/UI work (graphics, animations, components)

---

## Critical Red Flags & Fixes

### 🔴 #1: Jar Deletion + E2EE Trust (RELEASE BLOCKER)

**Concern**: Moving buds to Solo updates `jar_id`. Does this break signature verification?

**Analysis**:
- ✅ `jar_id` in `local_receipts` (local metadata)
- ✅ Signed receipts in `ucr_headers` (immutable)
- ✅ Receipt CID from CBOR payload (not jar_id)

**BUT**: Mental model ≠ implementation proof.

**Step 0.1 - Exact Test**:
```swift
// Test: Signature Verification Invariance
1. Create jar "Crypto Test"
2. Add bud to jar
3. Share bud with friend (E2EE)

// On sending device:
4. Log verification bytes BEFORE delete:
   - Receipt CID
   - Signature bytes (hex)
   - Public key used

5. Delete jar → bud moves to Solo

6. Re-verify SAME receipt on sending device:
   - Log verification bytes AFTER delete
   - Assert: bytes UNCHANGED

// On receiving device:
7. Before jar delete: verify signature → PASS
8. After jar delete: verify signature → MUST STILL PASS
9. Verify CID unchanged
10. Verify decryption works

**CRITICAL**: If bytes change OR verification fails → ABORT TestFlight
```

**Pass criteria**: Exact same verification input bytes before/after jar move.

---

### 🔴 #2: Nested Sheets = UI Bugs

**Issue**: Your CreateMemoryFlowView uses nested sheets:
```swift
// Shelf opens sheet
.sheet { CreateMemoryFlowView }
  // Which opens ANOTHER sheet
  .sheet { CreateMemoryView }
```

This causes:
- Stuck presentation state
- Sheet dismissal bugs
- "Sheet doesn't open second time"
- Weird animation stacking

**Fix**: Single sheet with NavigationStack
```swift
// ShelfView.swift
.sheet(isPresented: $showCreateMemory, onDismiss: {
    Task {
        // Refresh happens in CreateMemoryView.onDisappear
    }
}) {
    NavigationStack {
        JarPickerView(onJarSelected: { jarID in
            // Navigate to create view
        })
    }
}

// JarPickerView.swift
struct JarPickerView: View {
    @ObservedObject var jarManager = JarManager.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        List {
            ForEach(jarManager.jars) { jar in
                NavigationLink(destination: CreateMemoryView(jarID: jar.id)) {
                    HStack {
                        Text(jar.name)
                        Spacer()
                        Text("\(jarManager.jarStats[jar.id]?.totalBuds ?? 0) buds")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Choose Jar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}

// CreateMemoryView already has:
.onDisappear {
    Task {
        await jarManager.refreshJar(jarID: selectedJarID)  // Lightweight refresh
    }
}
```

**No nested .sheet()!** One sheet, NavigationStack inside, NavigationLink to create.

---

### 🔴 #3: Lightweight Query Still Decodes JSON

**Issue**: `fetchLightweightList()` does `JSONDecoder.decode()` per row. Not "free" at 50+ rows.

**Realistic Options**:

**Option A (Recommended for R1)**: In-memory decode cache
```swift
// MemoryRepository.swift
private var decodeCache: [String: SessionPayload] = [:]  // CID → payload

func fetchLightweightList(jarID: String, limit: Int = 50) async throws -> [MemoryListItem] {
    try await db.readAsync { db in
        let rows = try Row.fetchAll(db, sql: sql, arguments: [...])

        return rows.compactMap { row in
            let cid = row["cid"] as String
            let payloadJSON = row["payload_json"] as String

            // Check cache first
            let payload: SessionPayload
            if let cached = decodeCache[cid] {
                payload = cached
            } else {
                guard let data = payloadJSON.data(using: .utf8),
                      let decoded = try? JSONDecoder().decode(SessionPayload.self, from: data) else {
                    return nil
                }
                payload = decoded
                decodeCache[cid] = decoded
            }

            // Build MemoryListItem from cached payload
            return MemoryListItem(...)
        }
    }
}
```

**Option B (Future)**: Store summary fields in `local_receipts`:
```sql
-- Would require migration
ALTER TABLE local_receipts
  ADD COLUMN strain_name TEXT,
  ADD COLUMN rating INTEGER,
  ADD COLUMN product_type TEXT;
```

**R1 Decision**: Use Option A (cache). ~100 lines of code, zero migration risk.

---

### 🔴 #4: refreshAfterMutation() Might Be Overkill

**Issue**: Every create/delete reloads ALL jars + ALL stats. Can cause:
- UI flicker
- Unnecessary network/disk IO
- "Reload storms 2.0"

**Fix**: Split into two tiers

```swift
// JarManager.swift
@MainActor
class JarManager: ObservableObject {
    @Published var jars: [Jar] = []
    @Published var jarStats: [String: JarStats] = [:]
    @Published var isLoading = false

    // TIER 1: Full reload (jar create/delete, member changes, inbox receive)
    func refreshGlobal() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let jarsResult = JarRepository.shared.getAllJars()
            async let statsResult = MemoryRepository().fetchAllJarStats()

            let (loadedJars, loadedStats) = try await (jarsResult, statsResult)

            self.jars = loadedJars
            self.jarStats = loadedStats

            print("✅ Global refresh: \(jars.count) jars")
        } catch {
            print("❌ Failed global refresh: \(error)")
        }
    }

    // TIER 2: Lightweight (bud create/delete, single jar affected)
    func refreshJar(_ jarID: String) async {
        do {
            // Only update stats for this one jar
            let allStats = try await MemoryRepository().fetchAllJarStats()

            if let updatedStat = allStats[jarID] {
                self.jarStats[jarID] = updatedStat
            } else {
                // Jar might be empty now
                self.jarStats[jarID] = JarStats(
                    jarID: jarID,
                    totalBuds: 0,
                    recentBuds: 0,
                    lastCreatedAt: nil
                )
            }

            // Notify only this jar changed
            NotificationCenter.default.post(
                name: .jarContentsChanged,
                object: jarID
            )

            print("✅ Refreshed jar: \(jarID)")
        } catch {
            print("❌ Failed to refresh jar: \(error)")
        }
    }
}

// Usage:
// After create bud: await jarManager.refreshJar(budJarID)
// After delete bud: await jarManager.refreshJar(budJarID)
// After jar delete: await jarManager.refreshGlobal()  // Structural change
// After jar create: await jarManager.refreshGlobal()
// After inbox receive: await jarManager.refreshJar(inferredJarID)
```

**Performance Impact**:
- Create bud: Was 50ms (reload all), now 10ms (one jar)
- Delete bud: Was 50ms, now 10ms
- Jar delete: Still 50ms (needs global)
- Scroll Shelf: No change

---

### 🟡 Smaller Issues (Must Fix)

**A) NotificationCenter MainActor Safety**
```swift
// Extensions/NotificationNames.swift
extension Notification.Name {
    static let jarContentsChanged = Notification.Name("jarContentsChanged")
}

// JarDetailView.swift
.onReceive(NotificationCenter.default.publisher(for: .jarContentsChanged)) { notification in
    // This closure runs on MainActor (SwiftUI guarantees it)
    if let changedJarID = notification.object as? String,
       changedJarID == jar.id {
        Task { @MainActor in  // Explicit, though redundant
            await viewModel.loadMemories(jarID: jar.id)
        }
    }
}
```

**B) AsyncImage Caching**
```swift
// Shared/Components/CachedAsyncImage.swift
struct CachedAsyncImage: View {
    let cid: String
    @State private var imageData: Data?

    private static var cache: [String: Data] = [:]

    var body: some View {
        Group {
            if let data = imageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ProgressView()
            }
        }
        .task {
            // Check cache
            if let cached = Self.cache[cid] {
                imageData = cached
                return
            }

            // Load from DB
            do {
                let data = try await Database.shared.readAsync { db in
                    try Data.fetchOne(db, sql: "SELECT data FROM blobs WHERE cid = ?", arguments: [cid])
                }

                if let data = data {
                    Self.cache[cid] = data
                    imageData = data
                }
            } catch {
                print("❌ Failed to load image: \(error)")
            }
        }
    }
}
```

**C) Thumbnail Pipeline**
```swift
// Ensure thumbnails are actually small
// In addImages():
func addImages(to memoryId: UUID, images: [Data]) async throws {
    for imageData in images {
        // CRITICAL: Downscale to thumbnail before storing
        guard let downsized = downsizeImage(imageData, maxDimension: 800) else {
            continue
        }

        let cid = try generateImageCID(data: downsized)
        // Store downsized, not original
        try db.execute(..., arguments: [cid, downsized, ...])
    }
}

private func downsizeImage(_ data: Data, maxDimension: CGFloat) -> Data? {
    guard let image = UIImage(data: data) else { return nil }

    let size = image.size
    let scale = min(maxDimension / size.width, maxDimension / size.height)

    if scale >= 1.0 { return data }  // Already small enough

    let newSize = CGSize(width: size.width * scale, height: size.height * scale)

    UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
    image.draw(in: CGRect(origin: .zero, size: newSize))
    let resized = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()

    return resized?.jpegData(compressionQuality: 0.8)
}
```

---

## Implementation Plan

### Step 0: Critical Pre-Flight (1.5 hours) - DO THIS FIRST

**0.1: E2EE Verification Invariance Test**
- Implement exact test from Red Flag #1
- Log verification bytes before/after jar move
- **ABORT if bytes change or verification fails**

**0.2: Archive + Validate Early**
```bash
# Clean build
CMD+SHIFT+K

# Archive (don't wait!)
Product → Archive

# Validate
Organizer → Validate App

# Check for:
- Export compliance questions (E2EE)
- Privacy manifest issues
- Entitlements errors
- Provisioning profile issues

# Answer export compliance NOW
# Fix any issues BEFORE continuing
```

**0.3: Memory Baseline Test**
```swift
// Create 100 buds in one jar
// Tap jar → measure memory usage with Xcode Instruments
// Target: <100MB

// If fails: thumbnail pipeline broken, fix before ship
```

---

### Step 1: Single-Sheet Create Flow (2 hours)

**1.1: Create JarPickerView** (no nested sheets!)
```swift
// See Red Flag #2 above for full implementation
struct JarPickerView: View {
    // List of jars
    // NavigationLink to CreateMemoryView(jarID:)
}
```

**1.2: Shelf FAB**
```swift
// ShelfView.swift
@State private var showCreateMemory = false

var body: some View {
    NavigationStack {
        // ... existing shelf grid
    }
    .overlay(alignment: .bottomTrailing) {
        Button {
            showCreateMemory = true
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.budsPrimary)
                .background(Circle().fill(Color.black))
                .shadow(radius: 4)
        }
        .padding(20)
    }
    .sheet(isPresented: $showCreateMemory) {
        NavigationStack {
            JarPickerView()
        }
    }
}
```

**1.3: CreateMemoryView updates**
```swift
// Remove onDismiss refresh (moved to .onDisappear)
// Add .onDisappear:
.onDisappear {
    Task {
        await JarManager.shared.refreshJar(jarID)  // Lightweight!
    }
}
```

**1.4: JarDetailView Empty State**
```swift
private var emptyMemoriesState: some View {
    VStack(spacing: 16) {
        Image(systemName: "leaf")
            .font(.system(size: 60))
            .foregroundColor(.budsPrimary.opacity(0.3))

        Text("No buds yet")
            .font(.budsHeadline)

        Text("Start logging your cannabis experiences")
            .font(.budsBody)
            .foregroundColor(.budsTextSecondary)

        NavigationLink(destination: CreateMemoryView(jarID: jar.id)) {
            HStack {
                Image(systemName: "plus.circle")
                Text("Add Your First Bud")
            }
            .font(.budsBodyBold)
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.budsPrimary)
            .cornerRadius(12)
        }
    }
    .padding(.vertical, 40)
}
```

---

### Step 2: Lightweight Memory List (2 hours)

**2.1: Create MemoryListItem Model**
```swift
// Models/MemoryListItem.swift
struct MemoryListItem: Identifiable {
    let id: UUID
    let strainName: String
    let productType: ProductType
    let rating: Int
    let createdAt: Date
    let thumbnailCID: String?
    let jarID: String
}
```

**2.2: Update MemoryRepository**
```swift
// Add decode cache (see Red Flag #3)
private var decodeCache: [String: SessionPayload] = [:]

func fetchLightweightList(jarID: String, limit: Int = 50) async throws -> [MemoryListItem] {
    // Implementation from Red Flag #3
}
```

**2.3: Create MemoryListCard Component**
```swift
// Shared/Components/MemoryListCard.swift
struct MemoryListCard: View {
    let item: MemoryListItem
    let onTap: () async -> Void

    private let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail (cached)
            if let thumbnailCID = item.thumbnailCID {
                CachedAsyncImage(cid: thumbnailCID)
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
            } else {
                Rectangle()
                    .fill(Color.budsPrimary.opacity(0.2))
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.strainName)
                    .font(.budsBodyBold)
                    .lineLimit(1)

                HStack(spacing: 2) {
                    ForEach(0..<item.rating, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundColor(.budsPrimary)
                    }
                }

                Text(relativeDateFormatter.localizedString(for: item.createdAt, relativeTo: Date()))
                    .font(.budsCaption)
                    .foregroundColor(.budsTextSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.budsCard)
        .cornerRadius(12)
        .onTapGesture {
            Task { await onTap() }
        }
    }
}
```

**2.4: Update JarDetailView**
```swift
// Use lightweight items
@Published var memoryItems: [MemoryListItem] = []  // NOT Memory objects!

func loadMemories(jarID: String) async {
    isLoading = true
    defer { isLoading = false }

    do {
        memoryItems = try await repository.fetchLightweightList(jarID: jarID, limit: 50)
    } catch {
        print("❌ Failed to load memories: \(error)")
    }
}

// In view:
LazyVStack(spacing: 12) {
    ForEach(viewModel.memoryItems) { item in
        MemoryListCard(item: item) {
            // Load full memory ONLY when tapped
            await viewModel.loadFullMemory(id: item.id)
        }
    }

    if viewModel.memoryItems.count >= 50 {
        Button("Load More") {
            await viewModel.loadMore()
        }
        .buttonStyle(.bordered)
    }
}

func loadFullMemory(id: UUID) async {
    do {
        let fullMemory = try await repository.fetch(id: id)
        selectedMemory = fullMemory
    } catch {
        print("❌ Failed to load full memory: \(error)")
    }
}
```

---

### Step 3: Split Refresh Logic (1 hour)

**3.1: Implement refreshGlobal() + refreshJar()** (see Red Flag #4)

**3.2: Update all call sites**:
```swift
// CreateMemoryView.onDisappear
await jarManager.refreshJar(jarID)  // Lightweight!

// MemoryDetailView after delete
await jarManager.refreshJar(memory.jarID)  // Lightweight!

// ShelfView after jar delete
await jarManager.refreshGlobal()  // Full reload needed

// CreateJarView.onDismiss
await jarManager.refreshGlobal()  // Full reload needed

// InboxManager after receive
await jarManager.refreshJar(inferredJarID)  // Lightweight!
```

**3.3: Update JarDetailView listener**
```swift
.onReceive(NotificationCenter.default.publisher(for: .jarContentsChanged)) { notification in
    if let changedJarID = notification.object as? String,
       changedJarID == jar.id {
        Task { @MainActor in
            await viewModel.loadMemories(jarID: jar.id)
        }
    }
}
```

---

### Step 4: Shelf Polish (1 hour)

**4.1: Pull-to-refresh**
```swift
// ShelfView.swift
private var jarGrid: some View {
    ScrollView {
        LazyVGrid(columns: columns, spacing: 16) {
            // ... jar cards
        }
        .padding()
    }
    .refreshable {
        await jarManager.refreshGlobal()  // User explicitly pulled
    }
}
```

**4.2: Last activity with RelativeDateTimeFormatter**
```swift
// ShelfJarCard.swift
private let relativeDateFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter
}()

// In body:
if let lastCreated = stats?.lastCreatedAt {
    Text(relativeDateFormatter.localizedString(for: lastCreated, relativeTo: Date()))
        .font(.system(size: 11))
        .foregroundColor(.budsTextSecondary.opacity(0.7))
}
```

**4.3: Haptic feedback**
```swift
// On jar tap
.simultaneousGesture(
    TapGesture()
        .onEnded { _ in
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
)

// On jar delete
Button("Delete", role: .destructive) {
    let generator = UIImpactFeedbackGenerator(style: .medium)
    generator.impactOccurred()
    // ... delete logic
}
```

---

### Step 5: Toast + Polish (30 min)

**5.1: Toast Component** (reusable, single-flight)
```swift
// Shared/Components/Toast.swift
struct Toast: View {
    let message: String
    let icon: String?

    var body: some View {
        HStack(spacing: 12) {
            if let icon = icon {
                Image(systemName: icon)
                    .foregroundColor(.white)
            }
            Text(message)
                .font(.budsBody)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.budsPrimary)
        .cornerRadius(12)
        .shadow(radius: 8)
    }
}

// Toast Manager (single-flight)
@MainActor
class ToastManager: ObservableObject {
    @Published var currentToast: (message: String, icon: String?)?
    @Published var isShowing = false

    func show(_ message: String, icon: String? = nil, duration: TimeInterval = 2.0) {
        currentToast = (message, icon)
        isShowing = true

        Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            isShowing = false
        }
    }
}
```

**5.2: ShelfView toast**
```swift
@StateObject private var toastManager = ToastManager()

// After jar delete
if budCount > 0 {
    toastManager.show("\(budCount) buds moved to Solo", icon: "checkmark.circle.fill")
}

// In body
.overlay(alignment: .bottom) {
    if toastManager.isShowing, let toast = toastManager.currentToast {
        Toast(message: toast.message, icon: toast.icon)
            .padding(.bottom, 50)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(), value: toastManager.isShowing)
    }
}
```

---

### Step 6: Bug Fixes & Hardening (1 hour)

**6.1: Run Step 0.1 E2EE Test** (CRITICAL)
- If fails → ABORT, fix crypto

**6.2: Run Memory Baseline Test**
- 100 buds → should be <100MB
- If fails → thumbnail pipeline broken

**6.3: Fresh Install Test**
```bash
# Delete app from simulator
# Reinstall
# Verify Solo jar created automatically
# Create jar, add bud, delete jar
# Verify bud moved to Solo
```

**6.4: Stress Test**
```bash
# Create 10 jars
# Add 100 buds to one jar
# Scroll jar detail view rapidly
# Measure performance: should be smooth 60fps
```

**6.5: Edge Cases**
- Delete jar while viewing JarDetailView (should dismiss gracefully)
- Create bud while offline (should queue for send)
- Receive shared bud while app in background (should update on foreground)

---

### Step 7: TestFlight Prep (1 hour)

**7.1: Update Version**
```swift
// Info.plist
CFBundleShortVersionString: 1.0.0
CFBundleVersion: 1
```

**7.2: Create CHANGELOG.md**
```markdown
# Changelog

## 1.0.0 (R1) - December 26, 2025

### Core Features
- Multi-jar organization system
- Shelf grid view with activity indicators
- E2EE sharing with Circle members
- TOFU device pinning for security
- Jar deletion with memory preservation

### Known Limitations
- Multi-device sync not implemented (R2)
- No cloud backup (R2)
- No map or shop features (R3)
- Local storage only (data lost if app deleted)

### Testing Focus
- Create jars and organize buds
- Share buds with friends (test E2EE)
- Delete jars (verify buds move to Solo)
- Multi-device testing (2+ devices)
- Performance with 100+ buds

### Technical Notes
- Lightweight memory list (50-item cap)
- Cached image loading
- Split refresh strategy (global vs per-jar)
- Export compliance: Uses standard Apple crypto APIs
```

**7.3: Beta Tester Notes**
```
Buds R1 - Initial TestFlight

Focus Areas:
1. E2EE Sharing - Add friends, share buds, verify encryption
2. Jar Management - Create/delete jars, verify memories preserved
3. Performance - Test with 50+ buds, report any lag
4. Edge Cases - Kill app during operations, test offline mode

Known Issues:
- Multi-device sync coming in R2
- Data is local-only (backup manually if needed)
- Map and shop features coming later

Please report:
- Crashes or hangs
- Signature verification failures
- UI bugs or confusion
- Performance issues
```

**7.4: Archive & Upload**
```bash
# Final clean build
CMD+SHIFT+K
CMD+B

# Archive
Product → Archive

# Validate
Organizer → Validate App

# Upload
Distribute App → App Store Connect → Upload

# Submit for Review
App Store Connect → TestFlight → Submit
```

---

## Files Summary

### New Files (8):
1. `MemoryListItem.swift` - Lightweight list model
2. `MemoryListCard.swift` - Lightweight card component
3. `JarPickerView.swift` - Jar selection before create
4. `CachedAsyncImage.swift` - Image caching component
5. `Toast.swift` + `ToastManager.swift` - Toast notifications
6. `CHANGELOG.md` - Version history
7. `Extensions/NotificationNames.swift` - Notification name constants

### Modified Files (~12):
1. `MemoryRepository.swift` - Add `fetchLightweightList()` + decode cache
2. `JarManager.swift` - Split into `refreshGlobal()` + `refreshJar()`
3. `JarDetailView.swift` - Use lightweight list, add empty state
4. `ShelfView.swift` - Add FAB, pull-to-refresh, toast
5. `ShelfJarCard.swift` - RelativeDateTimeFormatter for timestamps
6. `CreateMemoryView.swift` - Move refresh to .onDisappear
7. `TimelineView.swift` - Use `refreshJar()` instead of `loadJars()`
8. `InboxManager.swift` - Call `refreshJar()` after receive
9. `MemoryDetailView.swift` - Use `refreshJar()` after delete
10. `Info.plist` - Version 1.0.0, build 1
11. Add image downscaling in `addImages()`
12. Xcode project settings

---

## Timeline Breakdown

| Step | Task | Time | Priority |
|------|------|------|----------|
| 0 | Pre-flight (E2EE test, archive early) | 1.5h | P0 |
| 1 | Single-sheet create flow | 2h | P0 |
| 2 | Lightweight memory list | 2h | P0 |
| 3 | Split refresh logic | 1h | P0 |
| 4 | Shelf polish | 1h | P1 |
| 5 | Toast + polish | 30m | P1 |
| 6 | Bug fixes & hardening | 1h | P0 |
| 7 | TestFlight prep | 1h | P0 |
| **Total** | | **9h** | |

**Critical path** (must complete): Steps 0, 1, 2, 3, 6, 7 = **7.5 hours**

**Can defer to R1.1**: Step 4 (some polish), Step 5 (toast)

---

## ABORT TestFlight If:

1. ❌ Step 0.1 fails (signature verification breaks after jar move)
2. ❌ Memory baseline >100MB with 100 buds (thumbnail pipeline broken)
3. ❌ Archive validation fails (signing/privacy issues)
4. ❌ Export compliance blocked

**DO NOT SHIP BROKEN CRYPTO, CRASHING UX, OR INVALID BUILDS.**

---

## Success Criteria

### Must Pass:
- ✅ E2EE verification bytes unchanged before/after jar move
- ✅ Can create buds from Shelf FAB and JarDetailView
- ✅ Jar detail list smooth with 100+ buds (<100MB memory)
- ✅ refreshJar() for lightweight ops, refreshGlobal() for structural
- ✅ No nested sheets (single NavigationStack)
- ✅ RelativeDateTimeFormatter for all timestamps
- ✅ Image cache prevents scroll stutter
- ✅ Thumbnails downscaled before storage
- ✅ Fresh install creates Solo jar
- ✅ Archive + upload succeeds

### Should Pass:
- ✅ Pull-to-refresh on Shelf
- ✅ Toast after jar delete
- ✅ Haptic feedback on interactions
- ✅ NotificationCenter MainActor-safe

### Can Defer:
- ⏭️ Advanced image caching (LRU eviction)
- ⏭️ "Load more" pagination (if 50-item cap sufficient)
- ⏭️ Onboarding tutorial

---

## Post-Phase 10

### Immediate (This Week):
- ✅ Ship R1 to TestFlight
- ✅ External testers install on 2+ devices
- ✅ Multi-device E2EE testing begins
- ✅ Start building map/shop infrastructure
- ✅ Begin UX/UI work (graphics, animations)

### R1.1 (Next Week):
- Fix critical bugs from TestFlight feedback
- Add "Load more" if 50-item cap too limiting
- Advanced image caching (LRU)
- Onboarding improvements

### R2 (Q1 2026):
- Multi-device sync (receipt-based)
- Cloud backup (iCloud/R2)
- Map view infrastructure
- Shop marketplace basics

---

## Red Flag Checklist (Final Verification)

Before ship, verify:
- [ ] jar_id update doesn't change verification bytes (Step 0.1)
- [ ] No nested sheets (JarPickerView uses NavigationStack)
- [ ] fetchLightweightList uses decode cache
- [ ] refreshJar() for bud ops, refreshGlobal() for jar ops
- [ ] NotificationCenter posts on MainActor
- [ ] CachedAsyncImage prevents redundant loads
- [ ] Thumbnails downscaled to 800px max
- [ ] Memory usage <100MB with 100 buds
- [ ] Export compliance answered
- [ ] Privacy manifest correct

---

**Ship R1. No broken crypto. No crashes. Production-ready.** 🛡️🚀
