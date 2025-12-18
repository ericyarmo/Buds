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
;
struct PhotoPicker: View {
    @Binding var selectedImages: [Data]
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showPhotosPicker = false
    @State private var selectedPhotoIndex: Int? = nil

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
        .onChange(of: selectedItems) { oldItems, newItems in
            print("📸 PhotoPicker: onChange triggered")
            print("📸 PhotoPicker: Old items count: \(oldItems.count)")
            print("📸 PhotoPicker: New items count: \(newItems.count)")
            print("📸 PhotoPicker: Current selectedImages: \(selectedImages.count)")

            guard !newItems.isEmpty else {
                print("📸 PhotoPicker: No items to load")
                return
            }

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
        .photosPicker(
            isPresented: $showPhotosPicker,
            selection: $selectedItems,
            maxSelectionCount: maxPhotos - selectedImages.count,
            matching: .images
        )
    }

    // MARK: - Photo Thumbnail

    private func photoThumbnail(_ imageData: Data, at index: Int) -> some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                if let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipped()
                        .cornerRadius(BudsRadius.small)
                        .overlay(
                            RoundedRectangle(cornerRadius: BudsRadius.small)
                                .stroke(selectedPhotoIndex == index ? Color.budsPrimary : Color.clear, lineWidth: 3)
                        )
                        .onTapGesture {
                            withAnimation {
                                selectedPhotoIndex = selectedPhotoIndex == index ? nil : index
                            }
                        }
                }

                // Delete button
                Button {
                    withAnimation {
                        selectedImages.remove(at: index)
                        selectedPhotoIndex = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                }
                .offset(x: 8, y: -8)
            }

            // Reorder controls (show when selected)
            if selectedPhotoIndex == index {
                HStack(spacing: 12) {
                    // Move left
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            movePhoto(from: index, direction: -1)
                        }
                    } label: {
                        Image(systemName: "arrow.left.circle.fill")
                            .font(.title3)
                            .foregroundColor(index > 0 ? .budsPrimary : .gray.opacity(0.3))
                    }
                    .disabled(index == 0)

                    // Move right
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            movePhoto(from: index, direction: 1)
                        }
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)
                            .foregroundColor(index < selectedImages.count - 1 ? .budsPrimary : .gray.opacity(0.3))
                    }
                    .disabled(index == selectedImages.count - 1)
                }
            }
        }
    }

    private func movePhoto(from index: Int, direction: Int) {
        let newIndex = index + direction
        guard newIndex >= 0 && newIndex < selectedImages.count else { return }

        selectedImages.swapAt(index, newIndex)
        selectedPhotoIndex = newIndex
    }

    // MARK: - Add Photo Button

    private var addPhotoButton: some View {
        Menu {
            // Photo library option
            Button {
                print("📸 PhotoPicker: Photo Library button tapped")
                showPhotosPicker = true
            } label: {
                Label("Photo Library", systemImage: "photo.on.rectangle")
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
        print("📸 PhotoPicker: Loading \(items.count) items from selection")
        print("📸 PhotoPicker: Current selectedImages count: \(selectedImages.count)")

        var newImages: [Data] = []

        for (index, item) in items.enumerated() {
            if selectedImages.count + newImages.count >= maxPhotos {
                print("📸 PhotoPicker: Max photos reached")
                break
            }

            print("📸 PhotoPicker: Processing item \(index + 1)/\(items.count)")

            do {
                if let data = try await item.loadTransferable(type: Data.self) {
                    print("📸 PhotoPicker: Loaded image data (\(data.count) bytes)")

                    // Compress image if needed (max 2MB)
                    if let compressedData = compressImage(data) {
                        print("📸 PhotoPicker: Compressed to \(compressedData.count) bytes")
                        newImages.append(compressedData)
                    } else {
                        print("❌ PhotoPicker: Failed to compress image")
                    }
                } else {
                    print("❌ PhotoPicker: Failed to load transferable data for item \(index)")
                }
            } catch {
                print("❌ PhotoPicker: Error loading photo \(index) - \(error)")
            }
        }

        // Add all new images at once on main thread
        await MainActor.run {
            selectedImages.append(contentsOf: newImages)
            print("📸 PhotoPicker: Final selectedImages count: \(selectedImages.count)")
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

    func makeUIViewController(context: Context) -> CameraViewController {
        let cameraVC = CameraViewController()
        cameraVC.onCapture = onCapture
        cameraVC.onCancel = onCancel
        return cameraVC
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}
}

// MARK: - Camera View Controller

class CameraViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    var onCapture: ((Data) -> Void)?
    var onCancel: (() -> Void)?

    private var imagePicker: UIImagePickerController!
    private var flipButton: UIButton!
    private var currentCamera: UIImagePickerController.CameraDevice = .rear

    override func viewDidLoad() {
        super.viewDidLoad()

        setupImagePicker()
        setupFlipButton()
    }

    private func setupImagePicker() {
        imagePicker = UIImagePickerController()
        imagePicker.sourceType = .camera
        imagePicker.cameraDevice = currentCamera
        imagePicker.delegate = self
        imagePicker.allowsEditing = false

        addChild(imagePicker)
        view.addSubview(imagePicker.view)
        imagePicker.view.frame = view.bounds
        imagePicker.didMove(toParent: self)
    }

    private func setupFlipButton() {
        flipButton = UIButton(type: .system)
        flipButton.setImage(UIImage(systemName: "camera.rotate"), for: .normal)
        flipButton.tintColor = .white
        flipButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        flipButton.layer.cornerRadius = 30
        flipButton.translatesAutoresizingMaskIntoConstraints = false
        flipButton.addTarget(self, action: #selector(flipCamera), for: .touchUpInside)

        view.addSubview(flipButton)

        NSLayoutConstraint.activate([
            flipButton.widthAnchor.constraint(equalToConstant: 60),
            flipButton.heightAnchor.constraint(equalToConstant: 60),
            flipButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            flipButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -100)
        ])
    }

    @objc private func flipCamera() {
        print("📸 Camera: Flipping camera")

        // Toggle camera
        currentCamera = currentCamera == .rear ? .front : .rear

        // Recreate image picker with new camera
        imagePicker.view.removeFromSuperview()
        imagePicker.removeFromParent()

        imagePicker = UIImagePickerController()
        imagePicker.sourceType = .camera
        imagePicker.cameraDevice = currentCamera
        imagePicker.delegate = self
        imagePicker.allowsEditing = false

        addChild(imagePicker)
        view.insertSubview(imagePicker.view, at: 0)
        imagePicker.view.frame = view.bounds
        imagePicker.didMove(toParent: self)

        // Bring flip button to front
        view.bringSubviewToFront(flipButton)
    }

    // MARK: - UIImagePickerControllerDelegate

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        print("📸 Camera: Captured image")
        if let image = info[.originalImage] as? UIImage,
           let imageData = image.jpegData(compressionQuality: 0.8) {
            print("📸 Camera: Converted to JPEG (\(imageData.count) bytes)")
            onCapture?(imageData)
        } else {
            print("❌ Camera: Failed to convert image")
            onCancel?()
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        print("📸 Camera: Cancelled by user")
        onCancel?()
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
