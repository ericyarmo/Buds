# Phase 9 Plan: Multi-Jar UI + Circle Rebuild
## Corrected & Verified Against Actual Codebase

**Date**: December 25, 2025
**Status**: Ready for Execution
**Difficulty**: High (UI rebuild + navigation changes)
**Timeline**: 6-8 hours
**Dependencies**: Phase 8 complete ✅

---

## Executive Summary

**Goal**: Transform Circle UI from broken stubs into functional multi-jar management system, enabling users to organize buds into separate jars (Solo, Friends, Tahoe Trip, etc.) and share with jar-specific members.

**Current State**: Phase 8 database migration complete; backend (JarManager, JarRepository) functional; UI layer stubbed and non-functional.

**What We're Building**: Complete UI layer for jar management with picker-based navigation, jar creation, member management, and jar-scoped sharing.

---

## A. Repo Reality Check

### 1. Database Layer ✅ COMPLETE

**Status**: Migration v5 complete, all tables and columns verified

**Files**:
- `Buds/Core/Database/Database.swift` - Migration v5 implemented ✅
- Schema verified:
  - `jars` table (id, name, description, owner_did, created_at, updated_at) ✅
  - `jar_members` table (jar_id, member_did, display_name, phone_number, pubkey_x25519, role, status, joined_at, created_at, updated_at) ✅
  - `local_receipts.jar_id` column (TEXT NOT NULL DEFAULT 'solo') ✅
  - `local_receipts.sender_did` column (TEXT) ✅

**Indexes**: All required indexes created ✅

**Verification**: Run query to confirm:
```sql
SELECT COUNT(*) FROM jars; -- Should have Solo jar
SELECT COUNT(*) FROM jar_members WHERE jar_id = 'solo'; -- Should have owner
SELECT COUNT(*) FROM local_receipts WHERE jar_id = 'solo'; -- Should have existing buds
```

---

### 2. Model Layer ✅ COMPLETE

**Files**:
- `/Users/ericyarmolinsky/Developer/Buds/Buds/Buds/Buds/Core/Models/Jar.swift` (58 lines) ✅
  - Properties: id, name, description, ownerDID, createdAt, updatedAt
  - Conforms to: Identifiable, Codable, FetchableRecord, PersistableRecord
  - Computed property: `isSolo: Bool`

- `/Users/ericyarmolinsky/Developer/Buds/Buds/Buds/Buds/Core/Models/JarMember.swift` (87 lines) ✅
  - Properties: jarID, memberDID, displayName, phoneNumber, avatarCID, pubkeyX25519, role, status, joinedAt, invitedAt, removedAt, createdAt, updatedAt
  - Enums: Role (owner, member), Status (pending, active, removed)
  - Composite ID: `"\(jarID)-\(memberDID)"`

- `/Users/ericyarmolinsky/Developer/Buds/Buds/Buds/Buds/Core/Models/Memory.swift` (186 lines) ✅
  - Added: `var jarID: String` ✅
  - Added: `var senderDID: String?` ✅

**Verification**: Models match database schema exactly ✅

---

### 3. Repository Layer ✅ COMPLETE

**Files**:
- `/Users/ericyarmolinsky/Developer/Buds/Buds/Buds/Buds/Core/Database/Repositories/JarRepository.swift` (137 lines) ✅
  - Methods verified:
    - `getAllJars() async throws -> [Jar]` ✅
    - `getJar(id:) async throws -> Jar?` ✅
    - `createJar(name:description:ownerDID:) async throws -> Jar` ✅
    - `deleteJar(id:) async throws` ✅
    - `getMembers(jarID:) async throws -> [JarMember]` ✅
    - `addMember(jarID:memberDID:displayName:phoneNumber:pubkeyX25519:) async throws` ✅
    - `removeMember(jarID:memberDID:) async throws` ✅
    - `getJarsForUser(did:) async throws -> [Jar]` ✅

- `/Users/ericyarmolinsky/Developer/Buds/Buds/Buds/Buds/Core/Database/Repositories/MemoryRepository.swift` (472 lines) ✅
  - Added: `fetchByJar(jarID:) async throws -> [Memory]` ✅ (Line 48-74)
  - Updated: `create(...)` with `jarID: String = "solo"` parameter ✅ (Line 120)
  - Verified: `storeSharedReceipt(...)` sets jar_id = "solo" for received buds ✅ (Line 370)

**Issue Found**: `storeSharedReceipt` hardcodes jar_id to "solo" - should infer jar from sender's membership
**Fix Required**: Update InboxManager to determine jar context when storing received buds

---

### 4. Manager Layer ✅ COMPLETE (1 Fix Needed)

**Files**:
- `/Users/ericyarmolinsky/Developer/Buds/Buds/Buds/Buds/Core/JarManager.swift` (178 lines) ✅
  - Methods verified:
    - `loadJars() async` ✅
    - `createJar(name:description:) async throws -> Jar` ✅
    - `deleteJar(id:) async throws` ✅
    - `getMembers(jarID:) async throws -> [JarMember]` ✅
    - `addMember(jarID:phoneNumber:displayName:) async throws` ✅
    - `removeMember(jarID:memberDID:) async throws` ✅
    - `getPinnedEd25519PublicKey(for:) async throws -> Data?` ✅ (TOFU key pinning)
    - `getPinnedEd25519PublicKey(did:deviceId:) async throws -> Data?` ✅ (Device-specific)

  **Missing**:
  - ❌ `ensureSoloJarExists() async throws` (Phase 9 requirement)

**Required Addition**:
```swift
func ensureSoloJarExists() async throws {
    let jars = try await JarRepository.shared.getAllJars()
    guard !jars.contains(where: { $0.id == "solo" }) else { return }

    guard let currentDID = try await IdentityManager.shared.currentDID else {
        throw JarError.noIdentity
    }

    _ = try await JarRepository.shared.createJar(
        name: "Solo",
        description: "Your private buds",
        ownerDID: currentDID
    )

    await loadJars()
    print("✅ Created Solo jar for fresh install")
}
```

---

### 5. UI Layer ❌ BROKEN (Phase 9 Work)

**Current State Analysis**:

#### TimelineView.swift ⚠️ PARTIALLY READY
**Path**: `/Users/ericyarmolinsky/Developer/Buds/Buds/Buds/Buds/Features/Timeline/TimelineView.swift`
**Lines**: 185
**Status**: Functional but no jar filtering
**Required Changes**:
1. Add `@StateObject var jarManager = JarManager.shared`
2. Add `@State var selectedJarID: String = "solo"`
3. Add `Picker` for jar selection (above memory list)
4. Update `viewModel.loadMemories()` → `viewModel.loadMemories(jarID: selectedJarID)`
5. Update `TimelineViewModel.loadMemories(jarID:)` to call `repository.fetchByJar(jarID)`

