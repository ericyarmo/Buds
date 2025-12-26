//
//  MemberDetailView.swift
//  Buds
//
//  Jar member detail with remove action (Phase 9)
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
