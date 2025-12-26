# Phase 9 Plan: Multi-Jar UI + Circle Rebuild

**Status**: Planning
**Timeline**: 6-8 hours
**Priority**: High (Circle UI currently broken)

---

## Goal

Rebuild Circle UI to support **multiple jars** and restore full functionality.

**User Story**: "As a user, I want to organize my buds into different jars (Solo, Friends, Tahoe Trip) and share with jar-specific members."

---

## Current State (Post-Phase 8)

✅ **Database**: Jar architecture complete (jars, jar_members tables)
✅ **Backend**: JarRepository + JarManager ready
❌ **UI**: Circle views stubbed (non-functional)
❌ **Timeline**: Only shows Solo jar (no switcher)
❌ **Sharing**: Empty member list (no jar context)

---

## What Needs to Be Built

### 1. Solo Jar Auto-Creation (30 min)

**Problem**: Fresh installs skip Solo jar creation, causing empty Timeline.

**Solution**: Add `ensureSoloJarExists()` to JarManager:
```swift
func ensureSoloJarExists() async throws {
    let jars = try await JarRepository.shared.getAllJars()
    if !jars.contains(where: { $0.id == "solo" }) {
        let did = try await IdentityManager.shared.currentDID
        _ = try await JarRepository.shared.createJar(
            name: "Solo",
            description: "Your private buds",
            ownerDID: did
        )
    }
}
```

**Call it**: In `BudsApp.swift` after auth check.

---

### 2. Jar Switcher in Timeline (1 hour)

**Design**:
```
┌──────────────────────────────────────┐
│ Timeline                   [+ New]   │ ← Nav bar
├──────────────────────────────────────┤
│ [Solo ▼]                             │ ← Jar picker
├──────────────────────────────────────┤
│ Blue Dream            Dec 24, 11:00  │
│ ⭐⭐⭐⭐⭐              Flower • 23% THC │
│ [Image]                              │
└──────────────────────────────────────┘
```

**Implementation**:
- Add `@StateObject var jarManager = JarManager.shared`
- Add `@State var selectedJarID: String = "solo"`
- Add `Picker` above Timeline cards:
  ```swift
  Picker("Jar", selection: $selectedJarID) {
      ForEach(jarManager.jars) { jar in
          Text(jar.name).tag(jar.id)
      }
  }
  .pickerStyle(.menu)
  ```
- Update `MemoryRepository.fetchAll()` → `fetchByJar(selectedJarID)`

**Files**:
- `TimelineView.swift` (add picker, filter memories)

---

### 3. Rebuild CircleView (2 hours)

**Design** (show all jars + their members):
```
┌──────────────────────────────────────┐
│ Jars                       [+ New]   │
├──────────────────────────────────────┤
│ Solo                                 │
│ 1 member • 7 buds                    │
│ ────────────────────────────────     │
│                                      │
│ Friends                              │
│ 3 members • 0 buds                   │
│ ────────────────────────────────     │
│                                      │
│ Tahoe Trip                           │
│ 5 members • 12 buds                  │
└──────────────────────────────────────┘
```

**Implementation**:
```swift
struct CircleView: View {
    @StateObject var jarManager = JarManager.shared
    @State var selectedJar: Jar?

    var body: some View {
        List(jarManager.jars) { jar in
            NavigationLink(destination: JarDetailView(jar: jar)) {
                JarCard(jar: jar)
            }
        }
        .toolbar {
            Button("New Jar") { showingCreateJar = true }
        }
    }
}
```

**Files**:
- `CircleView.swift` (rebuild to show jar list)
- `JarCard.swift` (new component for jar summary)
- `JarDetailView.swift` (new view showing jar members)
- `CreateJarView.swift` (new sheet to create jar)

---

### 4. JarDetailView (1.5 hours)

**Design** (drill-down to see jar members):
```
┌──────────────────────────────────────┐
│ < Back            Friends             │
├──────────────────────────────────────┤
│ Members (3/12)               [+ Add] │
├──────────────────────────────────────┤
│ 👤 Alice                             │
│    Active • +1 (650) 555-1234        │
│ ────────────────────────────────     │
│                                      │
│ 👤 Bob                               │
│    Active • +1 (650) 555-5678        │
│ ────────────────────────────────     │
│                                      │
│ 👤 Charlie                           │
│    Pending • Invite sent Dec 24      │
└──────────────────────────────────────┘
```

**Implementation**:
```swift
struct JarDetailView: View {
    let jar: Jar
    @State var members: [JarMember] = []

    var body: some View {
        List(members) { member in
            NavigationLink(destination: MemberDetailView(jar: jar, member: member)) {
                MemberCard(member: member)
            }
        }
        .task {
            members = try await JarRepository.shared.getMembers(jarID: jar.id)
        }
        .toolbar {
            Button("Add") { showingAddMember = true }
                .disabled(members.count >= 12)
        }
    }
}
```

**Files**:
- `JarDetailView.swift` (new view)

---

### 5. Update AddMemberView (1 hour)

**Changes**:
- Remove stub, restore functionality
- Accept `jarID: String` parameter (which jar to add to)
- Call `JarManager.addMember(jarID:phoneNumber:displayName:)`

**Implementation**:
```swift
struct AddMemberView: View {
    let jarID: String  // NEW: Which jar to add to
    @Environment(\.dismiss) var dismiss

    func addMember() {
        Task {
            try await JarManager.shared.addMember(
                jarID: jarID,  // Use passed jar
                phoneNumber: phoneNumber,
                displayName: displayName
            )
            dismiss()
        }
    }
}
```

