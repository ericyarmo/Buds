//
//  ReactionPicker.swift
//  Buds
//
//  Created by Eric Yarmolinsky on 12/28/25.
//
//  Phase 10.1 Module 1.4: Reaction picker UI (5 emoji buttons)
//

import SwiftUI

/// Reaction picker with 5 emoji buttons (tap to toggle)
struct ReactionPicker: View {
    let currentReaction: ReactionType?  // User's current reaction (if any)
    let onReact: (ReactionType) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BudsSpacing.s) {
            Text("React")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.budsTextSecondary)

            HStack(spacing: 10) {
                ForEach(ReactionType.allCases, id: \.self) { type in
                    reactionButton(type)
                }
            }
        }
    }

    private func reactionButton(_ type: ReactionType) -> some View {
        Button {
            onReact(type)
        } label: {
            Text(type.emoji)
                .font(.system(size: 26))
                .frame(width: 44, height: 44)
                .background(isSelected(type) ? Color.budsPrimary.opacity(0.3) : Color.budsSurface)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isSelected(type) ? Color.budsPrimary : Color.clear,
                            lineWidth: 2
                        )
                )
        }
        .accessibilityLabel("\(type.displayName) reaction")
    }

    private func isSelected(_ type: ReactionType) -> Bool {
        currentReaction == type
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 30) {
        // No selection
        ReactionPicker(currentReaction: nil) { type in
            print("Reacted with \(type.emoji)")
        }

        // Heart selected
        ReactionPicker(currentReaction: .heart) { type in
            print("Reacted with \(type.emoji)")
        }

        // Fire selected
        ReactionPicker(currentReaction: .fire) { type in
            print("Reacted with \(type.emoji)")
        }
    }
    .padding()
    .background(Color.black)
}
