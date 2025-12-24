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
