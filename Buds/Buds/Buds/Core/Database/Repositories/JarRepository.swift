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

    // Phase 10.1 Module 2.1: Update jar metadata
    func updateJar(jarID: String, name: String, description: String?) async throws {
        try await Database.shared.writeAsync { db in
            try db.execute(
                sql: """
                    UPDATE jars
                    SET name = ?, description = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [name, description, Date().timeIntervalSince1970, jarID]
            )
        }
    }

    /// Safe jar deletion: moves memories to Solo jar, deletes members, then deletes jar
    /// CRITICAL: Solo jar cannot be deleted (system jar)
    func deleteJar(id: String) async throws {
        let db = Database.shared

        // 1. Get jar to verify it exists and check if it's Solo
        guard let jar = try await getJar(id: id) else {
            throw JarError.jarNotFound
        }

        // 2. Prevent Solo jar deletion
        let isSolo = jar.name.trimmingCharacters(in: .whitespaces).lowercased() == "solo"
        guard !isSolo else {
            throw JarError.cannotDeleteSoloJar
        }

        // 3. Get Solo jar ID for memory reassignment
        let allJars = try await getAllJars()
        guard let soloJar = allJars.first(where: {
            $0.name.trimmingCharacters(in: .whitespaces).lowercased() == "solo"
        }) else {
            throw JarError.soloJarNotFound
        }

        // 4. Move all memories from this jar to Solo jar
        try await db.writeAsync { db in
            let movedCount = try db.execute(
                sql: "UPDATE local_receipts SET jar_id = ? WHERE jar_id = ?",
                arguments: [soloJar.id, id]
            )
            print("📦 Moved \(movedCount) memories from \(jar.name) to Solo")
        }

        // 5. Delete all jar members (just associations, not the users themselves)
        try await db.writeAsync { db in
            let deletedMembers = try db.execute(
                sql: "DELETE FROM jar_members WHERE jar_id = ?",
                arguments: [id]
            )
            print("👥 Deleted \(deletedMembers) member associations")
        }

        // 6. Delete the jar itself
        try await db.writeAsync { db in
            try Jar.deleteOne(db, key: id)
        }

        print("✅ Deleted jar '\(jar.name)' (id: \(id))")
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
