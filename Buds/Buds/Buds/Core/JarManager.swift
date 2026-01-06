//
//  JarManager.swift
//  Buds
//
//  Manages jars and jar members (renamed from CircleManager in Phase 8)
//

import Foundation
import GRDB
import Combine
import CryptoKit  // Phase 10.3 Module 0.5: For safety number generation

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
        print("🆕 [Module 5b] Creating jar: \(name)")

        let ownerDID = try await IdentityManager.shared.currentDID
        let jarID = UUID().uuidString

        // 1. Create jar locally (optimistic - before relay confirms)
        let jar = try await JarRepository.shared.createJar(
            id: jarID,
            name: name,
            description: description,
            ownerDID: ownerDID,
            lastSequenceNumber: 0,  // Will be updated after relay assigns
            parentCID: nil          // Root receipt has no parent
        )

        print("✅ Jar created locally: \(jarID)")

        // 2. Generate jar.created receipt payload
        let payloadCBOR = try ReceiptCanonicalizer.encodeJarCreatedPayload(
            jarName: name,
            jarDescription: description,
            ownerDID: ownerDID,
            createdAtMs: Int64(Date().timeIntervalSince1970 * 1000)
        )

        // 3. Wrap in jar receipt envelope (NO sequence, NO parent_cid)
        let receiptCBOR = try ReceiptCanonicalizer.encodeJarReceiptPayload(
            jarID: jarID,
            receiptType: "jar.created",
            senderDID: ownerDID,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            parentCID: nil,  // Root receipt
            payload: payloadCBOR
        )

        // 4. Compute CID + sign
        let receiptCID = CanonicalCBOREncoder.computeCID(from: receiptCBOR)
        let signature = try await IdentityManager.shared.sign(data: receiptCBOR)

        print("📝 Receipt CID: \(receiptCID)")

        // 5. Send to relay → relay assigns sequence (likely seq=1)
        let response = try await RelayClient.shared.storeJarReceipt(
            jarID: jarID,
            receiptData: receiptCBOR,
            signature: signature,
            parentCID: nil
        )

        print("✅ Relay assigned sequence: \(response.sequenceNumber)")

        // CRITICAL: Assert local CID matches relay CID (corruption detection)
        guard receiptCID == response.receiptCID else {
            print("🚨 [CORRUPTION] Local CID: \(receiptCID)")
            print("🚨 [CORRUPTION] Relay CID: \(response.receiptCID)")
            throw JarError.cidMismatch(local: receiptCID, relay: response.receiptCID)
        }

        // 6. Update jar with relay-assigned sequence
        try await JarRepository.shared.updateLastSequence(jarID, response.sequenceNumber)
        try await JarRepository.shared.updateParentCID(jarID, receiptCID)

        // 7. Add owner to jar_members (active)
        try await Database.shared.writeAsync { db in
            try db.execute(sql: """
                INSERT INTO jar_members (jar_id, did, role, status, added_at)
                VALUES (?, ?, 'owner', 'active', ?)
            """, arguments: [jarID, ownerDID, Date().timeIntervalSince1970])
        }

        print("🎉 Jar created and synced: \(name)")

        // Phase 10 Step 3: Structural change requires global refresh
        await refreshGlobal()

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
        print("🆕 [Module 6] Adding member: \(displayName) to jar \(jarID)")

        let currentMembers = try await getMembers(jarID: jarID)
        guard currentMembers.count < maxJarSize else {
            throw JarError.jarFull
        }

        let ownerDID = try await IdentityManager.shared.currentDID

        // 1. Look up real DID from relay
        let memberDID = try await RelayClient.shared.lookupDID(phoneNumber: phoneNumber)

        // 2. Get ALL devices for this DID (not just first one)
        let devices = try await DeviceManager.shared.getDevices(for: [memberDID])
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
                    print("🔐 Pinned device \(device.deviceId) for \(memberDID)")
                }
            }
        }

        // 4. Convert Device objects to DeviceInfo for receipt payload
        let deviceInfos = devices.map { device in
            DeviceInfo(
                deviceId: device.deviceId,
                pubkeyEd25519: device.pubkeyEd25519,
                pubkeyX25519: device.pubkeyX25519
            )
        }

        // 5. Generate jar.member_added receipt payload
        let payload = JarMemberAddedPayload(
            memberDID: memberDID,
            memberDisplayName: displayName,
            memberPhoneNumber: phoneNumber,
            memberDevices: deviceInfos,
            addedByDID: ownerDID,
            addedAtMs: Int64(Date().timeIntervalSince1970 * 1000)
        )
        let payloadCBOR = try ReceiptCanonicalizer.encodeJarMemberAddedPayload(payload)

        // 6. Get jar's current parent CID for causal chain
        let jar = try await JarRepository.shared.getJar(id: jarID)
        guard let jar = jar else {
            throw JarError.jarNotFound
        }

        // 7. Wrap in jar receipt envelope (NO sequence)
        let receiptCBOR = try ReceiptCanonicalizer.encodeJarReceiptPayload(
            jarID: jarID,
            receiptType: "jar.member_added",
            senderDID: ownerDID,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            parentCID: jar.parentCID,
            payload: payloadCBOR
        )

        // 8. Compute CID + sign
        let receiptCID = CanonicalCBOREncoder.computeCID(from: receiptCBOR)
        let signature = try await IdentityManager.shared.sign(data: receiptCBOR)

        print("📝 Receipt CID: \(receiptCID)")

        // 9. Send to relay → relay assigns sequence + broadcasts
        let response = try await RelayClient.shared.storeJarReceipt(
            jarID: jarID,
            receiptData: receiptCBOR,
            signature: signature,
            parentCID: jar.parentCID
        )

        print("✅ Relay assigned sequence: \(response.sequenceNumber)")

        // CRITICAL: Assert local CID matches relay CID (corruption detection)
        guard receiptCID == response.receiptCID else {
            print("🚨 [CORRUPTION] Local CID: \(receiptCID)")
            print("🚨 [CORRUPTION] Relay CID: \(response.receiptCID)")
            throw JarError.cidMismatch(local: receiptCID, relay: response.receiptCID)
        }

        // 10. Update jar with relay-assigned sequence
        try await JarRepository.shared.updateLastSequence(jarID, response.sequenceNumber)
        try await JarRepository.shared.updateParentCID(jarID, receiptCID)

        print("🎉 Member added and synced: \(displayName) (\(devices.count) devices)")

        // Phase 10 Step 3: Structural change requires global refresh
        await refreshGlobal()
    }

    func removeMember(jarID: String, memberDID: String) async throws {
        try await JarRepository.shared.removeMember(jarID: jarID, memberDID: memberDID)
        print("✅ Removed jar member: \(memberDID) from jar \(jarID)")
    }

    // MARK: - Invite Flow (Module 6)

    /// Accept an invite to join a jar
    /// Generates jar.invite_accepted receipt → relay broadcasts to all jar members
    func acceptInvite(jarID: String) async throws {
        print("✅ [Module 6] Accepting invite for jar: \(jarID)")

        let myDID = try await IdentityManager.shared.currentDID

        // 1. Verify invite exists and is pending
        let member = try await Database.shared.readAsync { db in
            try JarMember
                .filter(JarMember.Columns.jarID == jarID)
                .filter(JarMember.Columns.memberDID == myDID)
                .filter(JarMember.Columns.status == "pending")
                .fetchOne(db)
        }

        guard member != nil else {
            throw JarError.inviteNotFound
        }

        // 2. Generate jar.invite_accepted receipt payload
        let payload = JarInviteAcceptedPayload(
            memberDID: myDID,
            acceptedAtMs: Int64(Date().timeIntervalSince1970 * 1000)
        )
        let payloadCBOR = try ReceiptCanonicalizer.encodeJarInviteAcceptedPayload(payload)

        // 3. Get jar's current parent CID for causal chain
        let jar = try await JarRepository.shared.getJar(id: jarID)
        guard let jar = jar else {
            throw JarError.jarNotFound
        }

        // 4. Wrap in jar receipt envelope (NO sequence)
        let receiptCBOR = try ReceiptCanonicalizer.encodeJarReceiptPayload(
            jarID: jarID,
            receiptType: "jar.invite_accepted",
            senderDID: myDID,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            parentCID: jar.parentCID,
            payload: payloadCBOR
        )

        // 5. Compute CID + sign
        let receiptCID = CanonicalCBOREncoder.computeCID(from: receiptCBOR)
        let signature = try await IdentityManager.shared.sign(data: receiptCBOR)

        print("📝 Receipt CID: \(receiptCID)")

        // 6. Send to relay → relay assigns sequence + broadcasts
        let response = try await RelayClient.shared.storeJarReceipt(
            jarID: jarID,
            receiptData: receiptCBOR,
            signature: signature,
            parentCID: jar.parentCID
        )

        print("✅ Relay assigned sequence: \(response.sequenceNumber)")

        // CRITICAL: Assert local CID matches relay CID (corruption detection)
        guard receiptCID == response.receiptCID else {
            print("🚨 [CORRUPTION] Local CID: \(receiptCID)")
            print("🚨 [CORRUPTION] Relay CID: \(response.receiptCID)")
            throw JarError.cidMismatch(local: receiptCID, relay: response.receiptCID)
        }

        // 7. Update jar with relay-assigned sequence
        try await JarRepository.shared.updateLastSequence(jarID, response.sequenceNumber)
        try await JarRepository.shared.updateParentCID(jarID, receiptCID)

        print("🎉 Invite accepted for jar: \(jarID)")

        // Phase 10 Step 3: Structural change requires global refresh
        await refreshGlobal()
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

    // MARK: - Safety Number (Phase 10.3 Module 0.5)

    /// Generate safety number for TOFU verification
    /// Both parties compute the same hash for comparison
    func generateSafetyNumber(memberDID: String) async throws -> (safetyNumber: String, deviceCount: Int) {
        let myDID = try await IdentityManager.shared.currentDID

        // Get all devices for this member
        let devices = try await Database.shared.readAsync { db in
            try Device
                .filter(Device.Columns.ownerDID == memberDID)
                .filter(Device.Columns.status == "active")
                .fetchAll(db)
        }

        guard !devices.isEmpty else {
            throw JarError.userNotRegistered
        }

        // CRITICAL: Canonical DID ordering (both parties must compute same hash)
        let orderedDIDs = [myDID, memberDID].sorted().joined()

        // CRITICAL: Deterministic device ordering (prevents array order mismatch)
        let sortedDevices = devices.sorted { $0.deviceId < $1.deviceId }
        let deviceKeys = sortedDevices.map { $0.pubkeyEd25519 }.joined()

        // Compute hash
        let combined = orderedDIDs + deviceKeys
        guard let combinedData = combined.data(using: .utf8) else {
            throw JarError.invalidPhoneNumber
        }

        let hash = CryptoKit.SHA256.hash(data: combinedData)

        // Convert hash to Data, then take first 30 bytes (240 bits)
        let hashData = Data(hash)
        let truncatedHash = hashData.prefix(30)

        // Format as groups: "12345 67890 12345 67890 12345 67890"
        let safetyNumber = formatAsGroups(truncatedHash)

        return (safetyNumber, devices.count)
    }

    private func formatAsGroups(_ hashBytes: Data) -> String {
        let hexString = hashBytes.map { String(format: "%02x", $0) }.joined()

        // Group into 5-digit chunks for readability
        return stride(from: 0, to: hexString.count, by: 5)
            .map { i -> String in
                let start = hexString.index(hexString.startIndex, offsetBy: i)
                let end = hexString.index(start, offsetBy: min(5, hexString.count - i))
                return String(hexString[start..<end])
            }
            .joined(separator: " ")
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
    case inviteNotFound                             // Module 6: Invite acceptance
    case cidMismatch(local: String, relay: String)  // Module 5b: Corruption detection

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
        case .inviteNotFound:
            return "No pending invite found for this jar"
        case .cidMismatch(let local, let relay):
            return "CID mismatch: local=\(local), relay=\(relay)"
        }
    }
}
