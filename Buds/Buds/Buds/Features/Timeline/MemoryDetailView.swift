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
    @State private var showingEditView = false  // Phase 10.1 Module 1.1: Edit flow
    @State private var toast: Toast?
    @State private var showingMoveSheet = false  // Phase 10.1 Module 2.3: Move to jar

    init(memory: Memory) {
        self.memory = memory
        _viewModel = StateObject(wrappedValue: MemoryDetailViewModel(memory: memory))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Image carousel (full width, no padding)
                    if !memory.imageData.isEmpty {
                        ImageCarousel(images: memory.imageData, maxHeight: 350, cornerRadius: 0)
                    }

                    // All content below with consistent padding
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

                        // Additional details
                        additionalDetailsSection

                        // Reactions (Phase 10.1 Module 1.4)
                        reactionsSection

                        // Actions
                        actionsSection
                    }
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
            }
            .alert("Delete Bud?", isPresented: $viewModel.showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        let success = await viewModel.deleteMemory()
                        if success {
                            // Show success feedback before dismissing
                            await MainActor.run {
                                toast = Toast(message: "Bud deleted", style: .success)
                            }
                            // Small delay to show toast before dismiss
                            try? await Task.sleep(nanoseconds: 500_000_000)
                        }
                        dismiss()
                    }
                }
        } message: {
            Text("Are you sure you want to delete \"\(memory.strainName)\"? This action cannot be undone.")
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareToCircleView(memoryCID: memory.receiptCID, jarID: memory.jarID)
        }
        .sheet(isPresented: $showingEditView, onDismiss: {
            // Show success toast after edit
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                toast = Toast(message: "Bud updated! 🌿", style: .success)
            }
        }) {
            NavigationStack {
                EditMemoryView(memoryID: memory.id, isEnrichMode: false)
            }
        }
        // Phase 10.1 Module 2.3: Move to jar sheet
        .sheet(isPresented: $showingMoveSheet) {
            MoveMemoryView(
                memoryID: memory.id,
                currentJarID: memory.jarID
            ) { newJarID in
                Task {
                    await viewModel.moveToJar(newJarID: newJarID)
                    toast = Toast(message: "Bud moved", style: .success)
                    dismiss()  // Return to previous view
                }
            }
        }
        .toast($toast)
        .task {
            // Phase 10.1 Module 1.4: Load reactions when view appears
            await viewModel.loadReactions()
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

    // MARK: - Reactions Section (Phase 10.1 Module 1.4)

    private var reactionsSection: some View {
        VStack(alignment: .leading, spacing: BudsSpacing.m) {
            // Show existing reactions
            if !viewModel.reactionSummaries.isEmpty {
                VStack(alignment: .leading, spacing: BudsSpacing.s) {
                    Text("Reactions")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.budsTextSecondary)

                    ReactionSummaryView(summaries: viewModel.reactionSummaries)
                }
            }

            // Reaction picker
            ReactionPicker(currentReaction: viewModel.currentUserReaction) { type in
                Task {
                    await viewModel.toggleReaction(type)
                }
            }
        }
        .padding(.top, BudsSpacing.m)
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
                // Edit button
                Button {
                    showingEditView = true
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

                // Move button (Phase 10.1 Module 2.3)
                Button {
                    showingMoveSheet = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.right.square")
                        Text("Move")
                    }
                    .font(.budsBody)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BudsSpacing.s)
                    .background(Color.budsSurface)
                    .foregroundColor(.budsTextPrimary)
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
    @Published var reactionSummaries: [ReactionSummary] = []  // Phase 10.1 Module 1.4
    @Published var currentUserReaction: ReactionType?         // Phase 10.1 Module 1.4

    private let memory: Memory
    private let repository = MemoryRepository()
    private let reactionRepository = ReactionRepository()     // Phase 10.1 Module 1.4

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

    func deleteMemory() async -> Bool {
        do {
            try await repository.delete(id: memory.id)
            print("✅ Memory deleted: \(memory.strainName)")
            return true
        } catch {
            print("❌ Failed to delete memory: \(error)")
            return false
        }
    }

    // MARK: - Reactions (Phase 10.1 Module 1.4)

    func loadReactions() async {
        do {
            // Load summaries
            let summaries = try await reactionRepository.fetchReactionSummaries(for: memory.id)
            await MainActor.run {
                self.reactionSummaries = summaries
            }

            // Load current user's reaction using DID
            let userDID = try await IdentityManager.shared.getDID()

            if let userReaction = try await reactionRepository.fetchUserReaction(for: memory.id, senderDID: userDID) {
                await MainActor.run {
                    self.currentUserReaction = userReaction.type
                }
            } else {
                await MainActor.run {
                    self.currentUserReaction = nil
                }
            }
        } catch {
            print("❌ Failed to load reactions: \(error)")
        }
    }

    func toggleReaction(_ type: ReactionType) async {
        do {
            // Get user's DID
            let userDID = try await IdentityManager.shared.getDID()

            try await reactionRepository.toggleReaction(
                memoryID: memory.id,
                senderDID: userDID,
                type: type,
                jarID: memory.jarID
            )

            // Reload reactions
            await loadReactions()
        } catch {
            print("❌ Failed to toggle reaction: \(error)")
        }
    }

    // MARK: - Move (Phase 10.1 Module 2.3)

    func moveToJar(newJarID: String) async {
        do {
            try await repository.moveToJar(memoryID: memory.id, newJarID: newJarID)
            print("✅ Moved bud to jar: \(newJarID)")
        } catch {
            print("❌ Failed to move bud: \(error)")
        }
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

// MARK: - Preview

#Preview {
    MemoryDetailView(memory: .preview)
}
