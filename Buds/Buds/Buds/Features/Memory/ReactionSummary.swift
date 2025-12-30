//
//  ReactionSummary.swift
//  Buds
//
//  Created by Eric Yarmolinsky on 12/28/25.
//
//  Phase 10.1 Module 1.4: Display reaction counts
//

import SwiftUI

/// Displays reactions grouped by type with counts (e.g., "❤️ 3  🔥 2")
struct ReactionSummaryView: View {
    let summaries: [ReactionSummary]

    var body: some View {
        if !summaries.isEmpty {
            HStack(spacing: 8) {
                ForEach(summaries, id: \.type) { summary in
                    reactionBubble(summary)
                }

                Spacer()
            }
            .padding(.vertical, BudsSpacing.s)
        }
    }

    private func reactionBubble(_ summary: ReactionSummary) -> some View {
        HStack(spacing: 3) {
            Text(summary.emoji)
                .font(.system(size: 18))

            Text("\(summary.count)")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.budsTextPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.budsSurface)
        .cornerRadius(14)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        ReactionSummaryView(summaries: [
            ReactionSummary(type: .heart, count: 3, senderDIDs: ["did:buds:abc", "did:buds:def", "did:buds:ghi"]),
            ReactionSummary(type: .fire, count: 2, senderDIDs: ["did:buds:abc", "did:buds:def"]),
            ReactionSummary(type: .chilled, count: 1, senderDIDs: ["did:buds:abc"])
        ])

        ReactionSummaryView(summaries: [])
    }
    .padding()
    .background(Color.black)
}
