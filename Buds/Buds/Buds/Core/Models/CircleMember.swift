//
//  CircleMember.swift
//  Buds
//
//  Represents a member of your Circle
//

import Foundation
import GRDB

struct CircleMember: Identifiable, Codable, FetchableRecord, PersistableRecord {
    var id: String
    var did: String
    var displayName: String
    var phoneNumber: String?
    var avatarCID: String?
    var pubkeyX25519: String
    var status: CircleStatus
    var joinedAt: Date?
    var invitedAt: Date?
    var removedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    enum CircleStatus: String, Codable {
        case pending = "pending"
        case active = "active"
        case removed = "removed"
    }

    // MARK: - Database

    static let databaseTableName = "circles"

    enum Columns {
        static let id = Column("id")
        static let did = Column("did")
        static let displayName = Column("display_name")
        static let phoneNumber = Column("phone_number")
        static let avatarCID = Column("avatar_cid")
        static let pubkeyX25519 = Column("pubkey_x25519")
        static let status = Column("status")
        static let joinedAt = Column("joined_at")
        static let invitedAt = Column("invited_at")
        static let removedAt = Column("removed_at")
        static let createdAt = Column("created_at")
        static let updatedAt = Column("updated_at")
    }

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case id
        case did
        case displayName = "display_name"
        case phoneNumber = "phone_number"
        case avatarCID = "avatar_cid"
        case pubkeyX25519 = "pubkey_x25519"
        case status
        case joinedAt = "joined_at"
        case invitedAt = "invited_at"
        case removedAt = "removed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
