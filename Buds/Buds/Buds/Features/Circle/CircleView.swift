//
//  CircleView.swift
//  Buds
//
//  Circle (friends) management screen
//

import SwiftUI

struct CircleView: View {
    @StateObject private var circleManager = CircleManager.shared
    @State private var showingAddMember = false
    @State private var showingMemberDetail: CircleMember?

    var body: some View {
        NavigationView {
            ZStack {
                if circleManager.members.isEmpty {
                    emptyState
                } else {
                    membersList
                }
            }
            .navigationTitle("Circle")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingAddMember = true
                    }) {
                        Image(systemName: "person.badge.plus")
                            .foregroundColor(.budsPrimary)
                    }
                    .disabled(circleManager.members.count >= 12)
                }
            }
            .sheet(isPresented: $showingAddMember) {
                AddMemberView()
            }
            .sheet(item: $showingMemberDetail) { member in
                MemberDetailView(member: member)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.2.circle")
                .font(.system(size: 80))
                .foregroundColor(.budsPrimary.opacity(0.3))

            VStack(spacing: 12) {
                Text("Your Circle is Empty")
                    .font(.budsTitle)
                    .foregroundColor(.white)

                Text("Add friends to share your cannabis memories privately. Max 12 members.")
                    .font(.budsBody)
                    .foregroundColor(.budsTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button(action: {
                showingAddMember = true
            }) {
                HStack {
                    Image(systemName: "person.badge.plus")
                    Text("Add Friend")
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
                // Circle capacity indicator
                capacityIndicator

                // Member cards
                ForEach(circleManager.members, id: \.id) { member in
                    MemberCard(member: member)
                        .onTapGesture {
                            showingMemberDetail = member
                        }
                }
            }
            .padding()
        }
        .background(Color.black)
    }

    private var capacityIndicator: some View {
        HStack {
            Image(systemName: "person.2.fill")
                .foregroundColor(.budsPrimary)

            Text("\(circleManager.members.count) / 12 members")
                .font(.budsCaption)
                .foregroundColor(.budsTextSecondary)

            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Member Card Component

struct MemberCard: View {
    let member: CircleMember

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
                Text(member.displayName)
                    .font(.budsBodyBold)
                    .foregroundColor(.black)

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

// MARK: - Status Badge Component

struct StatusBadge: View {
    let status: CircleMember.CircleStatus

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

#Preview {
    CircleView()
}
