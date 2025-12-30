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
    @Published var jarStats: [String: JarStats] = [:]  // Phase 9b: Stats cache
    @Published var isLoading = false

    private let maxJarSize = 12

    private init() {
        Task {
            await loadJars()
        }
    }

    // MARK: - Jar Operations

    /// TIER 1: Full reload (jar create/delete, member changes, inbox receive)
    /// Phase 10 Step 3: Split refresh logic for performance
    func refreshGlobal() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Parallel fetch: jars + stats (Phase 9b optimization)
            async let jarsResult = JarRepository.shared.getAllJars()
            async let statsResult = MemoryRepository().fetchAllJarStats()

            let (loadedJars, loadedStats) = try await (jarsResult, statsResult)

            self.jars = loadedJars
            self.jarStats = loadedStats

            print("✅ Global refresh: \(jars.count) jars")
        } catch {
            print("❌ Failed global refresh: \(error)")
        }
    }

    /// TIER 2: Lightweight (bud create/delete, single jar affected)
    /// Phase 10 Step 3: Only updates stats for one jar
    func refreshJar(_ jarID: String) async {
        do {
            // Only update stats for this one jar
            let allStats = try await MemoryRepository().fetchAllJarStats()

            if let updatedStat = allStats[jarID] {
                self.jarStats[jarID] = updatedStat
            } else {
                // Jar might be empty now
                self.jarStats[jarID] = JarStats(
                    jarID: jarID,
                    totalBuds: 0,
                    recentBuds: 0,
                    lastCreatedAt: nil
                )
            }

            print("✅ Refreshed jar: \(jarID)")
        } catch {
            print("❌ Failed to refresh jar: \(error)")
        }
    }

    /// Backward compatibility: keep loadJars() as alias to refreshGlobal()
    /// TODO: Remove after updating all call sites
    func loadJars() async {
        await refreshGlobal()
    }

    func createJar(name: String, description: String? = nil) async throws -> Jar {
        let currentDID = try await IdentityManager.shared.currentDID

        let jar = try await JarRepository.shared.createJar(
            name: name,
            description: description,
            ownerDID: currentDID
        )

        // Phase 10 Step 3: Structural change requires global refresh
        await refreshGlobal()
        print("✅ Created jar: \(name)")
        return jar
    }

    // Phase 10.1 Module 2.1: Update jar
    func updateJar(jarID: String, name: String, description: String? = nil) async throws {
        try await JarRepository.shared.updateJar(
            jarID: jarID,
            name: name,
            description: description
        )

        // Metadata change only - refresh global to update UI
        await refreshGlobal()
        print("✅ Updated jar: \(name)")
    }

    func deleteJar(id: String) async throws {
        try await JarRepository.shared.deleteJar(id: id)
        // Phase 10 Step 3: Structural change requires global refresh
        await refreshGlobal()
        print("✅ Deleted jar: \(id)")
    }

    /// Ensure Solo jar exists (for fresh installs)
    /// CRITICAL: Must be called after auth to avoid crash on fresh install
    func ensureSoloJarExists() async throws {
        let jars = try await JarRepository.shared.getAllJars()

        print("🔍 [JarManager] Checking for Solo jar... Found \(jars.count) total jars")
        for jar in jars {
            print("🔍 [JarManager] Jar: '\(jar.name)' (id: \(jar.id))")
        }

        // Case-insensitive check with trimming
        let hasSoloJar = jars.contains { jar in
            jar.name.trimmingCharacters(in: .whitespaces).lowercased() == "solo"
        }

        if hasSoloJar {
            print("✅ Solo jar already exists")
            return
        }

        print("⚠️ No Solo jar found - creating one")
        let currentDID = try await IdentityManager.shared.currentDID

        _ = try await JarRepository.shared.createJar(
            name: "Solo",
            description: "Your private buds",
            ownerDID: currentDID
        )

        await refreshGlobal()
        print("✅ Created Solo jar for fresh install")
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

        // 1. Look up real DID from relay
        let did = try await RelayClient.shared.lookupDID(phoneNumber: phoneNumber)

        // 2. Get ALL devices for this DID (not just first one)
        let devices = try await DeviceManager.shared.getDevices(for: [did])
        guard !devices.isEmpty else {
            throw JarError.userNotRegistered
        }

        // 3. Store ALL devices in local devices table (TOFU key pinning)
        // CRITICAL: This prevents "senderDeviceNotPinned" errors when receiving messages
        for device in devices {
            try await Database.shared.writeAsync { db in
                // Check if device already exists
                let exists = try Device
                    .filter(Device.Columns.deviceId == device.deviceId)
                    .fetchCount(db) > 0

                if !exists {
                    try device.insert(db)
                    print("🔐 Pinned device \(device.deviceId) for \(did)")
                }
            }
        }

        // 4. Add member to jar (use first device's X25519 key for jar_members table)
        let firstDevice = devices[0]
        try await JarRepository.shared.addMember(
            jarID: jarID,
            memberDID: did,
            displayName: displayName,
            phoneNumber: phoneNumber,
            pubkeyX25519: firstDevice.pubkeyX25519
        )

        print("✅ Added jar member: \(displayName) to jar \(jarID) with \(devices.count) devices pinned")
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
    case jarNotFound
    case cannotDeleteSoloJar
    case soloJarNotFound

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
        case .jarNotFound:
            return "Jar not found"
        case .cannotDeleteSoloJar:
            return "Cannot delete Solo jar (system jar)"
        case .soloJarNotFound:
            return "Solo jar not found. Please reinstall the app."
        }
    }
}
