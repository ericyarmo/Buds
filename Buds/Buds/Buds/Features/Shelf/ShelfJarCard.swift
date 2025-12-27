//
//  ShelfJarCard.swift
//  Buds
//
//  Phase 9b: Shelf jar card (dumb view - stats passed from parent)
//

import SwiftUI

struct ShelfJarCard: View {
    let jar: Jar
    let stats: JarStats?  // Passed from parent, not fetched

    private var activityDots: Int {
        min(4, stats?.recentBuds ?? 0)  // RECENT buds (last 24h), not total!
    }

    private var hasRecentActivity: Bool {
        (stats?.recentBuds ?? 0) > 0
    }

    var body: some View {
        VStack(spacing: 8) {
            // Activity dots (top)
            HStack(spacing: 6) {
                ForEach(0..<activityDots, id: \.self) { _ in
                    Circle()
                        .fill(Color.budsPrimary)
                        .frame(width: 8, height: 8)
                }
                Spacer()
            }
            .frame(height: 20)
            .padding(.horizontal, 12)

            Spacer()

            // Jar name
            Text(jar.name)
                .font(.budsHeadline)
                .foregroundColor(.budsTextPrimary)
                .lineLimit(1)

            // Bud count
            Text("\(stats?.totalBuds ?? 0) buds")
                .font(.budsCaption)
                .foregroundColor(.budsTextSecondary)

            Spacer()
        }
        .padding()
        .frame(height: 150)  // Fixed height (not square)
        .frame(maxWidth: .infinity)
        .background(Color.budsCard)
        .cornerRadius(16)
        .shadow(
            color: hasRecentActivity ? Color.budsPrimary.opacity(0.4) : .clear,
            radius: hasRecentActivity ? 8 : 0
        )
    }
}

// MARK: - Preview

struct ShelfJarCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            // Card with recent activity
            ShelfJarCard(
                jar: Jar(
                    id: "1",
                    name: "Friends",
                    description: nil,
                    ownerDID: "did:example",
                    createdAt: Date(),
                    updatedAt: Date()
                ),
                stats: JarStats(
                    jarID: "1",
                    totalBuds: 12,
                    recentBuds: 3,
                    lastCreatedAt: Date()
                )
            )
            .frame(width: 180)

            // Card with no recent activity
            ShelfJarCard(
                jar: Jar(
                    id: "2",
                    name: "Solo",
                    description: nil,
                    ownerDID: "did:example",
                    createdAt: Date(),
                    updatedAt: Date()
                ),
                stats: JarStats(
                    jarID: "2",
                    totalBuds: 5,
                    recentBuds: 0,
                    lastCreatedAt: nil
                )
            )
            .frame(width: 180)

            // Empty jar
            ShelfJarCard(
                jar: Jar(
                    id: "3",
                    name: "Tahoe Trip",
                    description: nil,
                    ownerDID: "did:example",
                    createdAt: Date(),
                    updatedAt: Date()
                ),
                stats: nil  // No stats (empty jar)
            )
            .frame(width: 180)
        }
        .padding()
        .background(Color.black)
    }
}
