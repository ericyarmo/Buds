//
//  JarMember.swift
//  Buds
//
//  A person in a jar (N:M relationship)
//

import Foundation
import GRDB

struct JarMember: Codable, FetchableRecord, PersistableRecord {
    var jarID: String
    var memberDID: String
    var displayName: String
    var phoneNumber: String?
    var avatarCID: String?
    var pubkeyX25519: String
    var role: Role
    var status: Status
    var joinedAt: Date?
    var invitedAt: Date?
    var removedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    enum Role: String, Codable {
        case owner = "owner"
        case member = "member"
    }

    enum Status: String, Codable {
        case pending = "pending"
        case active = "active"
        case removed = "removed"
    }

    // MARK: - Database

    static let databaseTableName = "jar_members"

    enum Columns {
        static let jarID = Column("jar_id")
        static let memberDID = Column("member_did")
        static let displayName = Column("display_name")
        static let phoneNumber = Column("phone_number")
        static let avatarCID = Column("avatar_cid")
        static let pubkeyX25519 = Column("pubkey_x25519")
        static let role = Column("role")
        static let status = Column("status")
        static let joinedAt = Column("joined_at")
        static let invitedAt = Column("invited_at")
        static let removedAt = Column("removed_at")
        static let createdAt = Column("created_at")
        static let updatedAt = Column("updated_at")
    }

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case jarID = "jar_id"
        case memberDID = "member_did"
        case displayName = "display_name"
        case phoneNumber = "phone_number"
        case avatarCID = "avatar_cid"
        case pubkeyX25519 = "pubkey_x25519"
        case role
        case status
        case joinedAt = "joined_at"
        case invitedAt = "invited_at"
        case removedAt = "removed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Identifiable (for SwiftUI)

extension JarMember: Identifiable {
    var id: String { "\(jarID)-\(memberDID)" }  // Composite key
}

// MARK: - Relationships

extension JarMember {
    static let jar = belongsTo(Jar.self, using: ForeignKey(["jar_id"]))
}
