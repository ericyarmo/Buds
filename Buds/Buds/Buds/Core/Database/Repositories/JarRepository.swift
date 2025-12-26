//
//  JarRepository.swift
//  Buds
//
//  CRUD operations for jars and jar members
//

import Foundation
import GRDB
import CryptoKit

final class JarRepository {
    static let shared = JarRepository()

    private init() {}

    // MARK: - Jar CRUD

    func getAllJars() async throws -> [Jar] {
        try await Database.shared.readAsync { db in
            try Jar.fetchAll(db)
        }
    }

    func getJar(id: String) async throws -> Jar? {
        try await Database.shared.readAsync { db in
            try Jar.fetchOne(db, key: id)
        }
    }

    func createJar(name: String, description: String?, ownerDID: String) async throws -> Jar {
        let jar = Jar(
            id: UUID().uuidString,
            name: name,
            description: description,
            ownerDID: ownerDID,
            createdAt: Date(),
            updatedAt: Date()
        )

        // Get current device's X25519 key
        let x25519Key = try await IdentityManager.shared.getX25519Keypair()

        try await Database.shared.writeAsync { db in
            try jar.insert(db)

            // Add owner as first member
            let owner = JarMember(
                jarID: jar.id,
                memberDID: ownerDID,
                displayName: "You",
                phoneNumber: nil,
                avatarCID: nil,
                pubkeyX25519: x25519Key.publicKey.rawRepresentation.base64EncodedString(),
                role: .owner,
                status: .active,
                joinedAt: Date(),
                invitedAt: nil,
                removedAt: nil,
                createdAt: Date(),
                updatedAt: Date()
            )
            try owner.insert(db)
        }

        return jar
    }

    func deleteJar(id: String) async throws {
        try await Database.shared.writeAsync { db in
            try Jar.deleteOne(db, key: id)
        }
    }

    // MARK: - Jar Members CRUD

    func getMembers(jarID: String) async throws -> [JarMember] {
        try await Database.shared.readAsync { db in
            try JarMember
                .filter(Column("jar_id") == jarID)
                .filter(Column("status") == "active")
                .fetchAll(db)
        }
    }

    func addMember(
        jarID: String,
        memberDID: String,
        displayName: String,
        phoneNumber: String?,
        pubkeyX25519: String
    ) async throws {
        let member = JarMember(
            jarID: jarID,
            memberDID: memberDID,
            displayName: displayName,
            phoneNumber: phoneNumber,
            avatarCID: nil,
            pubkeyX25519: pubkeyX25519,
            role: .member,
            status: .active,
            joinedAt: Date(),
            invitedAt: Date(),
            removedAt: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        try await Database.shared.writeAsync { db in
            try member.insert(db)
        }
    }

    func removeMember(jarID: String, memberDID: String) async throws {
        try await Database.shared.writeAsync { db in
            try db.execute(
                sql: """
                    UPDATE jar_members
                    SET status = 'removed', removed_at = ?, updated_at = ?
                    WHERE jar_id = ? AND member_did = ?
                """,
                arguments: [Date().timeIntervalSince1970, Date().timeIntervalSince1970, jarID, memberDID]
            )
        }
    }

    // MARK: - Helper: Get jars where user is a member

    func getJarsForUser(did: String) async throws -> [Jar] {
        try await Database.shared.readAsync { db in
            try Jar
                .joining(required: Jar.members.filter(Column("member_did") == did && Column("status") == "active"))
                .fetchAll(db)
        }
    }
}
