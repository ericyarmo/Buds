//
//  MemoryListCard.swift
//  Buds
//
//  Phase 10 Step 2.3: Lightweight memory list card component
//

import SwiftUI
import GRDB

struct MemoryListCard: View {
    let item: MemoryListItem
    let onTap: () async -> Void

    private let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail (cached)
            if let thumbnailCID = item.thumbnailCID {
                CachedAsyncImage(cid: thumbnailCID)
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
            } else {
                Rectangle()
                    .fill(Color.budsPrimary.opacity(0.2))
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
                    .overlay(
                        Image(systemName: "leaf.fill")
                            .foregroundColor(.budsPrimary.opacity(0.5))
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.strainName)
                    .font(.budsBodyBold)
                    .foregroundColor(.budsText)
                    .lineLimit(1)

                HStack(spacing: 2) {
                    ForEach(0..<item.rating, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundColor(.budsPrimary)
                    }
                }

                Text(relativeDateFormatter.localizedString(for: item.createdAt, relativeTo: Date()))
                    .font(.budsCaption)
                    .foregroundColor(.budsTextSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.budsCard)
        .cornerRadius(12)
        .onTapGesture {
            Task { await onTap() }
        }
    }
}

// MARK: - Cached Async Image (Phase 10 Step 2.3)

struct CachedAsyncImage: View {
    let cid: String
    @State private var thumbnailImage: UIImage?

    private static var cache: [String: UIImage] = [:]
    private static let cacheLock = NSLock()
    private static let thumbnailSize = CGSize(width: 120, height: 120) // 2x for retina

    var body: some View {
        Group {
            if let image = thumbnailImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ProgressView()
                    .tint(.budsPrimary)
            }
        }
        .task {
            // Check cache
            Self.cacheLock.lock()
            if let cached = Self.cache[cid] {
                thumbnailImage = cached
                Self.cacheLock.unlock()
                return
            }
            Self.cacheLock.unlock()

            // Load from DB and downsample
            do {
                let data = try await Database.shared.readAsync { db in
                    try Data.fetchOne(db, sql: "SELECT data FROM blobs WHERE cid = ?", arguments: [cid])
                }

                if let data = data {
                    // Downsample to thumbnail size
                    let downsampled = Self.downsample(imageData: data, to: Self.thumbnailSize)

                    if let downsampled = downsampled {
                        Self.cacheLock.lock()
                        Self.cache[cid] = downsampled
                        Self.cacheLock.unlock()

                        thumbnailImage = downsampled
                    }
                }
            } catch {
                print("❌ Failed to load image: \(error)")
            }
        }
    }

    /// Downsample image to target size to reduce memory usage
    private static func downsample(imageData: Data, to targetSize: CGSize) -> UIImage? {
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, imageSourceOptions) else {
            return nil
        }

        let maxDimensionInPixels = max(targetSize.width, targetSize.height)
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimensionInPixels
        ] as CFDictionary

        guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
            return nil
        }

        return UIImage(cgImage: downsampledImage)
    }
}

// MARK: - Preview

#Preview {
    MemoryListCard(
        item: MemoryListItem(
            id: UUID(),
            strainName: "Blue Dream",
            productType: .flower,
            rating: 4,
            createdAt: Date(),
            thumbnailCID: nil,
            jarID: "solo"
        ),
        onTap: {}
    )
    .padding()
    .background(Color.black)
}
