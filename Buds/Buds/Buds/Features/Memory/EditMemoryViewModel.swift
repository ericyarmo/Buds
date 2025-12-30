//
//  EditMemoryViewModel.swift
//  Buds
//
//  Phase 10.1 Module 1.2: ViewModel for edit/enrich flow
//

import Foundation
import SwiftUI
import PhotosUI
import Combine

@MainActor
final class EditMemoryViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var isLoading = false
    @Published var isSaving = false
    @Published var toast: Toast?

    // Form fields
    @Published var strainName = ""
    @Published var productType: ProductType = .flower
    @Published var rating = 0
    @Published var effects: [String] = []
    @Published var notes = ""
    @Published var images: [UIImage] = []
    @Published var selectedPhotosItem: [PhotosPickerItem] = []

    // MARK: - Private Properties

    private let memoryID: UUID
    private let repository = MemoryRepository()
    private var originalMemory: Memory?
    private var imageCIDsToDelete: [String] = []  // Track CIDs to delete on save

    // MARK: - Computed Properties

    var hasChanges: Bool {
        guard let original = originalMemory else { return false }

        return strainName != original.strainName ||
               productType != original.productType ||
               rating != original.rating ||
               effects != original.effects ||
               notes != (original.notes ?? "") ||
               images.count != original.imageData.count
    }

    // MARK: - Initialization

    init(memoryID: UUID) {
        self.memoryID = memoryID
    }

    // MARK: - Load Memory

    func loadMemory() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let memory = try await repository.fetch(id: memoryID)

            guard let memory = memory else {
                print("❌ Memory not found: \(memoryID)")
                toast = Toast(message: "Memory not found", style: .error)
                return
            }

            // Store original for change detection
            originalMemory = memory

            // Pre-fill form fields
            strainName = memory.strainName
            productType = memory.productType
            rating = memory.rating
            effects = memory.effects
            notes = memory.notes ?? ""

            // Convert image Data to UIImage
            images = memory.imageData.compactMap { UIImage(data: $0) }

            print("✅ Loaded memory for editing: \(memory.strainName)")
        } catch {
            print("❌ Failed to load memory: \(error)")
            toast = Toast(message: "Failed to load memory", style: .error)
        }
    }

    // MARK: - Photo Handling

    func loadSelectedPhotos() async {
        for item in selectedPhotosItem {
            do {
                if let data = try await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    // Compress to max 2MB
                    if let compressed = compressImage(image, maxSizeBytes: 2_000_000) {
                        images.append(compressed)
                    }
                }
            } catch {
                print("❌ Failed to load photo: \(error)")
            }
        }

        // Clear selection
        selectedPhotosItem = []
    }

    func removeImage(at index: Int) {
        guard index < images.count else { return }

        // If this was an original image, mark its CID for deletion
        if let original = originalMemory,
           index < original.imageData.count {
            // We don't have direct CID access here, but we'll regenerate on save
            // For now, just remove from array
        }

        images.remove(at: index)
    }

    func addCameraImage(_ image: UIImage) {
        // Compress to max 2MB
        if let compressed = compressImage(image, maxSizeBytes: 2_000_000) {
            images.append(compressed)
        }
    }

    private func compressImage(_ image: UIImage, maxSizeBytes: Int) -> UIImage? {
        var compression: CGFloat = 1.0
        var imageData = image.jpegData(compressionQuality: compression)

        while let data = imageData, data.count > maxSizeBytes && compression > 0.1 {
            compression -= 0.1
            imageData = image.jpegData(compressionQuality: compression)
        }

        guard let data = imageData else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Effects Handling

    func toggleEffect(_ effect: String) {
        if effects.contains(effect) {
            effects.removeAll { $0 == effect }
        } else {
            effects.append(effect)
        }
    }

    // MARK: - Save Changes

    func saveChanges() async -> Bool {
        guard !strainName.isEmpty else {
            toast = Toast(message: "Strain name is required", style: .error)
            return false
        }

        isSaving = true
        defer { isSaving = false }

        do {
            // Convert UIImages to Data
            let imageDataArray = images.compactMap { $0.jpegData(compressionQuality: 0.8) }

            // Update memory via repository
            try await repository.update(
                id: memoryID,
                strainName: strainName,
                productType: productType.rawValue,
                rating: rating,
                effects: effects,
                flavors: [],  // TODO: Add flavors UI in future
                notes: notes.isEmpty ? nil : notes,
                images: imageDataArray
            )

            print("✅ Memory updated: \(strainName)")

            // Haptic feedback
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

            return true
        } catch {
            print("❌ Failed to save changes: \(error)")
            toast = Toast(message: "Failed to save changes", style: .error)
            return false
        }
    }

    // MARK: - Skip Toast (for enrich mode)

    func showSkipToast() {
        toast = Toast(message: "Bud saved! Enrich it anytime", style: .success)
    }
}
