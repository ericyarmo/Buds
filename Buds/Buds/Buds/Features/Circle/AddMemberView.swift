//
//  AddMemberView.swift
//  Buds
//
//  Add friend to Circle
//

import SwiftUI

struct AddMemberView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var circleManager = CircleManager.shared

    @State private var phoneNumber = ""
    @State private var displayName = ""
    @State private var isAdding = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 60))
                            .foregroundColor(.budsPrimary)

                        Text("Add Friend to Circle")
                            .font(.budsTitle)
                            .foregroundColor(.white)

                        Text("They'll be able to see memories you share with your Circle.")
                            .font(.budsBody)
                            .foregroundColor(.budsTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    .padding(.top, 40)

                    // Form
                    VStack(spacing: 20) {
                        // Display name
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Display Name")
                                .font(.budsCaption)
                                .foregroundColor(.budsTextSecondary)
                                .textCase(.uppercase)

                            TextField("e.g., Alex", text: $displayName)
                                .font(.budsBody)
                                .foregroundStyle(.black)
                                .padding()
                                .background(Color.budsCard)
                                .cornerRadius(12)
                        }

                        // Phone number
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Phone Number")
                                .font(.budsCaption)
                                .foregroundColor(.budsTextSecondary)
                                .textCase(.uppercase)

                            HStack {
                                Text("+1")
                                    .font(.budsBody)
                                    .foregroundColor(.budsTextSecondary)

                                TextField("(555) 123-4567", text: $phoneNumber)
                                    .font(.budsBody)
                                    .foregroundStyle(.black)
                                    .keyboardType(.phonePad)
                            }
                            .padding()
                            .background(Color.budsCard)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 20)

                    // Error message
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(.budsCaption)
                            .foregroundColor(.budsDanger)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }

                    Spacer()

                    // Add button
                    Button(action: addMember) {
                        if isAdding {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Text("Add to Circle")
                                .font(.budsBodyBold)
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(isFormValid ? Color.budsPrimary : Color.budsTextSecondary)
                    .cornerRadius(12)
                    .disabled(!isFormValid || isAdding)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .background(Color.black)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var isFormValid: Bool {
        !displayName.isEmpty && !phoneNumber.isEmpty
    }

    // MARK: - Actions

    private func addMember() {
        errorMessage = nil
        isAdding = true

        Task {
            do {
                try await circleManager.addMember(
                    phoneNumber: "+1\(phoneNumber.filter { $0.isNumber })",
                    displayName: displayName
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isAdding = false
        }
    }
}

#Preview {
    AddMemberView()
}
