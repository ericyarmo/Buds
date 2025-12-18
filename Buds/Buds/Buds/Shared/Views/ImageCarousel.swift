//
//  ImageCarousel.swift
//  Buds
//
//  Created by Eric Yarmolinsky on 12/17/25.
//
//
//  ImageCarousel 2.swift
//  Buds
//
//  Swipeable carousel for displaying up to 3 images
//

import SwiftUI

struct ImageCarousel: View {
    let images: [Data]
    @State private var currentIndex: Int = 0
    @State private var scrollPosition: Int? = 0
    var maxHeight: CGFloat = 200
    var cornerRadius: CGFloat = BudsRadius.small
    var onTap: (() -> Void)? = nil

    var body: some View {
        let _ = print("🎠 ImageCarousel: Rendering with \(images.count) images")

        if images.isEmpty {
            let _ = print("🎠 ImageCarousel: No images, rendering EmptyView")
            return AnyView(EmptyView())
        } else if images.count == 1 {
            let _ = print("🎠 ImageCarousel: Single image, size: \(images[0].count) bytes")
            // Single image - no carousel needed
            return AnyView(singleImage(images[0]))
        } else {
            let _ = print("🎠 ImageCarousel: Multiple images carousel")
            // Multiple images - show carousel with ScrollView instead of TabView
            return AnyView(
                VStack(spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(Array(images.enumerated()), id: \.offset) { index, imageData in
                                GeometryReader { geometry in
                                    carouselImage(imageData)
                                        .frame(width: geometry.size.width)
                                        .id(index)
                                }
                                .containerRelativeFrame(.horizontal)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollPosition(id: $scrollPosition)
                    .scrollTargetBehavior(.paging)
                    .frame(height: maxHeight)
                    .onChange(of: scrollPosition) { _, newValue in
                        if let index = newValue {
                            currentIndex = index
                            print("🎠 ImageCarousel: Scrolled to index \(index)")
                        }
                    }

                    // Page indicator dots
                    pageIndicator
                }
            )
        }
    }

    // MARK: - Single Image

    private func singleImage(_ imageData: Data) -> some View {
        if let uiImage = UIImage(data: imageData) {
            let _ = print("🎠 ImageCarousel: Successfully created UIImage, size: \(uiImage.size)")
            return AnyView(
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: maxHeight)
                    .clipped()
                    .cornerRadius(cornerRadius)
                    .onTapGesture {
                        onTap?()
                    }
            )
        } else {
            let _ = print("❌ ImageCarousel: Failed to create UIImage from \(imageData.count) bytes")
            return AnyView(
                Text("Failed to load image")
                    .foregroundColor(.red)
                    .frame(height: maxHeight)
            )
        }
    }

    // MARK: - Carousel Image

    private func carouselImage(_ imageData: Data) -> some View {
        if let uiImage = UIImage(data: imageData) {
            let _ = print("🎠 ImageCarousel: Successfully created UIImage, size: \(uiImage.size)")
            return AnyView(
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: maxHeight)
                    .clipped()
                    .cornerRadius(cornerRadius)
                    .onTapGesture {
                        onTap?()
                    }
            )
        } else {
            let _ = print("❌ ImageCarousel: Failed to create UIImage from \(imageData.count) bytes")
            return AnyView(
                VStack {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text("Failed to load")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .frame(height: maxHeight)
            )
        }
    }

    // MARK: - Page Indicator

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<images.count, id: \.self) { index in
                Circle()
                    .fill(index == currentIndex ? Color.budsPrimary : Color.gray.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // No images
        ImageCarousel(images: [])

        // Single image (mock data)
        ImageCarousel(images: [Data()])

        // Multiple images (mock data)
        ImageCarousel(images: [Data(), Data(), Data()])
    }
    .padding()
    .background(Color.budsBackground)
}