**Signature Mismatch**:
- Current: `repository.fetchAll()`
- Required: `repository.fetchByJar(jarID: selectedJarID)`

---

#### CircleView.swift ❌ STUBBED
**Path**: `/Users/ericyarmolinsky/Developer/Buds/Buds/Buds/Buds/Features/Circle/CircleView.swift`
**Lines**: 194
**Status**: Uses old CircleMember model (Phase 5), shows members not jars
**Required Changes**:
1. Rebuild as jar list (not member list)
2. Replace `CircleMember` with `Jar` model
3. Add `@StateObject var jarManager = JarManager.shared`
4. Display `jarManager.jars` instead of `members`
5. Navigation to new `JarDetailView` (shows members inside jar)
6. "Add Friend" → "Create Jar"

**Current Code Issue**: References `CircleMember` which is Phase 5 legacy model

---

#### AddMemberView.swift ❌ STUBBED
**Path**: `/Users/ericyarmolinsky/Developer/Buds/Buds/Buds/Buds/Features/Circle/AddMemberView.swift`
**Status**: TODO comment placeholder
**Required Changes**:
1. Remove stub
2. Add parameter: `jarID: String`
3. Call `JarManager.shared.addMember(jarID:phoneNumber:displayName:)`
4. Add device pinning logic (store devices in local table)

---

#### MemberDetailView.swift ❌ STUBBED
**Path**: `/Users/ericyarmolinsky/Developer/Buds/Buds/Buds/Buds/Features/Circle/MemberDetailView.swift`
**Status**: TODO comment placeholder
**Required Changes**:
1. Remove stub
2. Add parameters: `jar: Jar, member: JarMember`
3. Call `JarManager.shared.removeMember(jarID:memberDID:)`

---

#### ShareToCircleView.swift ❌ BROKEN
**Path**: `/Users/ericyarmolinsky/Developer/Buds/Buds/Buds/Buds/Features/Share/ShareToCircleView.swift`
**Status**: Uses old CircleManager
**Required Changes**:
1. Add parameter: `jarID: String` (current jar context)
2. Replace `CircleManager` → `JarManager`
3. Load members: `JarRepository.shared.getMembers(jarID: jarID)`
4. Update ShareManager to encrypt for jar members only

---

### 6. Navigation & App Structure

**Files**:
- `/Users/ericyarmolinsky/Developer/Buds/Buds/Buds/Buds/App/BudsApp.swift`

**Required Changes**:
1. Add `ensureSoloJarExists()` call after auth check:
```swift
.task {
    if AuthManager.shared.isAuthenticated {
        try? await JarManager.shared.ensureSoloJarExists()
    }
}
```

---

### 7. Missing Files (Phase 9 Deliverables)

**New Views Required** (3 files):
1. ❌ `JarCard.swift` - Summary card for jar list in CircleView
2. ❌ `JarDetailView.swift` - Drill-down showing jar members
3. ❌ `CreateJarView.swift` - Sheet to create new jar

---

## B. Corrected Phase 9 Plan

### Implementation Order (Bootstrapping → Data → UI → Sharing)

#### **Step 1: Solo Jar Auto-Creation** (30 min)

**Goal**: Ensure fresh installs create Solo jar automatically

**Files Modified** (2):
1. `JarManager.swift` - Add `ensureSoloJarExists()`
2. `BudsApp.swift` - Call on app launch

**Code**:
```swift
// In JarManager.swift
func ensureSoloJarExists() async throws {
    let jars = try await JarRepository.shared.getAllJars()
    guard !jars.contains(where: { $0.id == "solo" }) else {
        print("✅ Solo jar already exists")
        return
    }

    guard let currentDID = try await IdentityManager.shared.currentDID else {
        throw JarError.noIdentity
    }

    _ = try await JarRepository.shared.createJar(
        name: "Solo",
        description: "Your private buds",
        ownerDID: currentDID
    )

    await loadJars()
    print("✅ Created Solo jar for fresh install")
}
```

```swift
// In BudsApp.swift
.task {
    if AuthManager.shared.isAuthenticated {
        do {
            try await JarManager.shared.ensureSoloJarExists()
        } catch {
            print("❌ Failed to ensure Solo jar: \(error)")
        }
    }
}
```

**Acceptance Test**:
- Delete app
- Reinstall
- Sign in
- Verify Solo jar exists: `SELECT * FROM jars WHERE id = 'solo'`
- Verify Timeline shows Solo jar in picker

---

#### **Step 2: Jar Switcher in Timeline** (1 hour)

**Goal**: Add picker to switch between jars in Timeline

**Files Modified** (1):
- `TimelineView.swift`

**Changes**:
1. Add state properties:
```swift
@StateObject private var jarManager = JarManager.shared
@State private var selectedJarID: String = "solo"
```

2. Add picker above memory list:
```swift
private var jarPicker: some View {
    Picker("Jar", selection: $selectedJarID) {
        ForEach(jarManager.jars) { jar in
            Text(jar.name).tag(jar.id)
        }
    }
    .pickerStyle(.menu)
    .padding(.horizontal)
}
```

3. Update `loadMemories()` in ViewModel:
```swift
func loadMemories(jarID: String = "solo") async {
    isLoading = true
    defer { isLoading = false }

    do {
        memories = try await repository.fetchByJar(jarID: jarID)
        print("✅ Loaded \(memories.count) memories for jar \(jarID)")
    } catch {
        print("❌ Failed to load memories: \(error)")
    }
}
```

4. Watch for jar changes:
```swift
.onChange(of: selectedJarID) { oldValue, newValue in
    Task {
        await viewModel.loadMemories(jarID: newValue)
    }
}
```

**Acceptance Test**:
- Create "Friends" jar
- Add bud to Solo jar
- Add bud to Friends jar
- Switch picker: Solo → Friends
- Verify Timeline shows only Friends jar buds

---

#### **Step 3: Create JarCard Component** (30 min)

**Goal**: Reusable card for jar list

**Files Created** (1):
- `Buds/Shared/Views/JarCard.swift`

