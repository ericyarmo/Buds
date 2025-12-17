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
    var maxHeight: CGFloat = 200
    var cornerRadius: CGFloat = BudsRadius.small
    var onTap: (() -> Void)? = nil

    var body: some View {
        if images.isEmpty {
            EmptyView()
        } else if images.count == 1 {
            // Single image - no carousel needed
            singleImage(images[0])
        } else {
            // Multiple images - show carousel
            VStack(spacing: 8) {
                TabView(selection: $currentIndex) {
                    ForEach(Array(images.enumerated()), id: \.offset) { index, imageData in
                        carouselImage(imageData)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: maxHeight)

                // Page indicator dots
                pageIndicator
            }
        }
    }

    // MARK: - Single Image

    private func singleImage(_ imageData: Data) -> some View {
        Group {
            if let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxHeight: maxHeight)
                    .clipped()
                    .cornerRadius(cornerRadius)
                    .onTapGesture {
                        onTap?()
                    }
            }
        }
    }

    // MARK: - Carousel Image

    private func carouselImage(_ imageData: Data) -> some View {
        Group {
            if let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxHeight: maxHeight)
                    .clipped()
                    .cornerRadius(cornerRadius)
                    .onTapGesture {
                        onTap?()
                    }
            }
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
