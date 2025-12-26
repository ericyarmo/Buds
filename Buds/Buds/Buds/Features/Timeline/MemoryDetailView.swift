//
//  MemoryDetailView.swift
//  Buds
//
//  Created by Eric Yarmolinsky on 12/17/25.
//
//  Full-screen memory detail view
//

import SwiftUI
import Combine

struct MemoryDetailView: View {
    let memory: Memory
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: MemoryDetailViewModel
    @State private var showingShareSheet = false

    init(memory: Memory) {
        self.memory = memory
        _viewModel = StateObject(wrappedValue: MemoryDetailViewModel(memory: memory))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.budsBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        // Image carousel
                        if !memory.imageData.isEmpty {
                            ImageCarousel(images: memory.imageData, maxHeight: 350, cornerRadius: 0)
                                .ignoresSafeArea(edges: .top)
                        }

                        VStack(alignment: .leading, spacing: BudsSpacing.l) {
                            // Header: Strain + Rating
                            headerSection
                                .padding(.top, memory.imageData.isEmpty ? BudsSpacing.l : BudsSpacing.m)

                            // Notes
                            if let notes = memory.notes, !notes.isEmpty {
                                notesSection(notes)
                            }

                            // Effects
                            if !memory.effects.isEmpty {
                                effectsSection
                            }

                            // Product details
                            productDetailsSection

                            // Additional details
                            additionalDetailsSection

                            // Actions
                            actionsSection
                        }
                        .budsPadding()
                    }
                }
            }
            .navigationTitle("Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.toggleFavorite()
                    } label: {
                        Image(systemName: viewModel.isFavorited ? "heart.fill" : "heart")
                            .foregroundColor(viewModel.isFavorited ? .budsError : .secondary)
                    }
                }
            }
            .alert("Delete Memory?", isPresented: $viewModel.showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        await viewModel.deleteMemory()
                        dismiss()
                    }
                }
            } message: {
                Text("This action cannot be undone.")
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareToCircleView(memoryCID: memory.receiptCID, jarID: memory.jarID)
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: BudsSpacing.s) {
            // Strain name + emoji
            HStack(alignment: .top, spacing: BudsSpacing.s) {
                Text(memory.productType.emoji)
                    .font(.system(size: 48))

                VStack(alignment: .leading, spacing: 4) {
                    Text(memory.strainName)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.budsTextPrimary)

                    HStack(spacing: 4) {
                        Text(memory.productType.displayName)
                            .font(.budsBody)
                            .foregroundColor(.budsTextPrimary)

                        if let method = memory.consumptionMethod {
                            Text("•")
                                .foregroundColor(.budsTextSecondary)
                            Text(method.displayName)
                                .font(.budsBody)
                                .foregroundColor(.budsTextPrimary)
                        }
                    }
                }

                Spacer()
            }

            // Rating stars (larger)
            HStack(spacing: 6) {
                ForEach(0..<5) { index in
                    Image(systemName: index < memory.rating ? "star.fill" : "star")
                        .foregroundColor(.budsWarning)
                        .font(.title3)
                }
            }

            // Timestamp
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundColor(.budsTextSecondary)
                Text(memory.relativeTimestamp)
                    .font(.budsBody)
                    .foregroundColor(.budsTextSecondary)
            }
        }
    }

    // MARK: - Product Details Section

    private var productDetailsSection: some View {
        VStack(alignment: .leading, spacing: BudsSpacing.s) {
            Text("Product Info")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.budsTextPrimary)

            VStack(spacing: BudsSpacing.s) {
                if let brand = memory.brand {
                    detailCard(icon: "tag.fill", label: "Brand", value: brand)
                }

                if let thc = memory.thcPercent {
                    detailCard(icon: "leaf.fill", label: "THC", value: String(format: "%.1f%%", thc))
                }

                if let cbd = memory.cbdPercent {
                    detailCard(icon: "leaf", label: "CBD", value: String(format: "%.1f%%", cbd))
                }

                if let amount = memory.amountGrams {
                    detailCard(icon: "scalemass", label: "Amount", value: String(format: "%.1fg", amount))
                }
            }
        }
    }

    private func detailCard(icon: String, label: String, value: String) -> some View {
        HStack(spacing: BudsSpacing.s) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.budsPrimary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.budsCaption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.budsBodyBold)
                    .foregroundColor(.budsTextPrimary)
            }

            Spacer()
        }
        .padding(BudsSpacing.s)
        .background(Color.budsSurface)
        .cornerRadius(BudsRadius.small)
    }

    // MARK: - Notes Section

    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: BudsSpacing.s) {
            HStack(spacing: 6) {
                Image(systemName: "quote.opening")
                    .font(.caption)
                    .foregroundColor(.budsPrimary)
                Text("Notes")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.budsTextPrimary)
            }

            Text(notes)
                .font(.budsBody)
                .foregroundColor(.budsTextPrimary)
                .padding(BudsSpacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.budsSurface)
                .cornerRadius(BudsRadius.small)
        }
    }

    // MARK: - Effects Section

    private var effectsSection: some View {
        VStack(alignment: .leading, spacing: BudsSpacing.s) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundColor(.budsPrimary)
                Text("Effects")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.budsTextPrimary)
            }

            FlowLayout(spacing: 8) {
                ForEach(memory.effects, id: \.self) { effect in
                    EffectTag(effect: effect)
                }
            }
        }
    }

    // MARK: - Additional Details Section

    private var additionalDetailsSection: some View {
        HStack(spacing: BudsSpacing.m) {
            // Location
            if memory.hasLocation {
                HStack(spacing: 6) {
                    Image(systemName: "location.fill")
                        .font(.caption)
                        .foregroundColor(.budsInfo)
                    Text(memory.locationName ?? "Unknown")
                        .font(.budsCaption)
                        .foregroundColor(.secondary)
                }
            }

            // Shared status
            HStack(spacing: 6) {
                Image(systemName: memory.isShared ? "person.2.fill" : "lock.fill")
                    .font(.caption)
                    .foregroundColor(memory.isShared ? .budsSuccess : .secondary)
                Text(memory.isShared ? "Shared" : "Private")
                    .font(.budsCaption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: BudsSpacing.s) {
            // Share button - moved to top
            if !memory.isShared {
                Button {
                    showingShareSheet = true
                } label: {
                    HStack {
                        Image(systemName: "person.2.fill")
                        Text("Share with Circle")
                    }
                    .font(.budsBodyBold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BudsSpacing.m)
                    .background(Color.budsPrimary)
                    .foregroundColor(.white)
                    .cornerRadius(BudsRadius.medium)
                    .shadow(color: Color.budsPrimary.opacity(0.3), radius: 8, y: 4)
                }
            }

            HStack(spacing: BudsSpacing.s) {
                // Edit button (placeholder)
                Button {
                    // TODO: Navigate to edit view
                    print("Edit tapped")
                } label: {
                    HStack {
                        Image(systemName: "pencil")
                        Text("Edit")
                    }
                    .font(.budsBody)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BudsSpacing.s)
                    .background(Color.budsSurface)
                    .foregroundColor(.budsPrimary)
                    .cornerRadius(BudsRadius.medium)
                }

                // Delete button
                Button {
                    viewModel.showDeleteConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete")
                    }
                    .font(.budsBody)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BudsSpacing.s)
                    .background(Color.budsSurface)
                    .foregroundColor(.budsError)
                    .cornerRadius(BudsRadius.medium)
                }
            }
        }
        .padding(.top, BudsSpacing.s)
    }
}

// MARK: - View Model

@MainActor
final class MemoryDetailViewModel: ObservableObject {
    @Published var isFavorited: Bool
    @Published var showDeleteConfirmation = false

    private let memory: Memory
    private let repository = MemoryRepository()

    init(memory: Memory) {
        self.memory = memory
        self.isFavorited = memory.isFavorited
    }

    func toggleFavorite() {
        Task {
            do {
                try await repository.toggleFavorite(id: memory.id)
                isFavorited.toggle()
            } catch {
                print("❌ Failed to toggle favorite: \(error)")
            }
        }
    }

    func deleteMemory() async {
        do {
            try await repository.delete(id: memory.id)
            print("✅ Memory deleted")
        } catch {
            print("❌ Failed to delete memory: \(error)")
        }
    }
}

// MARK: - Preview

#Preview {
    MemoryDetailView(memory: .preview)
}
