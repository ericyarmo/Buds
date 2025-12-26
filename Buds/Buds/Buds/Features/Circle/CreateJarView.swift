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
