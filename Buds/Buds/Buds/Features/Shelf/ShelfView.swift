//
//  ShelfView.swift
//  Buds
//
//  Phase 9b: Shelf grid view (replaces Timeline list)
//

import SwiftUI

// Identifiable wrapper for jar ID to avoid @State timing issues with sheets
struct JarSelection: Identifiable {
    let id: String
    var jarID: String { id }
}

struct ShelfView: View {
    @ObservedObject var jarManager = JarManager.shared  // Only parent observes
    @State private var showingCreateJar = false
    @State private var showJarPicker = false           // Phase 10.1: Show jar picker
    @State private var jarSelection: JarSelection?     // Phase 10.1: Jar selected for create (drives sheet)
    @State private var memoryToEnrich: UUID?           // Phase 10.1: Memory to enrich
    @State private var jarToDelete: Jar?
    @State private var showDeleteConfirmation = false
    @State private var deleteError: String?
    @State private var showDeleteError = false
    @State private var toast: Toast?  // Phase 10 Step 5: Toast notifications
    @State private var jarToEdit: Jar?  // Phase 10.1 Module 2.1: Edit jar
    @State private var showingEditJar = false

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if jarManager.isLoading {
                    ProgressView("Loading jars...")
                        .tint(.budsPrimary)
                } else if jarManager.jars.isEmpty {
                    emptyState
                } else {
                    jarGrid
                }
            }
            .navigationTitle("Shelf")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreateJar = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.budsPrimary)
                    }
                }
            }
            .sheet(isPresented: $showingCreateJar, onDismiss: {
                Task { await jarManager.loadJars() }  // Reload after create
            }) {
                CreateJarView()
            }
            // Phase 10.1 Module 2.1: Edit jar sheet
            .sheet(isPresented: $showingEditJar, onDismiss: {
                Task {
                    await jarManager.loadJars()
                    // Show success toast
                    await MainActor.run {
                        toast = Toast(message: "Jar updated", style: .success)
                    }
                }
                jarToEdit = nil
            }) {
                if let jar = jarToEdit {
                    CreateJarView(jarToEdit: jar)
                }
            }
            // Phase 10.1: Jar picker sheet
            .sheet(isPresented: $showJarPicker) {
                NavigationStack {
                    JarPickerView { jarID in
                        print("🔍 [DEBUG] Jar selected: \(jarID)")
                        showJarPicker = false
                        print("🔍 [DEBUG] showJarPicker = false, creating JarSelection")
                        // Use .sheet(item:) to capture jar at presentation time
                        jarSelection = JarSelection(id: jarID)
                        print("🔍 [DEBUG] jarSelection set: \(jarSelection?.jarID ?? "nil")")
                    }
                }
            }
            // Phase 10.1: Create → Enrich flow (using .sheet(item:) to capture jar ID)
            .sheet(item: $jarSelection) { selection in
                let _ = print("🔍 [DEBUG] Create memory sheet presented with jarID: \(selection.jarID)")
                NavigationStack {
                    CreateMemoryView(jarID: selection.jarID) { createdMemoryID in
                        print("🔍 [DEBUG] Memory created: \(createdMemoryID), showing enrich view")
                        // On save complete, show enrich view
                        memoryToEnrich = createdMemoryID
                    }
                }
            }
            .sheet(isPresented: Binding(
                get: { memoryToEnrich != nil },
                set: { if !$0 { memoryToEnrich = nil } }
            )) {
                if let memoryID = memoryToEnrich {
                    NavigationStack {
                        EditMemoryView(memoryID: memoryID, isEnrichMode: true)
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    // Phase 10 Step 4: Haptic feedback on FAB tap
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showJarPicker = true  // Phase 10.1: Show jar picker instead
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 56))
                        .foregroundColor(.budsPrimary)
                        .background(Circle().fill(Color.black).padding(4))
                        .shadow(radius: 4)
                }
                .padding(20)
            }
            .task {
                await jarManager.loadJars()
            }
            .alert("Delete \(jarToDelete?.name ?? "Jar")?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    jarToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let jar = jarToDelete {
                        Task {
                            await deleteJar(jar)
                        }
                    }
                }
            } message: {
                if let jar = jarToDelete {
                    let budCount = jarManager.jarStats[jar.id]?.totalBuds ?? 0
                    if budCount > 0 {
                        Text("All \(budCount) buds in this jar will be moved to Solo. Members will be removed.")
                    } else {
                        Text("This jar is empty. Members will be removed.")
                    }
                }
            }
            .alert("Error", isPresented: $showDeleteError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(deleteError ?? "Failed to delete jar")
            }
            .toast($toast)  // Phase 10 Step 5: Toast modifier
        }
    }

    // MARK: - Jar Grid

    private var jarGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(jarManager.jars) { jar in
                    NavigationLink(destination: JarDetailView(jar: jar)) {
                        ShelfJarCard(jar: jar, stats: jarManager.jarStats[jar.id])  // Pass stats down
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        // Only allow deletion for non-Solo jars
                        let isSolo = jar.name.trimmingCharacters(in: .whitespaces).lowercased() == "solo"

                        // Phase 10.1 Module 2.1: Edit jar (all jars including Solo)
                        Button {
                            jarToEdit = jar
                            showingEditJar = true
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Label("Edit Jar", systemImage: "pencil")
                        }

                        if !isSolo {
                            Button(role: .destructive) {
                                jarToDelete = jar
                                showDeleteConfirmation = true
                                // Phase 10 Step 4: Haptic feedback for destructive action
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            } label: {
                                Label("Delete Jar", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .refreshable {
            // Phase 10 Step 4: Pull-to-refresh
            await jarManager.refreshGlobal()
            // Haptic feedback on refresh complete
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 80))
                .foregroundColor(.budsPrimary.opacity(0.3))

            VStack(spacing: 12) {
                Text("No Jars Yet")
                    .font(.budsTitle)
                    .foregroundColor(.white)

                Text("Create jars to organize your buds")
                    .font(.budsBody)
                    .foregroundColor(.budsTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                showingCreateJar = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle")
                    Text("Create Jar")
                }
                .font(.budsBodyBold)
                .foregroundColor(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .background(Color.budsPrimary)
                .cornerRadius(12)
            }
        }
        .padding()
    }

    // MARK: - Delete Jar

    private func deleteJar(_ jar: Jar) async {
        do {
            try await jarManager.deleteJar(id: jar.id)
            jarToDelete = nil

            // Phase 10 Step 5: Toast notification on success
            await MainActor.run {
                withAnimation {
                    toast = Toast(message: "Jar deleted", style: .success)
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }

            print("✅ Jar deleted and UI updated")
        } catch let error as JarError {
            deleteError = error.localizedDescription
            showDeleteError = true
            jarToDelete = nil
        } catch {
            deleteError = "An unexpected error occurred"
            showDeleteError = true
            jarToDelete = nil
        }
    }
}

// MARK: - Preview

struct ShelfView_Previews: PreviewProvider {
    static var previews: some View {
        ShelfView()
    }
}