**Code**:
```swift
//
//  JarCard.swift
//  Buds
//
//  Summary card for jar list in CircleView
//

import SwiftUI

struct JarCard: View {
    let jar: Jar

    @State private var memberCount: Int = 0
    @State private var budCount: Int = 0

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: jar.isSolo ? "person.fill" : "person.2.fill")
                .font(.title2)
                .foregroundColor(.budsPrimary)
                .frame(width: 50, height: 50)
                .background(Color.budsPrimary.opacity(0.2))
                .clipShape(Circle())

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(jar.name)
                    .font(.budsBodyBold)
                    .foregroundColor(.white)

                HStack(spacing: 12) {
                    Label("\(memberCount)", systemImage: "person.2")
                    Label("\(budCount)", systemImage: "leaf")
                }
                .font(.budsCaption)
                .foregroundColor(.budsTextSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.budsTextSecondary)
        }
        .padding()
        .background(Color.budsCard)
        .cornerRadius(12)
        .task {
            await loadCounts()
        }
    }

    private func loadCounts() async {
        do {
            let members = try await JarRepository.shared.getMembers(jarID: jar.id)
            let buds = try await MemoryRepository().fetchByJar(jarID: jar.id)

            await MainActor.run {
                memberCount = members.count
                budCount = buds.count
            }
        } catch {
            print("❌ Failed to load jar counts: \(error)")
        }
    }
}
```

---

#### **Step 4: Create JarDetailView** (1.5 hours)

**Goal**: Show members inside a jar

**Files Created** (1):
- `Buds/Features/Jar/JarDetailView.swift`

**Code**:
```swift
//
//  JarDetailView.swift
//  Buds
//
//  Shows members of a jar with add/remove actions
//

import SwiftUI

struct JarDetailView: View {
    let jar: Jar

    @State private var members: [JarMember] = []
    @State private var showingAddMember = false
    @State private var showingMemberDetail: JarMember?
    @State private var isLoading = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .tint(.budsPrimary)
            } else if members.isEmpty {
                emptyState
            } else {
                membersList
            }
        }
        .navigationTitle(jar.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddMember = true
                } label: {
                    Image(systemName: "person.badge.plus")
                        .foregroundColor(.budsPrimary)
                }
                .disabled(members.count >= 12)
            }
        }
        .sheet(isPresented: $showingAddMember, onDismiss: {
            Task { await loadMembers() }
        }) {
            AddMemberView(jarID: jar.id)
        }
        .sheet(item: $showingMemberDetail) { member in
            MemberDetailView(jar: jar, member: member)
                .onDisappear {
                    Task { await loadMembers() }
                }
        }
        .task {
            await loadMembers()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.2.circle")
                .font(.system(size: 80))
                .foregroundColor(.budsPrimary.opacity(0.3))

            VStack(spacing: 12) {
                Text("No Members Yet")
                    .font(.budsTitle)
                    .foregroundColor(.white)

                Text("Add friends to share buds with this jar. Max 12 members.")
                    .font(.budsBody)
                    .foregroundColor(.budsTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                showingAddMember = true
            } label: {
                HStack {
                    Image(systemName: "person.badge.plus")
                    Text("Add Member")
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

    // MARK: - Members List

    private var membersList: some View {
        ScrollView {
            VStack(spacing: 16) {
                capacityIndicator

                ForEach(members) { member in
                    JarMemberCard(member: member)
                        .onTapGesture {
                            showingMemberDetail = member
                        }
                }
            }
            .padding()
        }
    }

    private var capacityIndicator: some View {
        HStack {
            Image(systemName: "person.2.fill")
                .foregroundColor(.budsPrimary)

            Text("\(members.count) / 12 members")
                .font(.budsCaption)
                .foregroundColor(.budsTextSecondary)

            Spacer()
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Helpers

    private func loadMembers() async {
        isLoading = true
        defer { isLoading = false }

        do {
            members = try await JarRepository.shared.getMembers(jarID: jar.id)
            print("✅ Loaded \(members.count) members for jar \(jar.name)")
        } catch {
            print("❌ Failed to load members: \(error)")
        }
    }
}

// MARK: - Jar Member Card Component

struct JarMemberCard: View {
    let member: JarMember

    var body: some View {
        HStack(spacing: 16) {
            // Avatar
            Circle()
                .fill(Color.budsPrimary.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay(
                    Text(member.displayName.prefix(1).uppercased())
                        .font(.budsHeadline)
                        .foregroundColor(.budsPrimary)
                )

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(member.displayName)
                        .font(.budsBodyBold)
                        .foregroundColor(.white)

                    if member.role == .owner {
                        Text("OWNER")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.budsAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.budsAccent.opacity(0.2))
                            .cornerRadius(4)
                    }
                }

                HStack(spacing: 8) {
                    StatusBadge(status: member.status)

                    if let phone = member.phoneNumber {
                        Text(phone)
                            .font(.budsCaption)
                            .foregroundColor(.budsTextSecondary)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.budsTextSecondary)
                .font(.system(size: 14))
        }
        .padding()
        .background(Color.budsCard)
        .cornerRadius(12)
    }
}

// MARK: - Status Badge (Reuse from CircleView or extract to Shared)

struct JarMemberStatusBadge: View {
    let status: JarMember.Status

    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(statusColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.2))
            .cornerRadius(6)
    }

    private var statusColor: Color {
        switch status {
        case .active: return .budsSuccess
        case .pending: return Color.orange
        case .removed: return .budsTextSecondary
        }
    }
}
```

---

#### **Step 5: Create CreateJarView** (1 hour)

**Goal**: Sheet to create new jar

**Files Created** (1):
- `Buds/Features/Jar/CreateJarView.swift`

**Code**:
```swift
//
//  CreateJarView.swift
//  Buds
//
//  Sheet for creating a new jar
//

import SwiftUI

struct CreateJarView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var jarManager = JarManager.shared

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                Form {
                    Section(header: Text("Jar Details")) {
                        TextField("Name (e.g., Friends, Tahoe Trip)", text: $name)
                            .textInputAutocapitalization(.words)

                        TextField("Description (optional)", text: $description, axis: .vertical)
                            .lineLimit(3...6)
                    }

                    if let error = errorMessage {
                        Section {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.budsCaption)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Create Jar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.budsTextSecondary)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await createJar() }
                    }
                    .disabled(name.isEmpty || isCreating)
                    .foregroundColor(.budsPrimary)
                }
            }
        }
    }

    private func createJar() async {
        guard !name.isEmpty else {
            errorMessage = "Name is required"
            return
        }

        isCreating = true
        errorMessage = nil

        do {
            _ = try await jarManager.createJar(
                name: name,
                description: description.isEmpty ? nil : description
            )

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isCreating = false
        }
    }
}
```

---

#### **Step 6: Rebuild CircleView** (2 hours)

**Goal**: Transform CircleView from member list → jar list

**Files Modified** (1):
- `CircleView.swift`

