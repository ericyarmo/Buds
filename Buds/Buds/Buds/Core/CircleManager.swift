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

        // TODO: Phase 6 - Look up DID via Firebase/Relay
        // For now, create a placeholder
        let placeholderDID = "did:buds:placeholder_\(UUID().uuidString.prefix(8))"
        let placeholderPubkey = Data(repeating: 0, count: 32).base64EncodedString()

        let member = CircleMember(
            id: UUID().uuidString,
            did: placeholderDID,
            displayName: displayName,
            phoneNumber: phoneNumber,
            avatarCID: nil,
            pubkeyX25519: placeholderPubkey,
            status: .pending,
            joinedAt: nil,
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
        print("✅ Added Circle member: \(displayName)")
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

    var errorDescription: String? {
        switch self {
        case .circleFull:
            return "Your Circle is full (max 12 members)"
        case .memberNotFound:
            return "Circle member not found"
        case .invalidPhoneNumber:
            return "Invalid phone number"
        }
    }
}
