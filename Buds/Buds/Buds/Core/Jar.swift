//
//  Jar.swift
//  Buds
//
//  Shared, encrypted space (max 12 people, unlimited buds)
//

import Foundation
import GRDB

struct Jar: Identifiable, Codable, FetchableRecord, PersistableRecord {
    var id: String  // UUID
    var name: String  // "Solo", "Friends", "Tahoe Trip"
    var description: String?
    var ownerDID: String
    var createdAt: Date
    var updatedAt: Date

    // MARK: - Database

    static let databaseTableName = "jars"

    enum Columns {
        static let id = Column("id")
        static let name = Column("name")
        static let description = Column("description")
        static let ownerDID = Column("owner_did")
        static let createdAt = Column("created_at")
        static let updatedAt = Column("updated_at")
    }

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case ownerDID = "owner_did"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Relationships

extension Jar {
    // Get members of this jar
    static let members = hasMany(JarMember.self, using: ForeignKey(["jar_id"]))
}

// MARK: - Computed Properties

extension Jar {
    var isSolo: Bool {
        return id == "solo"
    }
}
