//
//  EditMemoryView.swift
//  Buds
//
//  Phase 10.1 Module 1.2: Full edit/enrich form
//  Pre-fills existing data, allows updating all fields
//

import SwiftUI
import PhotosUI
import Combine

struct EditMemoryView: View {
    let memoryID: UUID
    let isEnrichMode: Bool  // True when called from create flow, false for regular edit

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: EditMemoryViewModel
    @State private var showingCamera = false

    init(memoryID: UUID, isEnrichMode: Bool) {
        self.memoryID = memoryID
        self.isEnrichMode = isEnrichMode
        _viewModel = StateObject(wrappedValue: EditMemoryViewModel(memoryID: memoryID))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.isLoading {
                ProgressView("Loading...")
                    .tint(.budsPrimary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Images Section
                        imagesSection

                        // Basic Info Section
                        basicInfoSection

                        // Rating Section
                        ratingSection

                        // Effects Section
                        effectsSection

                        // Notes Section
                        notesSection

                        // Save Button
                        saveButton
                    }
                }
            }
        }
        .navigationTitle(isEnrichMode ? "Enrich Bud" : "Edit Bud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isEnrichMode ? "Skip" : "Cancel") {
                        if isEnrichMode {
                            viewModel.showSkipToast()
                        }
                        dismiss()
                    }
                    .foregroundColor(.budsTextSecondary)
                }
            }
            .toast($viewModel.toast)
            .sheet(isPresented: $showingCamera) {
                CameraView(
                    onCapture: { imageData in
                        if let uiImage = UIImage(data: imageData) {
                            viewModel.addCameraImage(uiImage)
                        }
                        showingCamera = false
                    },
                    onCancel: {
                        showingCamera = false
                    }
                )
            }
        .task {
            await viewModel.loadMemory()
        }
    }

    // MARK: - Images Section

    private var imagesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Photos")
                .font(.budsHeadline)
                .foregroundColor(.budsText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Existing images
                    ForEach(Array(viewModel.images.enumerated()), id: \.offset) { index, image in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .cornerRadius(8)
                                .clipped()

                            // Remove button
                            Button {
                                viewModel.removeImage(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white)
                                    .background(Circle().fill(Color.black.opacity(0.6)))
                            }
                            .padding(4)
                        }
                    }

                    // Add photo buttons (if < 3 images)
                    if viewModel.images.count < 3 {
                        // Camera button
                        Button {
                            showingCamera = true
                        } label: {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5]))
                                .foregroundColor(.budsPrimary)
                                .frame(width: 100, height: 100)
                                .overlay(
                                    VStack(spacing: 4) {
                                        Image(systemName: "camera")
                                            .font(.title2)
                                        Text("Camera")
                                            .font(.caption)
                                    }
                                    .foregroundColor(.budsPrimary)
                                )
                        }

                        // Photo library button
                        PhotosPicker(selection: $viewModel.selectedPhotosItem,
                                     maxSelectionCount: 3 - viewModel.images.count,
                                     matching: .images) {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5]))
                                .foregroundColor(.budsPrimary)
                                .frame(width: 100, height: 100)
                                .overlay(
                                    VStack(spacing: 4) {
                                        Image(systemName: "photo")
                                            .font(.title2)
                                        Text("Library")
                                            .font(.caption)
                                    }
                                    .foregroundColor(.budsPrimary)
                                )
                        }
                        .onChange(of: viewModel.selectedPhotosItem) { _, _ in
                            Task { await viewModel.loadSelectedPhotos() }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Basic Info Section

    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Basic Info")
                .font(.budsHeadline)
                .foregroundColor(.budsText)

            // Strain Name
            TextField("Strain Name", text: $viewModel.strainName)
                .font(.budsBody)
                .foregroundColor(.white)
                .padding()
                .background(Color.budsCard)
                .cornerRadius(12)

            // Product Type
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
    }

    // MARK: - Rating Section

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rating")
                .font(.budsHeadline)
                .foregroundColor(.budsText)

            HStack(spacing: 16) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        viewModel.rating = star
                    } label: {
                        Image(systemName: star <= viewModel.rating ? "star.fill" : "star")
                            .font(.title)
                            .foregroundColor(star <= viewModel.rating ? .budsPrimary : .gray)
                    }
                }

                Spacer()

                if viewModel.rating > 0 {
                    Button("Clear") {
                        viewModel.rating = 0
                    }
                    .font(.budsCaption)
                    .foregroundColor(.budsTextSecondary)
                }
            }
            .padding()
            .background(Color.budsCard)
            .cornerRadius(12)
        }
    }

    // MARK: - Effects Section

    private var effectsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Effects")
                .font(.budsHeadline)
                .foregroundColor(.budsText)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(CommonEffects.all, id: \.self) { effect in
                    Button {
                        viewModel.toggleEffect(effect)
                    } label: {
                        HStack {
                            Image(systemName: viewModel.effects.contains(effect) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(viewModel.effects.contains(effect) ? .budsPrimary : .gray)
                            Text(effect.capitalized)
                                .font(.budsBody)
                                .foregroundColor(.budsText)
                            Spacer()
                        }
                        .padding()
                        .background(viewModel.effects.contains(effect) ? Color.budsPrimary.opacity(0.1) : Color.budsCard)
                        .cornerRadius(8)
                    }
                }
            }
        }
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes")
                .font(.budsHeadline)
                .foregroundColor(.budsText)

            ZStack(alignment: .topLeading) {
                if viewModel.notes.isEmpty {
                    Text("Add your thoughts, flavor notes, or session details...")
                        .font(.budsBody)
                        .foregroundColor(.budsTextSecondary)
                        .padding(12)
                }

                TextEditor(text: $viewModel.notes)
                    .font(.budsBody)
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120)
                    .padding(8)
            }
            .background(Color.budsCard)
            .cornerRadius(12)
        }
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button {
            Task {
                let success = await viewModel.saveChanges()
                if success {
                    dismiss()
                }
            }
        } label: {
            Text(isEnrichMode ? "Save & Complete" : "Save Changes")
                .font(.budsBodyBold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(viewModel.hasChanges ? Color.budsPrimary : Color.gray)
                .cornerRadius(12)
        }
        .disabled(!viewModel.hasChanges || viewModel.isSaving)
    }
}

// MARK: - Common Effects List

enum CommonEffects {
    static let all = [
        "relaxed",
        "happy",
        "euphoric",
        "uplifted",
        "creative",
        "focused",
        "energetic",
        "sleepy",
        "hungry",
        "talkative",
        "giggly",
        "aroused"
    ]
}

// MARK: - Preview

#Preview {
    EditMemoryView(memoryID: UUID(), isEnrichMode: true)
}
