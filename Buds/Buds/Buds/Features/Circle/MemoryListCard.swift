//
//  MemoryListCard.swift
//  Buds
//
//  Phase 10 Step 2.3: Lightweight memory list card component
//  Phase 10.1 Module 1.0: Visual enrichment signals
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

    private var enrichmentLevel: EnrichmentLevel {
        item.enrichmentLevel
    }

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail or enrichment icon
            thumbnailView

            VStack(alignment: .leading, spacing: 4) {
                Text(item.strainName)
                    .font(.budsBodyBold)
                    .foregroundColor(.budsText)
                    .lineLimit(1)

                // Rating (or "Not rated yet" hint)
                ratingView

                // Timestamp
                Text(relativeDateFormatter.localizedString(for: item.createdAt, relativeTo: Date()))
                    .font(.budsCaption)
                    .foregroundColor(.budsTextSecondary)

                // Enrichment hint for minimal buds
                if enrichmentLevel == .minimal {
                    Text("+ Add Details")
                        .font(.budsCaption)
                        .foregroundColor(.orange)
                        .padding(.top, 2)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.budsCard)
        .overlay(cardBorder)  // Phase 10.1: Dashed border for minimal buds
        .cornerRadius(12)
        .onTapGesture {
            Task { await onTap() }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnailCID = item.thumbnailCID {
            CachedAsyncImage(cid: thumbnailCID)
                .frame(width: 60, height: 60)
                .cornerRadius(8)
        } else {
            // Different icon based on enrichment level
            Rectangle()
                .fill(iconBackgroundColor)
                .frame(width: 60, height: 60)
                .cornerRadius(8)
                .overlay(
                    Image(systemName: iconName)
                        .foregroundColor(iconColor)
                        .font(.title2)
                )
        }
    }

    @ViewBuilder
    private var ratingView: some View {
        if item.rating > 0 {
            HStack(spacing: 2) {
                ForEach(0..<item.rating, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundColor(.budsPrimary)
                }
            }
        } else {
            Text("⭐️ Not rated yet")
                .font(.budsCaption)
                .foregroundColor(.budsTextSecondary)
        }
    }

    @ViewBuilder
    private var cardBorder: some View {
        if enrichmentLevel == .minimal {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    Color.orange.opacity(0.5),
                    style: StrokeStyle(lineWidth: 2, dash: [5, 5])
                )
        } else {
            EmptyView()
        }
    }

    // MARK: - Enrichment Visual Properties

    private var iconName: String {
        switch enrichmentLevel {
        case .minimal: return "pencil.circle"
        case .partial: return "leaf.circle"
        case .complete: return "leaf.fill"
        }
    }

    private var iconColor: Color {
        switch enrichmentLevel {
        case .minimal: return .orange
        case .partial: return .yellow
        case .complete: return .budsPrimary
        }
    }

    private var iconBackgroundColor: Color {
        switch enrichmentLevel {
        case .minimal: return .orange.opacity(0.2)
        case .partial: return .yellow.opacity(0.2)
        case .complete: return .budsPrimary.opacity(0.2)
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
            jarID: "solo",
            effects: ["relaxed", "happy"],
            notes: "Great evening strain"
        ),
        onTap: {}
    )
    .padding()
    .background(Color.black)
}
