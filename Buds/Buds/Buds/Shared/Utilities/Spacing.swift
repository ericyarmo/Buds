//
//  Spacing.swift
//  Buds
//
//  Design system spacing scale
//

import SwiftUI

enum BudsSpacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

enum BudsRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let pill: CGFloat = 999
}

// MARK: - View Extensions

extension View {
    func budsPadding(_ edges: Edge.Set = .all) -> some View {
        self.padding(edges, BudsSpacing.m)
    }
}