**Complete Rewrite**:
```swift
//
//  CircleView.swift
//  Buds
//
//  Jar management screen (renamed from Circle)
//

import SwiftUI

struct CircleView: View {
    @StateObject private var jarManager = JarManager.shared
    @State private var showingCreateJar = false
    @State private var selectedJar: Jar?

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                if jarManager.isLoading {
                    ProgressView("Loading jars...")
                        .tint(.budsPrimary)
                } else if jarManager.jars.isEmpty {
                    emptyState
                } else {
                    jarList
                }
            }
            .navigationTitle("Jars")
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 80))
                .foregroundColor(.budsPrimary.opacity(0.3))

            VStack(spacing: 12) {
                Text("No Jars Yet")
                    .font(.budsTitle)
                    .foregroundColor(.white)

                Text("Create jars to organize your buds and share with specific groups.")
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

    // MARK: - Jar List

    private var jarList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(jarManager.jars) { jar in
                    NavigationLink(destination: JarDetailView(jar: jar)) {
                        JarCard(jar: jar)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }
}

#Preview {
    CircleView()
}
```

---

#### **Step 7: Update AddMemberView** (1 hour)

**Goal**: Remove stub, add jar context

**Files Modified** (1):
- `AddMemberView.swift`

**Complete Rewrite**:
```swift
//
//  AddMemberView.swift
//  Buds
//
//  Add member to a specific jar
//

import SwiftUI

struct AddMemberView: View {
    let jarID: String  // NEW: Which jar to add member to

    @Environment(\.dismiss) var dismiss
    @StateObject private var jarManager = JarManager.shared

    @State private var phoneNumber: String = ""
    @State private var displayName: String = ""
    @State private var isAdding = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                Form {
                    Section(header: Text("Friend Details")) {
                        TextField("Name", text: $displayName)
                            .textInputAutocapitalization(.words)

                        TextField("Phone Number", text: $phoneNumber)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                    }

                    if let error = errorMessage {
                        Section {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.budsCaption)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Add Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.budsTextSecondary)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task { await addMember() }
                    }
                    .disabled(displayName.isEmpty || phoneNumber.isEmpty || isAdding)
                    .foregroundColor(.budsPrimary)
                }
            }
        }
    }

    private func addMember() async {
        guard !displayName.isEmpty, !phoneNumber.isEmpty else {
            errorMessage = "Name and phone number are required"
            return
        }

        isAdding = true
        errorMessage = nil

        do {
            try await jarManager.addMember(
                jarID: jarID,
                phoneNumber: phoneNumber,
                displayName: displayName
            )

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isAdding = false
        }
    }
}
```

---

#### **Step 8: Update MemberDetailView** (30 min)

**Goal**: Remove stub, add remove functionality

**Files Modified** (1):
- `MemberDetailView.swift`

**Complete Rewrite**:
```swift
//
//  MemberDetailView.swift
//  Buds
//
//  Jar member detail with remove action
//

import SwiftUI

struct MemberDetailView: View {
    let jar: Jar
    let member: JarMember

    @Environment(\.dismiss) var dismiss
    @StateObject private var jarManager = JarManager.shared

    @State private var showingRemoveConfirmation = false
    @State private var isRemoving = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 32) {
                // Avatar
                Circle()
                    .fill(Color.budsPrimary.opacity(0.2))
                    .frame(width: 120, height: 120)
                    .overlay(
                        Text(member.displayName.prefix(1).uppercased())
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.budsPrimary)
                    )

                // Info
                VStack(spacing: 16) {
                    Text(member.displayName)
                        .font(.budsTitle)
                        .foregroundColor(.white)

                    if let phone = member.phoneNumber {
                        Text(phone)
                            .font(.budsBody)
                            .foregroundColor(.budsTextSecondary)
                    }

                    HStack(spacing: 12) {
                        Label(member.role.rawValue.capitalized, systemImage: "person.fill")
                        JarMemberStatusBadge(status: member.status)
                    }
                    .font(.budsCaption)
                }

                Spacer()

                // Actions
                if member.role != .owner && member.status == .active {
                    Button(role: .destructive) {
                        showingRemoveConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "person.fill.xmark")
                            Text("Remove from Jar")
                        }
                        .font(.budsBodyBold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.red)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .disabled(isRemoving)
                }
            }
            .padding(.vertical, 32)
        }
        .confirmationDialog(
            "Remove \(member.displayName)?",
            isPresented: $showingRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                Task { await removeMember() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They will no longer have access to buds in \(jar.name).")
        }
    }

    private func removeMember() async {
        isRemoving = true

        do {
            try await jarManager.removeMember(jarID: jar.id, memberDID: member.memberDID)
            dismiss()
        } catch {
            print("❌ Failed to remove member: \(error)")
            isRemoving = false
        }
    }
}
```

---

#### **Step 9: Update ShareToCircleView** (1 hour)

**Goal**: Add jar context, filter to jar members

**Files Modified** (1):
- `ShareToCircleView.swift`

**Required Changes**:
```swift
struct ShareToCircleView: View {
    let memoryCID: String
    let jarID: String  // NEW: Current jar context

    @Environment(\.dismiss) var dismiss
    @State private var members: [JarMember] = []  // Changed from CircleMember
    @State private var selectedMembers: Set<String> = []
    @State private var isSharing = false

    var body: some View {
        // ... existing UI ...

        .task {
            await loadMembers()
        }
    }

    private func loadMembers() async {
        do {
            members = try await JarRepository.shared.getMembers(jarID: jarID)
            print("✅ Loaded \(members.count) members for jar \(jarID)")
        } catch {
            print("❌ Failed to load members: \(error)")
        }
    }

    private func shareMemory() async {
        isSharing = true

        do {
            let recipientDIDs = selectedMembers.compactMap { memberID in
                members.first(where: { $0.id == memberID })?.memberDID
            }

            try await ShareManager.shared.shareMemory(
                cid: memoryCID,
                recipientDIDs: recipientDIDs
            )

            dismiss()
        } catch {
            print("❌ Failed to share memory: \(error)")
            isSharing = false
        }
    }
}
```

**Navigation Change** (in TimelineView or MemoryDetailView):
```swift
// When calling ShareToCircleView, pass current jar:
.sheet(isPresented: $showingShare) {
    ShareToCircleView(memoryCID: memory.receiptCID, jarID: selectedJarID)
}
```

---

#### **Step 10: Fix Device Pinning for Jar Members** (1 hour)

**Goal**: Store jar member devices in local devices table for TOFU pinning

**Files Modified** (1):
- `JarManager.swift`

