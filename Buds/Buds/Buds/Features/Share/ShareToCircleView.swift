//
//  ShareToCircleView.swift
//  Buds
//
//  Phase 9: Share memory to jar members with E2EE
//

import SwiftUI

struct ShareToCircleView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var shareManager = ShareManager.shared

    let memoryCID: String
    let jarID: String  // NEW: Current jar context

    @State private var selectedDIDs: Set<String> = []
    @State private var error: String?
    @State private var members: [JarMember] = []  // Updated to JarMember
    @State private var isLoading = false

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

                    Text("Share to Jar")
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

                // Loading or member list
                if isLoading {
                    ProgressView()
                        .tint(.budsPrimary)
                        .padding()
                } else if members.isEmpty {
                    VStack(spacing: 12) {
                        Text("No members in this jar")
                            .font(.budsBody)
                            .foregroundColor(.budsTextSecondary)
                        Text("Add members to share with them")
                            .font(.budsCaption)
                            .foregroundColor(.budsTextSecondary)
                    }
                    .padding()
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(members) { member in
                                JarMemberRow(
                                    member: member,
                                    isSelected: selectedDIDs.contains(member.memberDID)
                                ) {
                                    if selectedDIDs.contains(member.memberDID) {
                                        selectedDIDs.remove(member.memberDID)
                                    } else {
                                        selectedDIDs.insert(member.memberDID)
                                    }
                                }
                            }
                        }
                        .padding()
                    }
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
                    .disabled(members.isEmpty)
                }
            }
            .task {
                await loadMembers()
            }
        }
    }

    private func loadMembers() async {
        isLoading = true
        defer { isLoading = false }

        do {
            members = try await JarRepository.shared.getMembers(jarID: jarID)
            print("✅ Loaded \(members.count) members for jar \(jarID)")
        } catch {
            self.error = "Failed to load members: \(error.localizedDescription)"
            print("❌ Failed to load members: \(error)")
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
            selectedDIDs = Set(members.map(\.memberDID))
        }
    }
}

// MARK: - Jar Member Row

struct JarMemberRow: View {
    let member: JarMember
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
