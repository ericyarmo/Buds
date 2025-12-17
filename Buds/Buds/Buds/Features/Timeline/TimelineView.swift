//
//  TimelineView.swift
//  Buds
//
//  Main timeline showing user's cannabis memories
//

import SwiftUI

struct TimelineView: View {
    @StateObject private var viewModel = TimelineViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.budsBackground.ignoresSafeArea()

                if viewModel.isLoading {
                    ProgressView("Loading memories...")
                        .tint(.budsPrimary)
                } else if viewModel.memories.isEmpty {
                    emptyState
                } else {
                    memoryList
                }
            }
            .navigationTitle("Timeline")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.showCreateSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.budsAccent)
                    }
                }
            }
            .sheet(isPresented: $viewModel.showCreateSheet) {
                CreateMemoryView()
            }
            .task {
                await viewModel.loadMemories()
            }
            .refreshable {
                await viewModel.loadMemories()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: BudsSpacing.l) {
            Text("🌿")
                .font(.system(size: 60))

            Text("No memories yet")
                .font(.budsHeadline)

            Text("Tap + to create your first cannabis memory")
                .font(.budsBody)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BudsSpacing.xl)

            Button {
                viewModel.showCreateSheet = true
            } label: {
                Text("Create Memory")
                    .font(.budsBodyBold)
                    .foregroundColor(.white)
                    .frame(maxWidth: 200)
                    .padding(.vertical, 12)
                    .background(Color.budsAccent)
                    .cornerRadius(BudsRadius.medium)
            }
        }
    }

    // MARK: - Memory List

    private var memoryList: some View {
        ScrollView {
            LazyVStack(spacing: BudsSpacing.m) {
                ForEach(viewModel.memories) { memory in
                    MemoryCard(memory: memory) {
                        viewModel.selectedMemory = memory
                    } onToggleFavorite: {
                        Task {
                            await viewModel.toggleFavorite(memory)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, BudsSpacing.m)
        }
    }
}

// MARK: - View Model

@MainActor
final class TimelineViewModel: ObservableObject {
    @Published var memories: [Memory] = []
    @Published var isLoading = false
    @Published var showCreateSheet = false
    @Published var selectedMemory: Memory?

    private let repository = MemoryRepository()

    func loadMemories() async {
        isLoading = true
        defer { isLoading = false }

        do {
            memories = try await repository.fetchAll()
            print("✅ Loaded \(memories.count) memories")
        } catch {
            print("❌ Failed to load memories: \(error)")
        }
    }

    func toggleFavorite(_ memory: Memory) async {
        do {
            try await repository.toggleFavorite(id: memory.id)
            await loadMemories()  // Reload to get updated state
        } catch {
            print("❌ Failed to toggle favorite: \(error)")
        }
    }
}

// MARK: - Preview

#Preview {
    TimelineView()
}
