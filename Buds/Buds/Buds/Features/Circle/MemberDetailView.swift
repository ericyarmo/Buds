//
//  MemberDetailView.swift
//  Buds
//
//  Circle member detail screen
//

import SwiftUI

struct MemberDetailView: View {
    @Environment(\.dismiss) var dismiss
    // TODO Phase 9: Update to use JarManager

    let member: CircleMember
    @State private var showingRemoveAlert = false
    @State private var isEditingName = false
    @State private var editedName: String

    init(member: CircleMember) {
        self.member = member
        _editedName = State(initialValue: member.displayName)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Avatar
                    Circle()
                        .fill(Color.budsPrimary.opacity(0.2))
                        .frame(width: 100, height: 100)
                        .overlay(
                            Text(member.displayName.prefix(1).uppercased())
                                .font(.system(size: 50))
                                .foregroundColor(.budsPrimary)
                        )
                        .padding(.top, 40)

                    // Name
                    if isEditingName {
                        HStack {
                            TextField("Display Name", text: $editedName)
                                .font(.budsTitle)
                                .foregroundStyle(.black)
                                .multilineTextAlignment(.center)

                            Button("Save") {
                                saveName()
                            }
                            .font(.budsBodyBold)
                            .foregroundColor(.budsPrimary)
                        }
                        .padding(.horizontal, 20)
                    } else {
                        HStack(spacing: 12) {
                            Text(editedName)
                                .font(.budsTitle)
                                .foregroundColor(.white)

                            Button(action: {
                                isEditingName = true
                            }) {
                                Image(systemName: "pencil")
                                    .foregroundColor(.budsPrimary)
                            }
                        }
                    }

                    // Status
                    StatusBadge(status: member.status)

                    // Info section
                    VStack(spacing: 16) {
                        if let phone = member.phoneNumber {
                            InfoRow(label: "Phone", value: phone, icon: "phone.fill")
                        }

                        InfoRow(
                            label: "DID",
                            value: member.did,
                            icon: "key.fill"
                        )

                        if let joinedAt = member.joinedAt {
                            InfoRow(
                                label: "Joined",
                                value: joinedAt.formatted(date: .abbreviated, time: .omitted),
                                icon: "calendar"
                            )
                        }
                    }
                    .padding()
                    .background(Color.budsCard)
                    .cornerRadius(12)
                    .padding(.horizontal, 20)

                    Spacer()

                    // Remove button
                    Button(action: {
                        showingRemoveAlert = true
                    }) {
                        HStack {
                            Image(systemName: "person.badge.minus")
                            Text("Remove from Circle")
                        }
                        .font(.budsBodyBold)
                        .foregroundColor(.budsDanger)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.budsDanger.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .background(Color.black)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Remove from Circle?", isPresented: $showingRemoveAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Remove", role: .destructive) {
                    removeMember()
                }
            } message: {
                Text("This person will no longer be able to see memories you share with your Circle.")
            }
        }
    }

    // MARK: - Actions

    private func saveName() {
        // TODO Phase 9: Update to use JarManager
        print("⚠️ Circle features will be updated in Phase 9")
        isEditingName = false
    }

    private func removeMember() {
        // TODO Phase 9: Update to use JarManager
        print("⚠️ Circle features will be updated in Phase 9")
        dismiss()
    }
}

// MARK: - Info Row Component

struct InfoRow: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.budsPrimary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.budsCaption)
                    .foregroundColor(.budsTextSecondary)

                Text(value)
                    .font(.budsBody)
                    .foregroundColor(.white)
                    .lineLimit(1)
            }

            Spacer()
        }
    }
}

#Preview {
    MemberDetailView(member: CircleMember(
        id: "1",
        did: "did:buds:test",
        displayName: "Alex",
        phoneNumber: "+1 (555) 123-4567",
        avatarCID: nil,
        pubkeyX25519: "test",
        status: .active,
        joinedAt: Date(),
        invitedAt: Date(),
        removedAt: nil,
        createdAt: Date(),
        updatedAt: Date()
    ))
}
