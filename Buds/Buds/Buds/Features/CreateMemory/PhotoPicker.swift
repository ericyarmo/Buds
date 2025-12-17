//
//  PhotoPicker.swift
//  Buds
//
//  Created by Eric Yarmolinsky on 12/17/25.
//
//  Photo selection component (up to 3 photos from library or camera)
//

import SwiftUI
import PhotosUI

struct PhotoPicker: View {
    @Binding var selectedImages: [Data]
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showCamera = false

    let maxPhotos: Int = 3

    var body: some View {
        VStack(alignment: .leading, spacing: BudsSpacing.s) {
            // Photos grid
            if !selectedImages.isEmpty {
                HStack(spacing: BudsSpacing.s) {
                    ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, imageData in
                        photoThumbnail(imageData, at: index)
                    }

                    // Add photo button (if less than 3)
                    if selectedImages.count < maxPhotos {
                        addPhotoButton
                    }
                }
            } else {
                // Empty state - show add button
                addPhotoButton
            }
        }
        .onChange(of: selectedItems) { _, newItems in
            Task {
                await loadPhotos(from: newItems)
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraView(
                onCapture: { imageData in
                    if selectedImages.count < maxPhotos {
                        selectedImages.append(imageData)
                    }
                    showCamera = false
                },
                onCancel: {
                    showCamera = false
                }
            )
        }
    }

    // MARK: - Photo Thumbnail

    private func photoThumbnail(_ imageData: Data, at index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            if let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipped()
                    .cornerRadius(BudsRadius.small)
            }

            // Delete button
            Button {
                selectedImages.remove(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.white)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            .offset(x: 8, y: -8)
        }
    }

    // MARK: - Add Photo Button

    private var addPhotoButton: some View {
        Menu {
            // Photo library option
            Button {
                print("📸 PhotoPicker: Photo Library button tapped")
                // Trigger PhotosPicker manually
            } label: {
                Label("Photo Library", systemImage: "photo.on.rectangle")
            }

            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: maxPhotos - selectedImages.count,
                matching: .images
            ) {
                Label("Select from Library", systemImage: "photo.stack")
            }

            // Camera option
            Button {
                print("📸 PhotoPicker: Camera button tapped")
                showCamera = true
            } label: {
                Label("Take Photo", systemImage: "camera")
            }
        } label: {
            VStack {
                Image(systemName: "photo.badge.plus")
                    .font(.title2)
                    .foregroundColor(.budsPrimary)
                Text("Add Photo")
                    .font(.budsCaption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 80, height: 80)
            .background(Color.budsSurface)
            .cornerRadius(BudsRadius.small)
            .overlay(
                RoundedRectangle(cornerRadius: BudsRadius.small)
                    .stroke(Color.budsDivider, lineWidth: 1)
            )
        }
    }

    // MARK: - Load Photos

    private func loadPhotos(from items: [PhotosPickerItem]) async {
        print("📸 PhotoPicker: Loading \(items.count) items")

        for item in items {
            if selectedImages.count >= maxPhotos {
                print("📸 PhotoPicker: Max photos reached")
                break
            }

            do {
                if let data = try await item.loadTransferable(type: Data.self) {
                    print("📸 PhotoPicker: Loaded image data (\(data.count) bytes)")

                    // Compress image if needed (max 2MB)
                    if let compressedData = compressImage(data) {
                        print("📸 PhotoPicker: Compressed to \(compressedData.count) bytes")
                        await MainActor.run {
                            selectedImages.append(compressedData)
                        }
                    } else {
                        print("❌ PhotoPicker: Failed to compress image")
                    }
                } else {
                    print("❌ PhotoPicker: Failed to load transferable data")
                }
            } catch {
                print("❌ PhotoPicker: Error loading photo - \(error)")
            }
        }

        // Clear selection
        await MainActor.run {
            selectedItems = []
        }
    }

    private func compressImage(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }

        // Target max size: 2MB
        let maxSizeBytes = 2 * 1024 * 1024
        var compressionQuality: CGFloat = 0.8

        var compressedData = image.jpegData(compressionQuality: compressionQuality)

        // Iteratively reduce quality if still too large
        while let data = compressedData, data.count > maxSizeBytes, compressionQuality > 0.1 {
            compressionQuality -= 0.1
            compressedData = image.jpegData(compressionQuality: compressionQuality)
        }

        return compressedData
    }
}

// MARK: - Camera View

struct CameraView: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (Data) -> Void
        let onCancel: () -> Void

        init(onCapture: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            print("📸 Camera: Captured image")
            if let image = info[.originalImage] as? UIImage,
               let imageData = image.jpegData(compressionQuality: 0.8) {
                print("📸 Camera: Converted to JPEG (\(imageData.count) bytes)")
                onCapture(imageData)
            } else {
                print("❌ Camera: Failed to convert image")
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            print("📸 Camera: Cancelled by user")
            onCancel()
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var images: [Data] = []

    Form {
        Section {
            PhotoPicker(selectedImages: $images)
        } header: {
            Text("Photos (3 max)")
        }
    }
}
