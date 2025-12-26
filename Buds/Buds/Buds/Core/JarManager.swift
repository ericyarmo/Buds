//
//  JarManager.swift
//  Buds
//
//  Manages jars and jar members (renamed from CircleManager in Phase 8)
//

import Foundation
import GRDB
import Combine

@MainActor
class JarManager: ObservableObject {
    static let shared = JarManager()

    @Published var jars: [Jar] = []
    @Published var isLoading = false

    private let maxJarSize = 12

    private init() {
        Task {
            await loadJars()
        }
    }

    // MARK: - Jar Operations

    func loadJars() async {
        isLoading = true

        do {
            let loadedJars = try await JarRepository.shared.getAllJars()
            jars = loadedJars
            print("✅ Loaded \(jars.count) jars")
        } catch {
            print("❌ Failed to load jars: \(error)")
        }

        isLoading = false
    }

    func createJar(name: String, description: String? = nil) async throws -> Jar {
        let currentDID = try await IdentityManager.shared.currentDID

        let jar = try await JarRepository.shared.createJar(
            name: name,
            description: description,
            ownerDID: currentDID
        )

        await loadJars()
        print("✅ Created jar: \(name)")
        return jar
    }

    func deleteJar(id: String) async throws {
        try await JarRepository.shared.deleteJar(id: id)
        await loadJars()
        print("✅ Deleted jar: \(id)")
    }

    // MARK: - Member Operations

    func getMembers(jarID: String) async throws -> [JarMember] {
        try await JarRepository.shared.getMembers(jarID: jarID)
    }

    func addMember(jarID: String, phoneNumber: String, displayName: String) async throws {
        let currentMembers = try await getMembers(jarID: jarID)
        guard currentMembers.count < maxJarSize else {
            throw JarError.jarFull
        }

        // Look up real DID from relay
        let did = try await RelayClient.shared.lookupDID(phoneNumber: phoneNumber)
        let devices = try await DeviceManager.shared.getDevices(for: [did])
        guard let firstDevice = devices.first else {
            throw JarError.userNotRegistered
        }

        try await JarRepository.shared.addMember(
            jarID: jarID,
            memberDID: did,
            displayName: displayName,
            phoneNumber: phoneNumber,
            pubkeyX25519: firstDevice.pubkeyX25519
        )

        print("✅ Added jar member: \(displayName) to jar \(jarID)")
    }

    func removeMember(jarID: String, memberDID: String) async throws {
        try await JarRepository.shared.removeMember(jarID: jarID, memberDID: memberDID)
        print("✅ Removed jar member: \(memberDID) from jar \(jarID)")
    }

    // MARK: - TOFU Key Pinning (Phase 7)

    /// Get pinned Ed25519 public key for a jar member (TOFU: Trust On First Use)
    /// SECURITY: Returns locally-cached Ed25519 key from when member was added
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

enum JarError: Error, LocalizedError {
    case noIdentity
    case jarFull
    case memberNotFound
    case invalidPhoneNumber
    case userNotFound
    case userNotRegistered

    var errorDescription: String? {
        switch self {
        case .noIdentity:
            return "No identity found. Please sign in first."
        case .jarFull:
            return "This jar is full (max 12 members)"
        case .memberNotFound:
            return "Jar member not found"
        case .invalidPhoneNumber:
            return "Invalid phone number"
        case .userNotFound:
            return "User not found on Buds"
        case .userNotRegistered:
            return "User hasn't registered with Buds yet"
        }
    }
}
