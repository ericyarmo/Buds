//
//  MemoryListItem.swift
//  Buds
//
//  Phase 10 Step 2.1: Lightweight model for memory list display
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
}
