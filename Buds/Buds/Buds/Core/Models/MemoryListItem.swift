//
//  MemoryListItem.swift
//  Buds
//
//  Phase 10 Step 2.1: Lightweight model for memory list display
//  Phase 10.1 Module 1.0: Added enrichment fields for visual signals
//  Avoids loading full Memory objects with all images/metadata
//

import Foundation

/// Lightweight representation of a memory for list views
/// Only includes data needed for rendering the list card
struct MemoryListItem: Identifiable {
    let id: UUID
    let strainName: String
    let productType: ProductType
    let rating: Int
    let createdAt: Date
    let thumbnailCID: String?
    let jarID: String

    // Phase 10.1: Enrichment fields for visual signals
    let effects: [String]
    let notes: String?
}

// MARK: - Enrichment Level (Phase 10.1 Module 1.0)

enum EnrichmentLevel {
    case minimal   // Just name, maybe type
    case partial   // Some details added
    case complete  // Fully enriched
}

extension MemoryListItem {
    /// Calculate enrichment level based on available data
    /// Used to show visual signals (dashed borders, icons, hints)
    var enrichmentLevel: EnrichmentLevel {
        var score = 0

        // Count populated fields
        if rating > 0 { score += 1 }
        if !effects.isEmpty { score += 1 }
        if let notes = notes, !notes.isEmpty { score += 1 }
        if thumbnailCID != nil { score += 1 }

        // Classify enrichment
        switch score {
        case 0...1:
            return .minimal      // Just name, maybe type
        case 2...3:
            return .partial      // Some details
        case 4...:
            return .complete     // Fully enriched
        default:
            return .minimal
        }
    }
}