**Files**:
- `AddMemberView.swift` (remove stub, add `jarID` parameter)

---

### 6. Update MemberDetailView (30 min)

**Changes**:
- Accept `jar: Jar` parameter (which jar this member belongs to)
- Call `JarManager.removeMember(jarID:memberDID:)` (not global removal)

**Files**:
- `MemberDetailView.swift` (remove stub, add `jar` parameter)

---

### 7. Update ShareToCircleView (1 hour)

**Changes**:
- Load members from **current jar** (not global Circle)
- Get `selectedJarID` from Timeline context
- Filter sharing to jar members only

**Implementation**:
```swift
struct ShareToCircleView: View {
    let memoryCID: String
    let jarID: String  // NEW: Which jar context we're in

    @State var members: [JarMember] = []

    var body: some View {
        // Load members for THIS jar
        .task {
            members = try await JarRepository.shared.getMembers(jarID: jarID)
        }
    }
}
```

**Files**:
- `ShareToCircleView.swift` (add `jarID` parameter, load jar members)

---

### 8. Fix Device Pinning for Jar Members (1 hour)

**Problem**: Received buds fail with `senderDeviceNotPinned` because jar members aren't in `devices` table.

**Solution**: When adding jar member, fetch and store their devices:
```swift
// In JarManager.addMember()
let devices = try await DeviceManager.shared.getDevices(for: [did])
// Store devices in local devices table with their Ed25519 keys
for device in devices {
    try await Database.shared.write { db in
        try device.insert(db)  // Store for TOFU pinning
    }
}
```

**Files**:
- `JarManager.swift` (update `addMember()` to store devices)

---

## Implementation Checklist

- [ ] 1. Add `ensureSoloJarExists()` to JarManager
- [ ] 2. Call `ensureSoloJarExists()` in BudsApp on launch
- [ ] 3. Add jar picker to TimelineView
- [ ] 4. Update TimelineView to filter by `selectedJarID`
- [ ] 5. Rebuild CircleView as jar list
- [ ] 6. Create JarCard component
- [ ] 7. Create JarDetailView (shows members)
- [ ] 8. Create CreateJarView (new jar flow)
- [ ] 9. Update AddMemberView (remove stub, add `jarID`)
- [ ] 10. Update MemberDetailView (remove stub, add `jar`)
- [ ] 11. Update ShareToCircleView (add `jarID`, load jar members)
- [ ] 12. Fix device pinning in `addMember()`
- [ ] 13. Test jar creation flow
- [ ] 14. Test member addition to jar
- [ ] 15. Test sharing to jar members
- [ ] 16. Test switching between jars in Timeline

---

## Files to Create (3)

1. `JarCard.swift` - Summary card for jar list
2. `JarDetailView.swift` - Drill-down showing jar members
3. `CreateJarView.swift` - Sheet to create new jar

---

## Files to Modify (6)

1. `TimelineView.swift` - Add jar picker, filter by jar
2. `CircleView.swift` - Rebuild as jar list (not member list)
3. `AddMemberView.swift` - Remove stub, add `jarID` parameter
4. `MemberDetailView.swift` - Remove stub, add `jar` parameter
5. `ShareToCircleView.swift` - Add `jarID`, load jar members
6. `JarManager.swift` - Add `ensureSoloJarExists()`, fix device pinning

---

## Testing Plan

### Test 1: Solo Jar Auto-Creation
1. Delete app
2. Reinstall
3. Verify Solo jar created on first launch
4. Verify Timeline shows Solo jar in picker

### Test 2: Jar Switching
1. Create "Friends" jar
2. Add bud to Solo jar
3. Add bud to Friends jar
4. Switch jar picker between Solo ↔ Friends
5. Verify Timeline shows correct buds

### Test 3: Member Management
1. Open Circle view → See jar list
2. Tap "Friends" jar → See members
3. Add member to Friends jar
4. Verify member appears in jar
5. Remove member
6. Verify member removed

### Test 4: Jar-Scoped Sharing
1. Create bud in Friends jar
2. Tap Share to Circle
3. Verify only Friends jar members shown
4. Select member, share
5. Verify member receives bud (no pinning error)

---

## Success Criteria

- ✅ Solo jar auto-created on first login
- ✅ Timeline has jar picker (switch between jars)
- ✅ CircleView shows list of jars
- ✅ Can create new jars
- ✅ Can add/remove members to/from jars
- ✅ Sharing filtered to jar members
- ✅ Device pinning works for jar members
- ✅ No "senderDeviceNotPinned" errors

---

## Estimated Timeline

| Task | Time |
|------|------|
| Solo jar auto-creation | 30 min |
| Jar switcher in Timeline | 1 hour |
| Rebuild CircleView | 2 hours |
| JarDetailView | 1.5 hours |
| Update AddMemberView | 1 hour |
| Update MemberDetailView | 30 min |
| Update ShareToCircleView | 1 hour |
| Fix device pinning | 1 hour |
| Testing | 30 min |
| **Total** | **8 hours** |

---

## Future Enhancements (Phase 10+)

- [ ] Jar-specific notifications ("New bud in Tahoe Trip")
- [ ] Jar analytics ("Most active jar: Friends")
- [ ] Jar invites (send invite link to join jar)
- [ ] Jar permissions (read-only vs full access)
- [ ] Jar archival (hide old jars)

---

**Ready to implement when you give the green light!** 🚀
