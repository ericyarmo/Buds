//
//  CreateMemoryView.swift
//  Buds
//
//  Form to create a new cannabis memory
//

import SwiftUI
import Combine

struct CreateMemoryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = CreateMemoryViewModel()

    var body: some View {
        NavigationStack {
            Form {
                // Photos (3 max)
                Section {
                    PhotoPicker(selectedImages: $viewModel.selectedImages)
                } header: {
                    Text("Photos (3 max)")
                        .font(.budsCaption)
                }

                // Strain Name
                Section {
                    TextField("Strain name", text: $viewModel.strainName)
                        .font(.budsBody)
                } header: {
                    Text("Strain")
                        .font(.budsCaption)
                }

                // Product Type
                Section {
                    Picker("Type", selection: $viewModel.productType) {
                        ForEach(ProductType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .tint(.budsPrimary)
                } header: {
                    Text("Type")
                }

                // Rating
                Section {
                    HStack {
                        ForEach(1...5, id: \.self) { star in
                            Button {
                                viewModel.rating = star
                            } label: {
                                Image(systemName: star <= viewModel.rating ? "star.fill" : "star")
                                    .foregroundColor(star <= viewModel.rating ? .budsWarning : .gray)
                                    .font(.title2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                } header: {
                    Text("Rating")
                }

                // Notes
                Section {
                    ZStack(alignment: .topLeading) {
                        if viewModel.notes.isEmpty {
                            Text("How did it make you feel? What did you do?")
                                .foregroundColor(.secondary)
                                .font(.budsBody)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                        }
                        TextEditor(text: $viewModel.notes)
                            .frame(minHeight: 100)
                            .font(.budsBody)
                            .scrollContentBackground(.hidden)
                            .onChange(of: viewModel.notes) { _, newValue in
                                if newValue.count > 500 {
                                    viewModel.notes = String(newValue.prefix(500))
                                }
                            }
                    }

                    HStack {
                        Spacer()
                        Text("\(viewModel.notes.count)/500")
                            .font(.budsCaption)
                            .foregroundColor(viewModel.notes.count > 450 ? .budsWarning : .secondary)
                    }
                } header: {
                    Text("Notes")
                }

                // Effects
                Section {
                    FlowLayout(spacing: 8) {
                        ForEach(EffectOption.all, id: \.self) { effect in
                            effectChip(effect)
                        }
                    }
                } header: {
                    Text("Effects")
                }

                // Product Details (Optional)
                Section {
                    TextField("Brand (optional)", text: $viewModel.brand)
                    TextField("THC%", value: $viewModel.thcPercent, format: .number)
                        .keyboardType(.decimalPad)
                    TextField("CBD%", value: $viewModel.cbdPercent, format: .number)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Product Details (optional)")
                }

                // Consumption Method
                Section {
                    Picker("Method", selection: $viewModel.consumptionMethod) {
                        Text("Not specified").tag(nil as ConsumptionMethod?)
                        ForEach(ConsumptionMethod.allCases, id: \.self) { method in
                            Text(method.displayName).tag(method as ConsumptionMethod?)
                        }
                    }
                    .tint(.budsPrimary)
                } header: {
                    Text("Method")
                }
            }
            .navigationTitle("New Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await viewModel.save()
                            dismiss()
                        }
                    }
                    .font(.budsBodyBold)
                    .disabled(!viewModel.isValid)
                }
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") {}
            } message: {
                Text(viewModel.errorMessage ?? "Unknown error")
            }
        }
    }

    // MARK: - Effect Chip

    private func effectChip(_ effect: EffectOption) -> some View {
        Button {
            viewModel.toggleEffect(effect.rawValue)
        } label: {
            Text(effect.rawValue)
                .font(.budsTag)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    viewModel.selectedEffects.contains(effect.rawValue)
                        ? effect.color.opacity(0.3)
                        : Color.gray.opacity(0.1)
                )
                .foregroundColor(
                    viewModel.selectedEffects.contains(effect.rawValue)
                        ? effect.color
                        : .secondary
                )
                .cornerRadius(BudsRadius.pill)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - View Model

@MainActor
final class CreateMemoryViewModel: ObservableObject {
    @Published var selectedImages: [Data] = []
    @Published var strainName = ""
    @Published var productType: ProductType = .flower
    @Published var rating = 3
    @Published var notes = ""
    @Published var brand = ""
    @Published var thcPercent: Double? = nil
    @Published var cbdPercent: Double? = nil
    @Published var selectedEffects: [String] = []
    @Published var consumptionMethod: ConsumptionMethod? = nil

    @Published var showError = false
    @Published var errorMessage: String?

    private let repository = MemoryRepository()

    var isValid: Bool {
        !strainName.isEmpty && rating > 0
    }

    func toggleEffect(_ effect: String) {
        if selectedEffects.contains(effect) {
            selectedEffects.removeAll { $0 == effect }
        } else {
            selectedEffects.append(effect)
        }
    }

    func save() async {
        do {
            let memory = try await repository.create(
                strainName: strainName,
                productType: productType,
                rating: rating,
                notes: notes.isEmpty ? nil : notes,
                brand: brand.isEmpty ? nil : brand,
                thcPercent: thcPercent,
                cbdPercent: cbdPercent,
                amountGrams: nil,
                effects: selectedEffects,
                consumptionMethod: consumptionMethod
            )

            // Add images if any were selected
            if !selectedImages.isEmpty {
                try await repository.addImages(to: memory.id, images: selectedImages)
            }

            print("✅ Memory created successfully with \(selectedImages.count) images")
        } catch {
            print("❌ Failed to create memory: \(error)")
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Effect Options

enum EffectOption: String, CaseIterable {
    case relaxed, creative, energized, happy, focused, sleepy, anxious, euphoric

    var color: Color {
        switch self {
        case .relaxed: return .effectRelaxed
        case .creative: return .effectCreative
        case .energized: return .effectEnergized
        case .happy: return .effectHappy
        case .focused: return .effectFocused
        case .sleepy: return .effectSleepy
        case .anxious: return .effectAnxious
        case .euphoric: return .budsWarning
        }
    }

    static var all: [EffectOption] {
        allCases
    }
}

// MARK: - Flow Layout (for effect chips)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var frames: [CGRect] = []
        var size: CGSize = .zero

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth, currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                frames.append(CGRect(x: currentX, y: currentY, width: size.width, height: size.height))

                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}

// MARK: - Product Type Extension

extension ProductType: CaseIterable {
    static var allCases: [ProductType] {
        [.flower, .edible, .concentrate, .vape, .tincture, .topical, .other]
    }
}

extension ConsumptionMethod: CaseIterable {
    static var allCases: [ConsumptionMethod] {
        [.joint, .bong, .pipe, .vape, .edible, .dab, .tincture, .topical]
    }
}

// MARK: - Preview

#Preview {
    CreateMemoryView()
}