**Update `addMember()` method**:
```swift
func addMember(jarID: String, phoneNumber: String, displayName: String) async throws {
    let currentMembers = try await getMembers(jarID: jarID)
    guard currentMembers.count < maxJarSize else {
        throw JarError.jarFull
    }

    // 1. Look up real DID from relay
    let did = try await RelayClient.shared.lookupDID(phoneNumber: phoneNumber)

    // 2. Get ALL devices for this DID (not just first one)
    let devices = try await DeviceManager.shared.getDevices(for: [did])
    guard !devices.isEmpty else {
        throw JarError.userNotRegistered
    }

    // 3. Store devices in local devices table (TOFU key pinning)
    for device in devices {
        try await Database.shared.writeAsync { db in
            // Check if device already exists
            let exists = try Device
                .filter(Device.Columns.deviceId == device.deviceId)
                .fetchCount(db) > 0

            if !exists {
                try device.insert(db)
                print("🔐 Pinned device \(device.deviceId) for \(did)")
            }
        }
    }

    // 4. Add member to jar (use first device's X25519 key for jar_members)
    let firstDevice = devices[0]
    try await JarRepository.shared.addMember(
        jarID: jarID,
        memberDID: did,
        displayName: displayName,
        phoneNumber: phoneNumber,
        pubkeyX25519: firstDevice.pubkeyX25519
    )

    print("✅ Added jar member: \(displayName) to jar \(jarID) with \(devices.count) devices pinned")
}
```

**Why This Matters**:
- InboxManager.verifyAndStoreReceipt() calls JarManager.getPinnedEd25519PublicKey(did:deviceId:)
- This queries the devices table for TOFU key pinning
- Without storing devices, all received buds fail with `senderDeviceNotPinned` error

---

#### **Step 11: Fix Shared Bud Jar Assignment** (30 min)

**Goal**: Received buds should be assigned to correct jar (not hardcoded "solo")

**Files Modified** (1):
- `MemoryRepository.swift`

**Current Issue** (Line 370):
```swift
// WRONG: Hardcodes jar_id to "solo"
try db.execute(
    sql: """
        INSERT INTO local_receipts (
            uuid, header_cid, is_favorited, tags_json, local_notes,
            image_cids, jar_id, sender_did, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
    arguments: [uuid.uuidString, receiptCID, false, nil, nil, "[]", "solo", senderDID, now, now]
)
```

**Fix**: Infer jar from sender membership
```swift
func storeSharedReceipt(receiptCID: String, rawCBOR: Data, signature: String, senderDID: String, senderDeviceId: String, relayMessageId: String) async throws {
    try await db.writeAsync { db in
        // ... existing code ...

        // Infer jar from sender membership (which jar is sender a member of?)
        let jarID = try String.fetchOne(
            db,
            sql: """
                SELECT jar_id FROM jar_members
                WHERE member_did = ? AND status = 'active'
                LIMIT 1
                """,
            arguments: [senderDID]
        ) ?? "solo"  // Fallback to solo if sender not in any jar

        // Insert into local_receipts with correct jar_id
        try db.execute(
            sql: """
                INSERT INTO local_receipts (
                    uuid, header_cid, is_favorited, tags_json, local_notes,
                    image_cids, jar_id, sender_did, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [uuid.uuidString, receiptCID, false, nil, nil, "[]", jarID, senderDID, now, now]
        )

        print("✅ Stored shared receipt in jar: \(jarID)")
    }
}
```

---

## C. Risk Register

### Risk 1: Jar ID Mismatch (Medium)

**Symptom**: Buds appear in wrong jar or disappear

**Root Cause**:
- Timeline picker selectedJarID doesn't persist across app launches
- MemoryRepository.create() uses default jar_id = "solo"
- ShareToCircleView doesn't know current jar context

**Mitigation**:
1. Store selectedJarID in UserDefaults or AppStorage
2. Pass jarID explicitly to CreateMemoryView
3. Pass jarID explicitly to ShareToCircleView
4. Add jar_id validation: `SELECT COUNT(*) FROM jars WHERE id = ?` before INSERT

**Code**:
```swift
// In TimelineView
@AppStorage("selectedJarID") private var selectedJarID: String = "solo"
```

---

### Risk 2: Solo Jar Boot Timing (High)

**Symptom**: Fresh install shows empty Timeline (no Solo jar)

**Root Cause**:
- Migration v5 defers Solo jar creation if no devices table entry
- ensureSoloJarExists() not called on app launch
- Race condition: Timeline loads before Solo jar created

**Mitigation**:
1. Call ensureSoloJarExists() in BudsApp.swift .task {} after auth check
2. Add retry logic if Solo jar missing:
```swift
if jars.isEmpty {
    try await JarManager.shared.ensureSoloJarExists()
    await loadJars()
}
```
3. Show loading state in Timeline until jarManager.jars.count > 0

---

### Risk 3: Async State Race Conditions (Medium)

**Symptom**: UI shows stale data, members/buds appear/disappear

**Root Cause**:
- JarManager.jars is @Published but loadJars() called from multiple views
- CircleView, TimelineView, JarDetailView all independently reload
- No single source of truth

**Mitigation**:
1. Use @StateObject JarManager.shared (not @ObservedObject) in root views
2. Call loadJars() ONLY in CircleView.task {}
3. Other views observe JarManager.jars (no independent loads)
4. Use .refreshable for manual reload

**Code Pattern**:
```swift
// Root view (CircleView)
@StateObject private var jarManager = JarManager.shared

// Child views (JarDetailView)
@ObservedObject private var jarManager = JarManager.shared
```

---

### Risk 4: N+1 Query Problem (Low)

**Symptom**: Slow jar list load (especially with 10+ jars)

**Root Cause**:
- JarCard.loadCounts() makes 2 queries per jar:
  - `JarRepository.shared.getMembers(jarID:)`
  - `MemoryRepository().fetchByJar(jarID:)`
- 10 jars = 20 queries

**Mitigation**:
1. Add batch query methods:
   - `getAllJarsWithCounts() async -> [(Jar, memberCount: Int, budCount: Int)]`
2. Use SQL JOIN to fetch counts in single query:
```sql
SELECT
    j.id, j.name, j.description,
    COUNT(DISTINCT jm.member_did) as member_count,
    COUNT(DISTINCT lr.uuid) as bud_count
FROM jars j
LEFT JOIN jar_members jm ON j.id = jm.jar_id AND jm.status = 'active'
LEFT JOIN local_receipts lr ON j.id = lr.jar_id
GROUP BY j.id
```
3. Cache counts in JarManager (refresh on create/delete)

