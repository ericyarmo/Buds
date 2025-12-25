//
//  MemoryCard.swift
//  Buds
//
//  Card displaying a cannabis memory in timeline
//

import SwiftUI
import GRDB

struct MemoryCard: View {
    let memory: Memory
    let onTap: () -> Void
    let onToggleFavorite: () -> Void

    @State private var senderName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header section with colored accent
            VStack(alignment: .leading, spacing: BudsSpacing.xs) {
                HStack(alignment: .top) {
                    HStack(spacing: 8) {
                        Text(memory.productType.emoji)
                            .font(.title2)
                        Text(memory.strainName)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.budsTextPrimary)
                    }

                    Spacer()

                    Button(action: onToggleFavorite) {
                        Image(systemName: memory.isFavorited ? "heart.fill" : "heart")
                            .foregroundColor(memory.isFavorited ? .budsError : .budsTextSecondary)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }

                // Rating + timestamp
                HStack {
                    HStack(spacing: 3) {
                        ForEach(0..<5) { index in
                            Image(systemName: index < memory.rating ? "star.fill" : "star")
                                .foregroundColor(.budsWarning)
                                .font(.caption2)
                        }
                    }

                    Text("•")
                        .foregroundColor(.budsTextSecondary)
                        .font(.caption)

                    Text(memory.relativeTimestamp)
                        .font(.caption)
                        .foregroundColor(.budsTextSecondary)

                    Spacer()
                }
            }
            .padding(BudsSpacing.m)
            .background(
                LinearGradient(
                    colors: [Color.budsPrimary.opacity(0.08), Color.budsPrimary.opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            // Photos (if present)
            if !memory.imageData.isEmpty {
                ImageCarousel(images: memory.imageData, maxHeight: 180, cornerRadius: 0, onTap: onTap)
            }

            // Content section
            VStack(alignment: .leading, spacing: BudsSpacing.s) {
                // Notes (truncated)
                if let notes = memory.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.budsBody)
                        .foregroundColor(.budsTextPrimary)
                        .lineLimit(2)
                }

                // Effects chips
                if !memory.effects.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(memory.effects.prefix(5), id: \.self) { effect in
                                EffectTag(effect: effect)
                            }
                            if memory.effects.count > 5 {
                                Text("+\(memory.effects.count - 5)")
                                    .font(.caption2)
                                    .foregroundColor(.budsTextSecondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(BudsRadius.pill)
                            }
                        }
                    }
                }

                Divider()
                    .padding(.vertical, 2)

                // Bottom metadata
                HStack(spacing: BudsSpacing.m) {
                    // Brand
                    if let brand = memory.brand {
                        HStack(spacing: 4) {
                            Image(systemName: "tag.fill")
                                .font(.caption2)
                                .foregroundColor(.budsPrimary)
                            Text(brand)
                                .font(.caption)
                                .foregroundColor(.budsTextPrimary)
                        }
                    }

                    Spacer()

                    // Share indicator
                    HStack(spacing: 4) {
                        if let senderDID = memory.senderDID {
                            // Received from Circle member
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.budsAccent)
                            if let name = senderName {
                                Text("From \(name)")
                                    .font(.caption)
                                    .foregroundColor(.budsTextSecondary)
                            } else {
                                Text("Shared")
                                    .font(.caption)
                                    .foregroundColor(.budsTextSecondary)
                            }
                        } else {
                            // Your own memory
                            Image(systemName: memory.isShared ? "person.2.fill" : "lock.fill")
                                .font(.caption2)
                                .foregroundColor(memory.isShared ? .budsSuccess : .budsTextSecondary)
                            Text(memory.isShared ? "Shared" : "Private")
                                .font(.caption)
                                .foregroundColor(.budsTextSecondary)
                        }
                    }
                }
            }
            .padding(BudsSpacing.m)
        }
        .background(Color.budsSurface)
        .cornerRadius(BudsRadius.medium)
        .shadow(color: Color.budsPrimary.opacity(0.12), radius: 12, x: 0, y: 4)
        .onTapGesture(perform: onTap)
        .task {
            // Load sender name if this is a received memory
            if let senderDID = memory.senderDID {
                await loadSenderName(did: senderDID)
            }
        }
    }

    // MARK: - Helpers

    private func loadSenderName(did: String) async {
        do {
            let members = try await Database.shared.readAsync { db in
                try CircleMember
                    .filter(sql: "did = ?", arguments: [did])
                    .fetchAll(db)
            }
            if let member = members.first {
                senderName = member.displayName
            }
        } catch {
            print("❌ Failed to load sender name: \(error)")
        }
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
