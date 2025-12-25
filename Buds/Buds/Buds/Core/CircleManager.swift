//
//  CircleManager.swift
//  Buds
//
//  Manages Circle (friends) operations
//

import Foundation
import GRDB
import Combine

@MainActor
class CircleManager: ObservableObject {
    static let shared = CircleManager()

    @Published var members: [CircleMember] = []
    @Published var isLoading = false

    private let maxCircleSize = 12

    private init() {
        Task {
            await loadMembers()
        }
    }

    // MARK: - Load Members

    func loadMembers() async {
        isLoading = true

        do {
            let db = Database.shared
            let fetchedMembers = try await db.readAsync { db in
                try CircleMember
                    .filter(CircleMember.Columns.status != "removed")
                    .order(CircleMember.Columns.displayName)
                    .fetchAll(db)
            }

            members = fetchedMembers
            print("✅ Loaded \(members.count) Circle members")
        } catch {
            print("❌ Failed to load Circle members: \(error)")
        }

        isLoading = false
    }

    // MARK: - Add Member

    func addMember(phoneNumber: String, displayName: String) async throws {
        guard members.count < maxCircleSize else {
            throw CircleError.circleFull
        }

        // Look up real DID from relay
        let did = try await RelayClient.shared.lookupDID(phoneNumber: phoneNumber)
        let devices = try await DeviceManager.shared.getDevices(for: [did])
        guard let firstDevice = devices.first else {
            throw CircleError.userNotRegistered
        }

        let member = CircleMember(
            id: UUID().uuidString,
            did: did,
            displayName: displayName,
            phoneNumber: phoneNumber,
            avatarCID: nil,
            pubkeyX25519: firstDevice.pubkeyX25519,
            status: .active,
            joinedAt: Date(),
            invitedAt: Date(),
            removedAt: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        let db = Database.shared
        try await db.writeAsync { db in
            try member.insert(db)
        }

        await loadMembers()
        print("✅ Added Circle member: \(displayName) (DID: \(did))")
    }

    // MARK: - Remove Member

    func removeMember(_ member: CircleMember) async throws {
        var updatedMember = member
        updatedMember.status = .removed
        updatedMember.removedAt = Date()
        updatedMember.updatedAt = Date()

        let db = Database.shared
        try await db.writeAsync { db in
            try updatedMember.update(db)
        }

        await loadMembers()
        print("✅ Removed Circle member: \(member.displayName)")
    }

    // MARK: - Update Member

    func updateMemberName(_ member: CircleMember, newName: String) async throws {
        var updatedMember = member
        updatedMember.displayName = newName
        updatedMember.updatedAt = Date()

        let db = Database.shared
        try await db.writeAsync { db in
            try updatedMember.update(db)
        }

        await loadMembers()
        print("✅ Updated Circle member: \(newName)")
    }

    // MARK: - TOFU Key Pinning (Phase 7)

    /// Get pinned Ed25519 public key for a Circle member (TOFU: Trust On First Use)
    /// SECURITY: Returns locally-cached Ed25519 key from when member was added to Circle
    /// This prevents the relay from swapping keys in transit
    func getPinnedEd25519PublicKey(for did: String) async throws -> Data? {
        let db = Database.shared

        // Query devices table for this DID (stored when device was registered)
        let device = try await db.readAsync { db in
            try Device
                .filter(Device.Columns.ownerDID == did)
                .filter(Device.Columns.status == "active")
                .order(Device.Columns.registeredAt.desc) // Most recent device
                .fetchOne(db)
        }

        guard let device = device,
              let pubkeyData = Data(base64Encoded: device.pubkeyEd25519) else {
            print("❌ No pinned Ed25519 key for DID: \(did)")
            return nil
        }

        print("🔐 TOFU: Using pinned Ed25519 key for \(did)")
        return pubkeyData
    }

    /// Get pinned Ed25519 public key for a specific device (TOFU: Trust On First Use)
    /// SECURITY: Returns device-specific Ed25519 key, preventing key confusion attacks
    /// Use this method when you have both DID and deviceId from the message metadata
    func getPinnedEd25519PublicKey(did: String, deviceId: String) async throws -> Data? {
        let db = Database.shared

        // Query devices table for this specific device
        let device = try await db.readAsync { db in
            try Device
                .filter(Device.Columns.ownerDID == did)
                .filter(Device.Columns.deviceId == deviceId)
                .filter(Device.Columns.status == "active")
                .fetchOne(db)
        }

        guard let device = device,
              let pubkeyData = Data(base64Encoded: device.pubkeyEd25519) else {
            print("❌ No pinned Ed25519 key for device: \(deviceId) (DID: \(did))")
            return nil
        }

        print("🔐 TOFU: Using device-specific pinned Ed25519 key for \(deviceId)")
        return pubkeyData
    }
}

// MARK: - Errors

enum CircleError: Error, LocalizedError {
    case circleFull
    case memberNotFound
    case invalidPhoneNumber
    case userNotFound
    case userNotRegistered

    var errorDescription: String? {
        switch self {
        case .circleFull:
            return "Your Circle is full (max 12 members)"
        case .memberNotFound:
            return "Circle member not found"
        case .invalidPhoneNumber:
            return "Invalid phone number"
        case .userNotFound:
            return "User not found on Buds"
        case .userNotRegistered:
            return "User hasn't registered with Buds yet"
        }
    }
}
