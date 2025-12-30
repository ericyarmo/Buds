//
//  CreateJarView.swift
//  Buds
//
//  Sheet for creating a new jar
//

import SwiftUI

struct CreateJarView: View {
    let jarToEdit: Jar?  // Phase 10.1 Module 2.1: Edit mode support
    let onSave: (() -> Void)?  // Callback after save

    @Environment(\.dismiss) var dismiss
    @StateObject private var jarManager = JarManager.shared

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    private var isEditMode: Bool {
        jarToEdit != nil
    }

    init(jarToEdit: Jar? = nil, onSave: (() -> Void)? = nil) {
        self.jarToEdit = jarToEdit
        self.onSave = onSave
        _name = State(initialValue: jarToEdit?.name ?? "")
        _description = State(initialValue: jarToEdit?.description ?? "")
    }

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
            .navigationTitle(isEditMode ? "Edit Jar" : "Create Jar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.budsTextSecondary)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditMode ? "Save" : "Create") {
                        Task { await saveJar() }
                    }
                    .disabled(name.isEmpty || isCreating)
                    .foregroundColor(.budsPrimary)
                }
            }
        }
    }

    private func saveJar() async {
        guard !name.isEmpty else {
            errorMessage = "Name is required"
            return
        }

        isCreating = true
        errorMessage = nil

        do {
            if let jar = jarToEdit {
                // Edit mode: Update existing jar
                try await jarManager.updateJar(
                    jarID: jar.id,
                    name: name,
                    description: description.isEmpty ? nil : description
                )
            } else {
                // Create mode: Create new jar
                _ = try await jarManager.createJar(
                    name: name,
                    description: description.isEmpty ? nil : description
                )
            }

            onSave?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isCreating = false
        }
    }
}
