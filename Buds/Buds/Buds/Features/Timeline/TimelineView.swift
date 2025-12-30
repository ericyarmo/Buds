//
//  TimelineView.swift
//  Buds
//
//  Main timeline showing user's cannabis memories
//

import SwiftUI
import Combine

struct TimelineView: View {
    @StateObject private var viewModel = TimelineViewModel()
    @StateObject private var jarManager = JarManager.shared
    @AppStorage("selectedJarID") private var selectedJarID: String = "solo"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Jar Picker
                if !jarManager.jars.isEmpty {
                    jarPicker
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color.black)
                }

                // Main Content
                ZStack {
                    Color.black.ignoresSafeArea()

                    if viewModel.isLoading {
                        ProgressView("Loading memories...")
                            .tint(.budsPrimary)
                    } else if viewModel.memories.isEmpty {
                        emptyState
                    } else {
                        memoryList
                    }
                }
            }
            .navigationTitle("Timeline")
            .toolbarColorScheme(.dark, for: .navigationBar)
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
            .sheet(isPresented: $viewModel.showCreateSheet, onDismiss: {
                // Reload memories and jar stats when create sheet is dismissed
                Task {
                    await viewModel.loadMemories(jarID: selectedJarID)
                    await jarManager.loadJars()  // Phase 9b: Reload stats
                }
            }) {
                NavigationStack {
                    CreateMemoryView(jarID: selectedJarID)
                }
            }
            .sheet(item: $viewModel.selectedMemory) { memory in
                NavigationStack {
                    MemoryDetailView(memory: memory)
                        .onDisappear {
                            // Reload memories and jar stats when detail view is dismissed
                            Task {
                                await viewModel.loadMemories(jarID: selectedJarID)
                                await jarManager.loadJars()  // Phase 9b: Reload stats (in case of delete)
                            }
                        }
                }
            }
            .task {
                await viewModel.loadMemories(jarID: selectedJarID)
            }
            .refreshable {
                await viewModel.loadMemories(jarID: selectedJarID)
            }
            .onChange(of: selectedJarID) { oldValue, newValue in
                Task {
                    await viewModel.loadMemories(jarID: newValue)
                }
            }
            .onAppear {
                viewModel.startInboxPolling()
            }
            .onDisappear {
                viewModel.stopInboxPolling()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: BudsSpacing.l) {
            Text("No memories yet")
                .font(.budsHeadline)

            Text("Tap + to create your first cannabis memory")
                .font(.budsBody)
                .foregroundColor(.black.opacity(0.7))
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

    // MARK: - Jar Picker

    private var jarPicker: some View {
        HStack {
            Image(systemName: "square.stack.3d.up.fill")
                .foregroundColor(.budsPrimary)
                .font(.caption)

            Picker("Jar", selection: $selectedJarID) {
                ForEach(jarManager.jars) { jar in
                    Text(jar.name).tag(jar.id)
                }
            }
            .pickerStyle(.menu)
            .tint(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.budsCard)
        .cornerRadius(10)
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
    private var inboxObserver: AnyCancellable?

    init() {
        // Listen for inbox updates (new shared memories)
        // Note: inbox updates reload with default jar (solo)
        // User can switch jars manually via picker to see shared buds in other jars
        inboxObserver = NotificationCenter.default
            .publisher(for: .inboxUpdated)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.loadMemories() // Uses default jar="solo"
                }
            }
    }

    func loadMemories(jarID: String = "solo") async {
        isLoading = true
        defer { isLoading = false }

        do {
            memories = try await repository.fetchByJar(jarID: jarID)
            print("✅ Loaded \(memories.count) memories for jar \(jarID)")
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

    func startInboxPolling() {
        Task {
            await InboxManager.shared.startForegroundPolling()
            print("📬 Started inbox polling")
        }
    }

    func stopInboxPolling() {
        Task {
            await InboxManager.shared.stopForegroundPolling()
            print("📭 Stopped inbox polling")
        }
    }
}

// MARK: - Preview

#Preview {
    TimelineView()
}
