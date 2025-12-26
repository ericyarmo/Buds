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