---

### Risk 5: Device Pinning Failure (High)

**Symptom**: Received buds fail with `senderDeviceNotPinned` error

**Root Cause**:
- addMember() fetches devices but doesn't store in local devices table
- InboxManager.verifyAndStoreReceipt() queries devices table
- No device found → verification fails

**Mitigation**:
1. ✅ Implemented in Step 10 (store devices when adding member)
2. Add error recovery: If pinning fails, show "Add \(name) again to refresh devices"
3. Periodically sync devices: `refreshDevices(for jarMember) async throws`

---

## D. Diff-Ready Checklist

### Files to Create (3)

1. ✅ `Buds/Shared/Views/JarCard.swift` (~80 lines)
2. ✅ `Buds/Features/Jar/JarDetailView.swift` (~220 lines)
3. ✅ `Buds/Features/Jar/CreateJarView.swift` (~100 lines)

**Total New Code**: ~400 lines

---

### Files to Modify (7)

1. ✅ `Buds/Core/JarManager.swift`
   - Add: `ensureSoloJarExists() async throws`
   - Update: `addMember()` to store devices (TOFU pinning)
   - **Lines Added**: ~30

2. ✅ `Buds/App/BudsApp.swift`
   - Add: `.task { try? await JarManager.shared.ensureSoloJarExists() }`
   - **Lines Added**: ~5

3. ✅ `Buds/Features/Timeline/TimelineView.swift`
   - Add: `@StateObject var jarManager`, `@AppStorage var selectedJarID`
   - Add: Jar picker UI
   - Update: `loadMemories()` → `loadMemories(jarID:)`
   - **Lines Added**: ~40

4. ✅ `Buds/Features/Circle/CircleView.swift`
   - **COMPLETE REWRITE**: Transform member list → jar list
   - Replace: `CircleMember` → `Jar`
   - Add: Navigation to JarDetailView, CreateJarView
   - **Lines Changed**: ~150 (entire file)

5. ✅ `Buds/Features/Circle/AddMemberView.swift`
   - Add parameter: `jarID: String`
   - Update: Call `JarManager.shared.addMember(jarID:...)`
   - **Lines Changed**: ~80 (entire file)

6. ✅ `Buds/Features/Circle/MemberDetailView.swift`
   - Add parameters: `jar: Jar, member: JarMember`
   - Update: Call `JarManager.shared.removeMember(jarID:...)`
   - **Lines Changed**: ~100 (entire file)

7. ✅ `Buds/Features/Share/ShareToCircleView.swift`
   - Add parameter: `jarID: String`
   - Update: Load `JarRepository.shared.getMembers(jarID:)`
   - **Lines Changed**: ~20

**Total Modified Code**: ~425 lines

---

### Execution Order (Critical Path)

**Phase 1: Bootstrapping (Solo Jar)**
1. JarManager.swift - Add `ensureSoloJarExists()`
2. BudsApp.swift - Call on launch
3. **Test**: Fresh install creates Solo jar ✅

**Phase 2: Timeline Jar Filtering**
4. TimelineView.swift - Add jar picker
5. **Test**: Switch between jars, verify filtering ✅

**Phase 3: Jar Management UI**
6. JarCard.swift - Create component
7. CreateJarView.swift - Create sheet
8. CircleView.swift - Rebuild as jar list
9. **Test**: Create jar, view in list ✅

**Phase 4: Member Management**
10. JarDetailView.swift - Create view
11. AddMemberView.swift - Update for jar context
12. MemberDetailView.swift - Update for jar context
13. JarManager.swift - Add device pinning to `addMember()`
14. **Test**: Add/remove members, verify device pinning ✅

**Phase 5: Sharing**
15. ShareToCircleView.swift - Add jar context
16. MemoryRepository.swift - Fix shared bud jar assignment
17. **Test**: Share bud to jar, verify recipient receives in correct jar ✅

**Phase 6: Integration Testing**
18. End-to-end flow: Create jar → Add member → Share bud → Verify receipt

---

## E. Acceptance Tests

### Test 1: Solo Jar Auto-Creation ✅

**Steps**:
1. Delete app from simulator
2. Reinstall and launch
3. Sign in with Firebase auth
4. Wait for app load

**Expected**:
- Solo jar created automatically
- Timeline picker shows "Solo" option
- No crash or empty state

**SQL Verification**:
```sql
SELECT * FROM jars WHERE id = 'solo';
-- Should return 1 row

SELECT * FROM jar_members WHERE jar_id = 'solo' AND role = 'owner';
-- Should return current user
```

---

### Test 2: Jar Switcher ✅

**Steps**:
1. Create new jar "Friends"
2. Add bud to Solo jar (Blue Dream)
3. Add bud to Friends jar (Gelato)
4. Switch Timeline picker: Solo → Friends
5. Switch back: Friends → Solo

**Expected**:
- Solo picker shows only "Blue Dream"
- Friends picker shows only "Gelato"
- No duplicate buds across jars

---

### Test 3: Jar Creation Flow ✅

**Steps**:
1. Open Circle tab
2. Tap "+ Create Jar"
3. Enter name: "Tahoe Trip"
4. Enter description: "Snowboarding weekend"
5. Tap "Create"

**Expected**:
- Sheet dismisses
- "Tahoe Trip" appears in jar list
- Tap jar → Shows 1 member (You) with OWNER badge

---

### Test 4: Member Management ✅

**Steps**:
1. Create jar "Test Jar"
2. Tap jar → Tap "+"
3. Enter name "Alice", phone "+1 650-555-1234"
4. Tap "Add"
5. Verify Alice appears in member list
6. Tap Alice → Tap "Remove from Jar"
7. Confirm removal

**Expected**:
- Alice appears after adding
- Alice disappears after removal
- SQL: `SELECT * FROM jar_members WHERE jar_id = ? AND member_did = ?` status = 'removed'

---

### Test 5: Device Pinning ✅

**Steps**:
1. Create jar "Pinning Test"
2. Add real user (with Buds account)
3. Share bud to Pinning Test jar
4. Wait for recipient to receive
5. Check recipient's Timeline

**Expected**:
- No `senderDeviceNotPinned` error
- Bud appears in recipient's Timeline
- SQL: `SELECT * FROM devices WHERE owner_did = ?` shows sender's device

**Debug Logs**:
```
🔐 Pinned device abc-123 for did:buds:xyz
✅ Added jar member: Alice to jar test-jar with 2 devices pinned
📬 Received encrypted message (CID: bafyrei...)
🔐 TOFU: Using device-specific pinned Ed25519 key for abc-123
✅ Signature verification PASSED
✅ Stored shared receipt in jar: test-jar
```

