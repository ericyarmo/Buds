//
//  Device.swift
//  Buds
//
//  Represents a device (for multi-device E2EE)
//

import Foundation
import GRDB

struct Device: Codable, FetchableRecord, PersistableRecord {
    var deviceId: String
    var ownerDID: String
    var deviceName: String
    var pubkeyX25519: String
    var pubkeyEd25519: String
    var status: DeviceStatus
    var registeredAt: Date
    var lastSeenAt: Date?

    enum DeviceStatus: String, Codable {
        case active = "active"
        case revoked = "revoked"
    }

    // MARK: - Database

    static let databaseTableName = "devices"

    enum Columns {
        static let deviceId = Column("device_id")
        static let ownerDID = Column("owner_did")
        static let deviceName = Column("device_name")
        static let pubkeyX25519 = Column("pubkey_x25519")
        static let pubkeyEd25519 = Column("pubkey_ed25519")
        static let status = Column("status")
        static let registeredAt = Column("registered_at")
        static let lastSeenAt = Column("last_seen_at")
    }

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case ownerDID = "owner_did"
        case deviceName = "device_name"
        case pubkeyX25519 = "pubkey_x25519"
        case pubkeyEd25519 = "pubkey_ed25519"
        case status
        case registeredAt = "registered_at"
        case lastSeenAt = "last_seen_at"
    }
}
