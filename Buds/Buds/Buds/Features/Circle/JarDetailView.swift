//
//  JarDetailView.swift
//  Buds
//
//  Shows buds/memories in a jar (Phase 10: converted from members view)
//

import SwiftUI

struct JarDetailView: View {
    let jar: Jar

    @State private var memoryItems: [MemoryListItem] = []
    @State private var members: [JarMember] = []
    @State private var showingAddMember = false
    @State private var showingMemberDetail: JarMember?
    @State private var selectedMemory: Memory?     // Phase 10.1 Module 1.1: For detail view
    @State private var isLoading = false
    @State private var showMembersSheet = false
    @State private var showingCreateMemory = false  // Phase 10.1: Create flow
    @State private var memoryToEnrich: UUID?       // Phase 10.1: Enrich flow
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                ProgressView("Loading buds...")
                    .tint(.budsPrimary)
            } else if memoryItems.isEmpty {
                emptyMemoriesState
            } else {
                memoriesList
            }
        }
        .navigationTitle(jar.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingCreateMemory = true
                    } label: {
                        Label("Add Bud", systemImage: "plus.circle")
                    }

                    // Only show Manage Members for shared jars (not solo)
                    if jar.id != "solo" {
                        Button {
                            showMembersSheet = true
                        } label: {
                            Label("Manage Members", systemImage: "person.2")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.budsPrimary)
                }
            }
        }
        .sheet(isPresented: $showMembersSheet) {
            NavigationStack {
                membersView
            }
        }
        // Phase 10.1: Create → Enrich flow
        .sheet(isPresented: $showingCreateMemory, onDismiss: {
            Task { await loadMemories() }
        }) {
            NavigationStack {
                CreateMemoryView(jarID: jar.id) { createdMemoryID in
                    // On save complete, show enrich view
                    memoryToEnrich = createdMemoryID
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { memoryToEnrich != nil },
            set: { if !$0 { memoryToEnrich = nil } }
        ), onDismiss: {
            Task { await loadMemories() }
        }) {
            if let memoryID = memoryToEnrich {
                NavigationStack {
                    EditMemoryView(memoryID: memoryID, isEnrichMode: true)
                }
            }
        }
        // Phase 10.1 Module 1.1: Memory detail view
        .sheet(item: $selectedMemory, onDismiss: {
            // Phase 10.1 Module 1.3: Reload list after detail view dismissal (in case of delete)
            Task { await loadMemories() }
        }) { memory in
            NavigationStack {
                MemoryDetailView(memory: memory)
            }
        }
        .task {
            await loadMemories()
            await loadMembers()
        }
    }

    // MARK: - Memories Empty State (Step 1.4)

    private var emptyMemoriesState: some View {
        VStack(spacing: 24) {
            Image(systemName: "leaf")
                .font(.system(size: 80))
                .foregroundColor(.budsPrimary.opacity(0.3))

            VStack(spacing: 12) {
                Text("No buds yet")
                    .font(.budsTitle)
                    .foregroundColor(.white)

                Text("Start logging your cannabis experiences")
                    .font(.budsBody)
                    .foregroundColor(.budsTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                showingCreateMemory = true
            } label: {
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

    // MARK: - Memories List (Phase 10 Step 2.4)

    private var memoriesList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(memoryItems) { item in
                    MemoryListCard(item: item) {
                        // Phase 10.1 Module 1.1: Fetch full memory and show detail view
                        await loadMemoryDetail(id: item.id)
                    }
                }
            }
            .padding()
        }
        .refreshable {
            await loadMemories()
        }
    }

    // MARK: - Members View (in sheet)

    private var membersView: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if members.isEmpty {
                emptyMembersState
            } else {
                membersList
            }
        }
        .navigationTitle("Members")
        .navigationBarTitleDisplayMode(.inline)
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
    }

    private var emptyMembersState: some View {
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

    private func loadMemories() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let repository = MemoryRepository()
            memoryItems = try await repository.fetchLightweightList(jarID: jar.id, limit: 50)
            print("✅ Loaded \(memoryItems.count) memories for jar \(jar.name)")
        } catch {
            print("❌ Failed to load memories: \(error)")
        }
    }

    private func loadMembers() async {
        do {
            members = try await JarRepository.shared.getMembers(jarID: jar.id)
            print("✅ Loaded \(members.count) members for jar \(jar.name)")
        } catch {
            print("❌ Failed to load members: \(error)")
        }
    }

    private func loadMemoryDetail(id: UUID) async {
        do {
            let repository = MemoryRepository()
            let memory = try await repository.fetch(id: id)
            print("✅ Loaded memory detail: \(memory!.strainName)")
            await MainActor.run {
                selectedMemory = memory
            }
        } catch {
            print("❌ Failed to load memory detail: \(error)")
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
                        .foregroundColor(.budsTextPrimary)

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
                    JarMemberStatusBadge(status: member.status)

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

// MARK: - Status Badge

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