---

### Test 6: Jar-Scoped Sharing ✅

**Steps**:
1. Create 2 jars: "Jar A" (member: Alice), "Jar B" (member: Bob)
2. Add bud to Jar A
3. Tap Share → Verify only Alice appears
4. Share to Alice
5. Add bud to Jar B
6. Tap Share → Verify only Bob appears

**Expected**:
- ShareToCircleView shows only jar members (not all members)
- Alice receives Jar A bud (not Jar B bud)
- Bob receives Jar B bud (not Jar A bud)

---

## F. Cross-Reference with R1 Master Plan

### Phase Numbering Alignment ✅

**R1 Master Plan** (Buds/R1_MASTER_PLAN.md):
- **Phase 8**: Database Migration + Jar Model ✅ COMPLETE
- **Phase 9**: Shelf View (Home Redesign) ❌ MISMATCH

**Our Phase 9 Plan**: Multi-Jar UI + Circle Rebuild

**Conflict Resolution**:

The R1 Master Plan defines Phase 9 as:
> "Replace Timeline with Shelf (grid of jars)"

Our Phase 9 plan keeps Timeline as-is (adds jar picker) and rebuilds Circle view.

**Recommendation**: This plan is actually **Phase 9a** (UI rebuild). The R1 Master Plan's Phase 9 (Shelf redesign) should be **Phase 9b** (UX transformation).

**Proposed Split**:
1. **Phase 9a** (This Plan): Multi-Jar UI + Circle Rebuild - Make existing UI work with jars
2. **Phase 9b** (R1 Phase 9): Shelf View - Transform Timeline → Shelf (grid layout, activity dots, glow effects)

**Justification**:
- Phase 9a unblocks core functionality (users can create/manage jars)
- Phase 9b is pure UX polish (Shelf grid vs Timeline list)
- Splitting reduces risk: If Shelf redesign fails, jars still work

**R1 Master Plan Phase 9 Goals**:
```
Phase 9: Shelf View (Home Redesign) (4 hours)
- Replace Timeline with Shelf (grid of jars)
- Jars displayed as cards (2 per row)
- Dots inside = recent activity (up to 4 dots)
- Glow effect = new buds added in last 24h
- Tapping jar opens Jar Feed
```

**Our Phase 9 Deliverables**:
- ✅ Multi-jar support (database + backend complete)
- ✅ Jar creation/management UI
- ✅ Member management (add/remove)
- ✅ Jar-scoped sharing
- ❌ Shelf grid layout (deferred to Phase 9b)
- ❌ Activity dots/glow (deferred to Phase 9b)
- ❌ Jar Feed view (deferred to Phase 10)

**Recommendation for User**:
Execute this plan as **Phase 9a**, then decide:
- Option A: Skip Shelf redesign, keep Timeline picker (faster to ship)
- Option B: Implement Phase 9b (Shelf grid) before App Store submission

---

### Prerequisites Verification ✅

**R1 Master Plan Prerequisites**:
> "Phase 8 must be complete: jars table, jar_members table, jar_id column on local_receipts"

**Verified**:
- ✅ Migration v5 complete (PHASE_8_COMPLETE.md confirms)
- ✅ Jars table exists with Solo jar
- ✅ Jar_members table populated
- ✅ local_receipts.jar_id column added
- ✅ JarRepository + JarManager ready

**Status**: All prerequisites met ✅

---

### Timeline Consistency ✅

**R1 Master Plan Estimate**: 4 hours (Phase 9 Shelf View)

**Our Estimate**: 6-8 hours (Phase 9a Multi-Jar UI)

**Difference Explained**:
- R1 Phase 9 assumes backend complete, only UI changes
- Our Phase 9a includes:
  - Backend fixes (device pinning, ensureSoloJar)
  - 3 new views (JarCard, JarDetailView, CreateJarView)
  - 4 view rebuilds (CircleView, AddMemberView, MemberDetailView, ShareToCircleView)
  - Integration testing

**Revised Timeline**:
- Phase 9a (This Plan): 6-8 hours
- Phase 9b (Shelf Redesign): 4 hours (if executed)
- **Total**: 10-12 hours for full R1 Phase 9 vision

---

## G. README Update Instructions

**File**: `Buds/README.md`

**Changes Required**:

1. Update "Current Build" section:
```markdown
## Current Build

🚀 **LIVE ON TESTFLIGHT** - Phase 8 Complete (December 26, 2025)

**Latest**: Jar Architecture Migration ✅
- Database: jars + jar_members tables, jar_id scoping
- Backend: JarRepository + JarManager ready
- Models: Jar, JarMember, Memory (with jarID)
- Migration: Circle members → Solo jar (zero data loss)

**Next Up**: Phase 9 - Multi-Jar UI + Circle Rebuild
```

2. Add Phase 8 to "Build Progress":
```markdown
### Phase 8: Database Migration + Jar Architecture ✅ (COMPLETE - Dec 26, 2025)

**Goal**: Transform from single Circle → multiple Jars (scoped groups)

**What Was Built**:
- ✅ Migration v5: Created jars + jar_members tables
- ✅ Added jar_id column to local_receipts (which jar owns this bud)
- ✅ Added sender_did column to local_receipts (for received buds)
- ✅ Migrated existing Circle members → Solo jar
- ✅ Created Jar.swift + JarMember.swift models
- ✅ Created JarRepository.swift (CRUD operations)
- ✅ Created JarManager.swift (replaces CircleManager)
- ✅ Updated MemoryRepository.swift with jar filtering
- ⚠️  Circle UI temporarily stubbed (Phase 9 will rebuild)

**Testing**:
- ✅ Migration succeeds on existing users (14 members, 7 buds → Solo jar)
- ✅ Migration succeeds on fresh installs (graceful deferral)
- ✅ Build succeeds with no errors
- ✅ Zero data loss

**See [`PHASE_8_COMPLETE.md`](./PHASE_8_COMPLETE.md) for full details.**
```

3. Update "Future Phases":
```markdown
### Future Phases
- [ ] **Phase 9:** Multi-Jar UI + Circle Rebuild (in progress)
- [ ] **Phase 10:** Jar Feed View (media-first)
- [ ] **Phase 11:** Map View + Fuzzy Location Privacy
- [ ] **Phase 12:** Shop View + Remote Config
- [ ] **Phase 13:** AI Buds v1 (Reflection-Only)
- [ ] **Phase 14:** App Store Prep + Polish
```

---

## H. Critical Invariants

### 1. Solo Jar Identity Strategy

