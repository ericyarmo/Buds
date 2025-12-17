//
//  EffectTag.swift
//  Buds
//
//  Color-coded tag for cannabis effects
//

import SwiftUI

struct EffectTag: View {
    let effect: String

    var body: some View {
        Text(effect.lowercased())
            .font(.budsTag)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(effectColor.opacity(0.2))
            .foregroundColor(effectColor)
            .cornerRadius(BudsRadius.small)
    }

    private var effectColor: Color {
        switch effect.lowercased() {
        case "relaxed": return .effectRelaxed
        case "creative": return .effectCreative
        case "energized": return .effectEnergized
        case "happy": return .effectHappy
        case "anxious": return .effectAnxious
        case "focused": return .effectFocused
        case "sleepy": return .effectSleepy
        case "euphoric": return .budsWarning
        default: return .secondary
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 8) {
        HStack {
            EffectTag(effect: "relaxed")
            EffectTag(effect: "creative")
            EffectTag(effect: "focused")
        }
        HStack {
            EffectTag(effect: "happy")
            EffectTag(effect: "energized")
            EffectTag(effect: "sleepy")
        }
        HStack {
            EffectTag(effect: "anxious")
            EffectTag(effect: "euphoric")
        }
    }
    .padding()
}
