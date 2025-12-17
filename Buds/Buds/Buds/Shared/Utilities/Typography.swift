//
//  Typography.swift
//  Buds
//
//  Design system typography
//

import SwiftUI

extension Font {
    // MARK: - Titles

    static let budsTitle = Font.system(size: 28, weight: .bold)
    static let budsHeadline = Font.system(size: 22, weight: .semibold)

    // MARK: - Body

    static let budsBody = Font.system(size: 17, weight: .regular)
    static let budsBodyBold = Font.system(size: 17, weight: .semibold)

    // MARK: - Small

    static let budsCaption = Font.system(size: 13, weight: .regular)
    static let budsTag = Font.system(size: 12, weight: .medium)
}

// MARK: - Text Modifiers

extension Text {
    func titleStyle() -> some View {
        self.font(.budsTitle)
            .foregroundColor(.primary)
    }

    func headlineStyle() -> some View {
        self.font(.budsHeadline)
            .foregroundColor(.primary)
    }

    func bodyStyle() -> some View {
        self.font(.budsBody)
            .foregroundColor(.primary)
    }

    func captionStyle() -> some View {
        self.font(.budsCaption)
            .foregroundColor(.secondary)
    }
}