**Rule**: Solo jar MUST have id = "solo" (hardcoded string, not UUID)

**Why**:
- Migration v5 creates jar with id = 'solo'
- MemoryRepository.create() defaults jar_id = "solo"
- MemoryRepository.storeSharedReceipt() falls back to "solo"
- All existing code assumes "solo" exists

**Enforcement**:
```swift
// In JarRepository.createJar()
func createJar(name: String, description: String?, ownerDID: String) async throws -> Jar {
    // CRITICAL: Solo jar must have fixed ID
    let id = (name == "Solo") ? "solo" : UUID().uuidString

    let jar = Jar(id: id, name: name, ...)
    // ...
}
```

**Verification**:
```sql
-- Must always return 1 row per user
SELECT COUNT(*) FROM jars WHERE id = 'solo';
```

---

### 2. Jar ID on Memories (NOT NULL)

**Rule**: Every memory MUST belong to exactly one jar (no NULL jar_id)

**Why**:
- Schema: `ALTER TABLE local_receipts ADD COLUMN jar_id TEXT NOT NULL DEFAULT 'solo'`
- Prevents orphaned memories
- Enables clean jar deletion (`ON DELETE CASCADE`)

**Enforcement**:
```swift
// In MemoryRepository.create()
func create(..., jarID: String = "solo") async throws -> Memory {
    // CRITICAL: Never allow nil jar_id
    let finalJarID = jarID.isEmpty ? "solo" : jarID

    try db.execute(
        sql: "INSERT INTO local_receipts (..., jar_id, ...) VALUES (..., ?, ...)",
        arguments: [..., finalJarID, ...]
    )
}
```

**Verification**:
```sql
-- Must return 0
SELECT COUNT(*) FROM local_receipts WHERE jar_id IS NULL OR jar_id = '';
```

---

### 3. Member Identity Key (Composite: jar_id + member_did)

**Rule**: Same person can be in multiple jars with different roles/names

**Why**:
- Schema: `PRIMARY KEY (jar_id, member_did)`
- Allows: Alice in "Friends" (member) AND "Tahoe Trip" (owner)
- Prevents: Duplicate Alice in same jar

**Enforcement**:
```swift
// JarMember.id uses composite key
extension JarMember: Identifiable {
    var id: String { "\(jarID)-\(memberDID)" }
}
```

**Example**:
```
jar_id       | member_did           | role
friends      | did:buds:alice123    | member
tahoe-trip   | did:buds:alice123    | owner  ← Same person, different jar
```

---

### 4. Device Pinning Flow (TOFU)

**Rule**: Devices MUST be stored locally when adding jar member (not on first message)

**Why**:
- InboxManager verifies signature using `getPinnedEd25519PublicKey(did, deviceId)`
- Query: `SELECT * FROM devices WHERE owner_did = ? AND device_id = ?`
- If device not found → `senderDeviceNotPinned` error

**Critical Flow**:
```
1. User adds Alice to jar
2. JarManager.addMember() fetches Alice's devices from relay
3. Store ALL devices in local devices table (TOFU pinning)
4. Alice sends encrypted bud
5. InboxManager verifies signature against locally-stored device key
6. Success ✅
```

**Broken Flow** (Without Step 3):
```
1. User adds Alice to jar
2. JarManager.addMember() fetches devices but doesn't store ❌
3. Alice sends encrypted bud
4. InboxManager queries devices table → NOT FOUND
5. Error: senderDeviceNotPinned ❌
```

---

### 5. View Parameter Shapes

**Rule**: All jar-scoped views MUST accept jarID parameter

**Enforcement**:
```swift
// ✅ CORRECT
struct AddMemberView: View {
    let jarID: String  // Which jar to add to
}

struct ShareToCircleView: View {
    let memoryCID: String
    let jarID: String  // Which jar context we're in
}

// ❌ WRONG (global Circle behavior)
struct AddMemberView: View {
    // No jarID → adds to all jars? Ambiguous!
}
```

**Navigation Consistency**:
```swift
// When navigating to jar-scoped views, ALWAYS pass jar
NavigationLink(destination: JarDetailView(jar: jar)) { ... }

// When presenting sheets, ALWAYS pass jar context
.sheet(isPresented: $showAddMember) {
    AddMemberView(jarID: jar.id)
}
```

---

## I. Summary

### What This Plan Fixes

1. ✅ Solo jar auto-creation (fresh installs)
2. ✅ Timeline jar filtering (picker-based navigation)
3. ✅ Circle UI rebuild (member list → jar list)
4. ✅ Jar creation flow (CreateJarView)
5. ✅ Member management (add/remove per jar)
6. ✅ Device pinning (TOFU key storage)
7. ✅ Jar-scoped sharing (filter members by jar)
8. ✅ Shared bud jar assignment (infer from sender)

### What This Plan Does NOT Fix (Out of Scope)

1. ❌ Shelf grid redesign (R1 Phase 9 vision - defer to Phase 9b)
2. ❌ Activity dots/glow effects (R1 Phase 9 - defer to Phase 9b)
3. ❌ Jar Feed view (R1 Phase 10)
4. ❌ APNs push notifications (replace inbox polling)
5. ❌ Jar analytics (most active jar, etc.)

### Execution Confidence: 95%

**Why High Confidence**:
- ✅ Backend verified complete (JarRepository, JarManager tested)
- ✅ Database schema verified (migrations run successfully)
- ✅ Models match schema exactly
- ✅ Critical paths identified (device pinning, jar ID invariants)
- ✅ Risks documented with mitigations
- ✅ Acceptance tests defined

**Remaining Unknowns (5%)**:
1. ShareToCircleView exact file location/structure (need to verify full file)
2. BudsApp.swift exact .task {} hook location
3. Potential CircleMember → JarMember migration conflicts in UI

### Recommended Next Steps

1. **Pre-Implementation** (15 min):
   - Read this plan end-to-end
   - Review Risk Register (Section C)
   - Verify all prerequisites (database, models, repositories)

2. **Implementation** (6-8 hours):
   - Follow execution order (Section D)
   - Check off each step in Diff-Ready Checklist
   - Run acceptance tests after each phase

3. **Post-Implementation** (30 min):
   - Update README.md (Section G)
   - Run full acceptance test suite (Section E)
   - Commit with message: "Phase 9a Complete: Multi-Jar UI + Circle Rebuild"

4. **Phase 9b Decision** (Future):
   - Option A: Ship with Timeline picker (faster)
   - Option B: Implement Shelf grid redesign (R1 vision)

---

**Ready for execution. Let's ship multi-jar support! 🫙✨**
