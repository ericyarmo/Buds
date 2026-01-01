//
//  SafetyNumberView.swift
//  Buds
//
//  Phase 10.3 Module 0.5: Safety Number Verification UI
//

import SwiftUI

struct SafetyNumberView: View {
    let member: JarMember
    let safetyNumber: String
    let deviceCount: Int

    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 32) {
                // Header
                VStack(spacing: 8) {
                    Text("Safety Number")
                        .font(.budsTitle)
                        .foregroundColor(.white)

                    Text("with \(member.displayName)")
                        .font(.budsBody)
                        .foregroundColor(.budsTextSecondary)
                }
                .padding(.top, 32)

                // Safety Number Display
                VStack(spacing: 16) {
                    Text(safetyNumber)
                        .font(.system(size: 24, weight: .medium, design: .monospaced))
                        .foregroundColor(.budsPrimary)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.budsPrimary.opacity(0.1))
                        )
                        .padding(.horizontal)

                    Text("Based on \(deviceCount) device\(deviceCount == 1 ? "" : "s")")
                        .font(.budsCaption)
                        .foregroundColor(.budsTextSecondary)
                }

                // Instructions
                VStack(spacing: 16) {
                    Text("How to Verify")
                        .font(.budsBodyBold)
                        .foregroundColor(.white)

                    Text("Compare this number with your friend's device. If they match, your connection is secure.")
                        .font(.budsBody)
                        .foregroundColor(.budsTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    // Warning
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.budsPrimary)

                        Text("This number will change if your friend adds a new device")
                            .font(.budsCaption)
                            .foregroundColor(.budsTextSecondary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.budsPrimary.opacity(0.1))
                    )
                    .padding(.horizontal)
                }

                Spacer()

                // Close Button
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.budsBodyBold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.budsPrimary)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
    }
}

#Preview {
    SafetyNumberView(
        member: JarMember(
            jarID: "test",
            memberDID: "did:phone:abc123",
            displayName: "Alice",
            phoneNumber: "+1 (555) 123-4567",
            avatarCID: nil,
            pubkeyX25519: "test",
            role: .member,
            status: .active,
            joinedAt: Date(),
            invitedAt: nil,
            removedAt: nil,
            createdAt: Date(),
            updatedAt: Date()
        ),
        safetyNumber: "12345 67890 12345 67890 12345 67890",
        deviceCount: 2
    )
}
