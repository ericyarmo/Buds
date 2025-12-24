//
//  Memory.swift
//  Buds
//
//  User-facing model for cannabis sessions/experiences
//

import Foundation
import Combine

/// User-facing model for a cannabis memory
struct Memory: Identifiable, Codable {
    let id: UUID                         // Local UUID (from local_receipts table)
    let receiptCID: String               // CID of underlying receipt

    // Core data
    let strainName: String
    let productType: ProductType
    let rating: Int                      // 1-5
    let notes: String?

    // Product details
    let brand: String?
    let thcPercent: Double?
    let cbdPercent: Double?
    let amountGrams: Double?

    // Effects & method
    let effects: [String]
    let consumptionMethod: ConsumptionMethod?

    // Timestamps
    let createdAt: Date                  // Local creation time
    let claimedTimeMs: Int64?            // User's claimed time (unverified)

    // Location
    let hasLocation: Bool
    let locationName: String?

    // Metadata
    var isFavorited: Bool
    var isShared: Bool
    var imageData: [Data]  // Array of up to 3 images

    // MARK: - Computed Properties

    var relativeTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }

    var displayTime: String {
        if let claimed = claimedTimeMs {
            let date = Date(timeIntervalSince1970: Double(claimed) / 1000)
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else {
            return relativeTimestamp
        }
    }
}

// MARK: - Product Type

enum ProductType: String, Codable {
    case flower
    case edible
    case concentrate
    case vape
    case tincture
    case topical
    case other

    var displayName: String {
        rawValue.capitalized
    }

    var emoji: String {
        switch self {
        case .flower: return "🌿"
        case .edible: return "🍪"
        case .concentrate: return "💎"
        case .vape: return "💨"
        case .tincture: return "💧"
        case .topical: return "🧴"
        case .other: return "📦"
        }
    }
}

// MARK: - Consumption Method

enum ConsumptionMethod: String, Codable {
    case joint
    case bong
    case pipe
    case vape
    case edible
    case dab
    case tincture
    case topical

    var displayName: String {
        rawValue.capitalized
    }

    var emoji: String {
        switch self {
        case .joint: return "🚬"
        case .bong: return "🫧"
        case .pipe: return "🪈"
        case .vape: return "💨"
        case .edible: return "🍪"
        case .dab: return "🔥"
        case .tincture: return "💧"
        case .topical: return "🧴"
        }
    }
}

// MARK: - Preview Helpers

extension Memory {
    static var preview: Memory {
        Memory(
            id: UUID(),
            receiptCID: "bafyreitest123",
            strainName: "Blue Dream",
            productType: .flower,
            rating: 5,
            notes: "Perfect for creative work. Felt super focused but relaxed.",
            brand: "Cookies",
            thcPercent: 23.5,
            cbdPercent: 0.8,
            amountGrams: 3.5,
            effects: ["relaxed", "creative", "focused"],
            consumptionMethod: .vape,
            createdAt: Date().addingTimeInterval(-3600),
            claimedTimeMs: Int64(Date().addingTimeInterval(-3600).timeIntervalSince1970 * 1000),
            hasLocation: true,
            locationName: "Home",
            isFavorited: false,
            isShared: false,
            imageData: []
        )
    }

    static var previews: [Memory] {
        [
            preview,
            Memory(
                id: UUID(),
                receiptCID: "bafyreitest456",
                strainName: "Gelato",
                productType: .flower,
                rating: 4,
                notes: "Great evening smoke. Super relaxed.",
                brand: "Jungle Boys",
                thcPercent: 24.2,
                cbdPercent: nil,
                amountGrams: nil,
                effects: ["relaxed", "happy", "sleepy"],
                consumptionMethod: .joint,
                createdAt: Date().addingTimeInterval(-86400 * 3),
                claimedTimeMs: nil,
                hasLocation: false,
                locationName: nil,
                isFavorited: true,
                isShared: true,
                imageData: []
            )
        ]
    }
}
