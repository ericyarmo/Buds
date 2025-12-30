//
//  CreateMemoryView.swift
//  Buds
//
//  Phase 10.1 Module 1.0: Simplified create flow (name + type only)
//  After save, auto-navigates to enrich view
//

import SwiftUI
import Combine

struct CreateMemoryView: View {
    let jarID: String
    let onSaveComplete: ((UUID) -> Void)?  // Callback with created memory ID

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CreateMemoryViewModel

    init(jarID: String = "solo", onSaveComplete: ((UUID) -> Void)? = nil) {
        self.jarID = jarID
        self.onSaveComplete = onSaveComplete
        _viewModel = StateObject(wrappedValue: CreateMemoryViewModel(jarID: jarID))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Strain Name (Required)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Strain Name *")
                            .font(.budsCaption)
                            .foregroundColor(.budsTextSecondary)

                        TextField("Blue Dream", text: $viewModel.strainName)
                            .font(.budsBody)
                            .padding()
                            .background(Color.budsCard)
                            .cornerRadius(12)
                            .foregroundColor(.budsText)
                    }

                    // Product Type (Optional)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Type")
                            .font(.budsCaption)
                            .foregroundColor(.budsTextSecondary)

                        Picker("Type", selection: $viewModel.productType) {
                            ForEach(ProductType.allCases, id: \.self) { type in
                                HStack {
                                    Text(type.icon)
                                    Text(type.displayName)
                                }
                                .tag(type)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.budsPrimary)
                        .padding()
                        .background(Color.budsCard)
                        .cornerRadius(12)
                    }

                    Spacer()

                    // Helper text
                    Text("Add photos, rating, and notes on the next screen")
                        .font(.budsCaption)
                        .foregroundColor(.budsTextSecondary)
                        .multilineTextAlignment(.center)

                    // Continue button
                    Button {
                        Task {
                            await viewModel.save(onComplete: onSaveComplete)
                            dismiss()
                        }
                    } label: {
                        Text("Continue to Details")
                            .font(.budsBodyBold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(viewModel.isValid ? Color.budsPrimary : Color.gray)
                            .cornerRadius(12)
                    }
                    .disabled(!viewModel.isValid)
                }
            }
        }
        .navigationTitle("New Bud")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
                .foregroundColor(.budsTextSecondary)
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
    }
}

// MARK: - View Model

@MainActor
final class CreateMemoryViewModel: ObservableObject {
    @Published var strainName = ""
    @Published var productType: ProductType = .flower

    @Published var showError = false
    @Published var errorMessage: String?

    private let repository = MemoryRepository()
    private let jarID: String

    init(jarID: String = "solo") {
        self.jarID = jarID
    }

    var isValid: Bool {
        !strainName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func save(onComplete: ((UUID) -> Void)? = nil) async {
        guard isValid else { return }

        do {
            print("💾 CreateMemory (Simplified): Creating minimal bud '\(strainName)'")

            // Create minimal receipt with defaults
            let memory = try await repository.create(
                strainName: strainName.trimmingCharacters(in: .whitespacesAndNewlines),
                productType: productType,
                rating: 0,              // Default: no rating yet
                notes: nil,             // No notes
                brand: nil,             // No brand
                thcPercent: nil,        // No THC
                cbdPercent: nil,        // No CBD
                amountGrams: nil,       // No amount
                effects: [],            // No effects
                consumptionMethod: nil, // No method
                locationCID: nil,       // No location
                jarID: jarID
            )

            print("✅ Minimal bud created: \(memory.id)")
            print("   Name: \(strainName)")
            print("   Type: \(productType.displayName)")
            print("   → Callback will navigate to enrich view")

            // Trigger callback to show enrich view
            onComplete?(memory.id)

            // Refresh jar list (lightweight)
            await JarManager.shared.refreshJar(jarID)

        } catch {
            print("❌ Failed to create minimal bud: \(error)")
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Product Type Extension

extension ProductType {
    var icon: String {
        switch self {
        case .flower: return "🌿"
        case .edible: return "🍪"
        case .concentrate: return "💎"
        case .vape: return "💨"
        case .tincture: return "💧"
        case .topical: return "🧴"
        case .other: return "📦"
        }
    }
}

extension ProductType: CaseIterable {
    static var allCases: [ProductType] {
        [.flower, .edible, .concentrate, .vape, .tincture, .topical, .other]
    }
}

// MARK: - Preview

#Preview {
    CreateMemoryView()
}
