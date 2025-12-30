//
//  Reaction.swift
//  Buds
//
//  Created by Eric Yarmolinsky on 12/28/25.
//
//  Phase 10.1 Module 1.4: Social reactions for memories
//

import Foundation

/// Reaction to a memory (bud) - Phase 10.1 Module 1.4/1.5
struct Reaction: Identifiable, Codable {
    let id: UUID
    let memoryID: UUID
    let senderDID: String  // User who reacted (DID)
    let type: ReactionType
    let createdAt: Date

    init(id: UUID = UUID(), memoryID: UUID, senderDID: String, type: ReactionType, createdAt: Date = Date()) {
        self.id = id
        self.memoryID = memoryID
        self.senderDID = senderDID
        self.type = type
        self.createdAt = createdAt
    }
}

/// Reaction types with emoji representations
enum ReactionType: String, Codable, CaseIterable {
    case heart = "heart"
    case laughing = "laughing"
    case fire = "fire"
    case eyes = "eyes"
    case chilled = "chilled"

    /// Emoji for display
    var emoji: String {
        switch self {
        case .heart: return "❤️"
        case .laughing: return "😂"
        case .fire: return "🔥"
        case .eyes: return "👀"
        case .chilled: return "😌"
        }
    }

    /// Display name for accessibility
    var displayName: String {
        switch self {
        case .heart: return "Heart"
        case .laughing: return "Laughing"
        case .fire: return "Fire"
        case .eyes: return "Eyes"
        case .chilled: return "Chilled"
        }
    }
}

/// Reaction summary for display (grouped by type with counts)
struct ReactionSummary {
    let type: ReactionType
    let count: Int
    let senderDIDs: [String]  // Who reacted with this type

    var emoji: String {
        type.emoji
    }
}
