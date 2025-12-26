//
//  ShareToCircleView.swift
//  Buds
//
//  Phase 6: Share memory to Circle with E2EE
//

import SwiftUI

struct ShareToCircleView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var shareManager = ShareManager.shared

    let memoryCID: String

    @State private var selectedDIDs: Set<String> = []
    @State private var error: String?
    @State private var members: [CircleMember] = []  // TODO Phase 9: Update to use JarMembers

    private var allSelected: Bool {
        !members.isEmpty && selectedDIDs.count == members.count
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header section
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.budsPrimary)

                    Text("Share to Circle")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)

                    Text("End-to-end encrypted. Only selected members can see this.")
                        .font(.budsBody)
                        .foregroundColor(.budsTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .padding(.top, 40)
                .padding(.bottom, 24)

                // Member list
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(members, id: \.id) { member in
                            MemberRow(
                                member: member,
                                isSelected: selectedDIDs.contains(member.did)
                            ) {
                                if selectedDIDs.contains(member.did) {
                                    selectedDIDs.remove(member.did)
                                } else {
                                    selectedDIDs.insert(member.did)
                                }
                            }
                        }
                    }
                    .padding()
                }

                // Error message
                if let error = error {
                    Text(error)
                        .font(.budsCaption)
                        .foregroundColor(.budsError)
                        .padding()
                }

                // Share button
                Button(action: share) {
                    if shareManager.isSharing {
                        ProgressView().tint(.white)
                    } else {
                        Text("Share (\(selectedDIDs.count))")
                            .font(.budsBodyBold)
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(selectedDIDs.isEmpty ? Color.budsTextSecondary : Color.budsPrimary)
                .cornerRadius(12)
                .disabled(selectedDIDs.isEmpty || shareManager.isSharing)
                .padding()
            }
            .background(Color.black)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.budsPrimary)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(allSelected ? "Deselect All" : "Select All") {
                        toggleSelectAll()
                    }
                    .foregroundColor(.budsPrimary)
                }
            }
        }
    }

    private func share() {
        error = nil
        Task {
            do {
                try await shareManager.shareMemory(memoryCID: memoryCID, with: Array(selectedDIDs))
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func toggleSelectAll() {
        if allSelected {
            // Deselect all
            selectedDIDs.removeAll()
        } else {
            // Select all
            selectedDIDs = Set(members.map(\.did))
        }
    }
}

// MARK: - Member Row

struct MemberRow: View {
    let member: CircleMember
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Avatar circle
            Circle()
                .fill(Color.budsPrimary.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay(
                    Text(member.displayName.prefix(1).uppercased())
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.budsPrimary)
                )

            // Name
            Text(member.displayName)
                .font(.budsBodyBold)
                .foregroundColor(.white)

            Spacer()

            // Selection indicator
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .budsPrimary : .budsTextSecondary)
                .font(.title2)
        }
        .padding()
        .background(Color.budsSurface)
        .cornerRadius(12)
        .onTapGesture { onToggle() }
    }
}

// MARK: - Preview

#Preview {
    ShareToCircleView(memoryCID: "bafyreitest123")
}
