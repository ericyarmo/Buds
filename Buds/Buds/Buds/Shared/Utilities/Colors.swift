//
//  Colors.swift
//  Buds
//
//  Design system color palette
//

import SwiftUI

extension Color {
    // MARK: - Primary Palette
    // Note: budsPrimary defined in Assets.xcassets
    static let budsSecondary = Color(hex: "#8BC34A")    // Light green
    static let budsAccent = Color(hex: "#FF6B35")       // Orange CTA

    // MARK: - Backgrounds
    static let budsBackground = Color(hex: "#F5F5F5")   // Light gray
    // Note: budsSurface defined in Assets.xcassets
    static let budsSurfaceDark = Color(hex: "#1E1E1E")

    // MARK: - Semantic
    // Note: budsSuccess defined in Assets.xcassets
    static let budsWarning = Color(hex: "#FFC107")
    static let budsError = Color(hex: "#F44336")
    static let budsInfo = Color(hex: "#2196F3")

    // MARK: - Effect Tags

    static let effectRelaxed = Color(hex: "#64B5F6")    // Soft blue
    static let effectCreative = Color(hex: "#BA68C8")   // Purple
    static let effectEnergized = Color(hex: "#FFD54F")  // Yellow
    static let effectHappy = Color(hex: "#FF8A65")      // Orange
    static let effectAnxious = Color(hex: "#E57373")    // Red (warning)
    static let effectFocused = Color(hex: "#4DD0E1")    // Cyan
    static let effectSleepy = Color(hex: "#9575CD")     // Deep purple

    // MARK: - Hex Initializer

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: // RGB
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
