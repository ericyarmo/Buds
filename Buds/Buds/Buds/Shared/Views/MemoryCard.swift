//
//  MemoryCard.swift
//  Buds
//
//  Card displaying a cannabis memory in timeline
//

import SwiftUI

struct MemoryCard: View {
    let memory: Memory
    let onTap: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BudsSpacing.s) {
            // Header: Strain + Favorite
            HStack {
                Text("\(memory.productType.emoji) \(memory.strainName)")
                    .font(.budsHeadline)

                Spacer()

                Button(action: onToggleFavorite) {
                    Image(systemName: memory.isFavorited ? "heart.fill" : "heart")
                        .foregroundColor(memory.isFavorited ? .budsError : .secondary)
                        .font(.body)
                }
                .buttonStyle(.plain)
            }

            // Timestamp
            Text(memory.relativeTimestamp)
                .font(.budsCaption)
                .foregroundColor(.secondary)

            Divider()

            // Photo (if present)
            if let imageData = memory.imageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxHeight: 200)
                    .clipped()
                    .cornerRadius(BudsRadius.small)
            }

            // Notes (truncated)
            if let notes = memory.notes, !notes.isEmpty {
                Text(notes)
                    .font(.budsBody)
                    .lineLimit(3)
            }

            // Brand (if present)
            if let brand = memory.brand {
                HStack {
                    Image(systemName: "tag.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(brand)
                        .font(.budsCaption)
                        .foregroundColor(.secondary)
                }
            }

            // Rating + Effects
            HStack {
                // Stars
                HStack(spacing: 2) {
                    ForEach(0..<5) { index in
                        Image(systemName: index < memory.rating ? "star.fill" : "star")
                            .foregroundColor(.budsWarning)
                            .font(.caption)
                    }
                }

                Spacer()

                // Effects
                HStack(spacing: 4) {
                    ForEach(memory.effects.prefix(3), id: \.self) { effect in
                        EffectTag(effect: effect)
                    }
                    if memory.effects.count > 3 {
                        Text("+\(memory.effects.count - 3)")
                            .font(.budsTag)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Location + Share indicator
            HStack {
                if memory.hasLocation, let locationName = memory.locationName {
                    Label(locationName, systemImage: "location.fill")
                        .font(.budsCaption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: memory.isShared ? "globe" : "lock.fill")
                    .font(.caption)
                    .foregroundColor(memory.isShared ? .budsInfo : .secondary)

                if memory.isShared {
                    Text("Shared")
                        .font(.budsCaption)
                        .foregroundColor(.budsInfo)
                }
            }
        }
        .budsPadding()
        .background(Color.budsSurface)
        .cornerRadius(BudsRadius.medium)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        MemoryCard(memory: .preview) {
            print("Tapped")
        } onToggleFavorite: {
            print("Toggle favorite")
        }

        MemoryCard(memory: .previews[1]) {
            print("Tapped")
        } onToggleFavorite: {
            print("Toggle favorite")
        }
    }
    .padding()
    .background(Color.budsBackground)
}
