//
//  InboxManager.swift
//  Buds
//
//  Phase 7: Message inbox polling and processing
//

import Foundation
import Combine
import CryptoKit
import GRDB  // Phase 10.3 Module 0.4: For device insertion

actor InboxManager {
    static let shared = InboxManager()

    private var pollTask: Task<Void, Never>?
    private var isPolling = false

    private init() {}

    // Start foreground polling (30s interval)
    func startForegroundPolling() {
        guard pollTask == nil else { return }

        pollTask = Task {
            // Poll immediately
            await pollInbox()

            // Continue polling every 30 seconds
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                await pollInbox()
            }
        }
    }

    func stopForegroundPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // Poll inbox for new messages
    func pollInbox() async {
        guard !isPolling else { return }
        isPolling = true
        defer { isPolling = false }

        do {
            // ═══════════════════════════════════════════════════════
            // EXISTING: Poll bud receipts (keep unchanged)
            // ═══════════════════════════════════════════════════════

            // Get authenticated user's DID
            let did = try await IdentityManager.shared.currentDID

            // Fetch messages from relay
            let messages = try await RelayClient.shared.getInbox(for: did)

            if !messages.isEmpty {
                print("📬 Received \(messages.count) messages")

                // Decrypt and store each message
                for message in messages {
                    do {
                        try await processMessage(message)
                    } catch {
                        print("❌ Failed to process message \(message.messageId): \(error)")
                    }
                }

                // Notify UI to refresh
                await MainActor.run {
                    NotificationCenter.default.post(name: .inboxUpdated, object: nil)
                }
            }

            // ═══════════════════════════════════════════════════════
            // NEW: Poll jar receipts (Module 5a)
            // ═══════════════════════════════════════════════════════

            await pollJarReceipts()

        } catch {
            print("❌ Inbox poll failed: \(error)")
        }
    }

    // MARK: - Jar Polling (Module 5a)

    /// Poll jar receipts for all active jars
    private func pollJarReceipts() async {
        do {
            // Phase 10.3 Module 6.5: Discover new jars before polling
            await discoverNewJars()

            // Get sync targets from JarSyncManager (clean interface)
            let targets = try await JarSyncManager.shared.getSyncTargets()

            guard !targets.isEmpty else {
                print("📭 No active jars to sync")
                return
            }

            print("📡 [JAR_SYNC] Polling \(targets.count) active jars...")

            // Poll each jar independently
            for target in targets {
                do {
                    try await pollJar(target)
                } catch {
                    let jarPrefix = String(target.jarID.prefix(8))
                    print("❌ [JAR_SYNC] Failed to poll jar \(jarPrefix)...: \(error)")
                    // Continue polling other jars (isolation)
                }
            }

        } catch {
            print("❌ [JAR_SYNC] Failed to get sync targets: \(error)")
        }
    }

    /// Discover new jars the user has been added to (Phase 10.3 Module 6.5)
    private func discoverNewJars() async {
        do {
            // Call /api/jars/list to get all jars where user is a member
            let remoteJars = try await RelayClient.shared.listUserJars()

            guard !remoteJars.isEmpty else {
                return
            }

            print("🔍 Discovered \(remoteJars.count) jars from relay")

            // Get local jars
            let localJars = try await JarRepository.shared.getAllJars()
            let localJarIds = Set(localJars.map { $0.id })

            // Find new jars (not in local database)
            let newJars = remoteJars.filter { !localJarIds.contains($0.jarId) }

            guard !newJars.isEmpty else {
                print("✅ All jars already synced locally")
                return
            }

            print("🆕 Found \(newJars.count) new jars to sync")

            // For each new jar, create local record and fetch receipts from sequence 0
            for remoteJar in newJars {
                do {
                    let jarPrefix = String(remoteJar.jarId.prefix(8))
                    print("📥 Syncing new jar \(jarPrefix)... (role: \(remoteJar.role))")

                    // Fetch all receipts from sequence 0
                    let envelopes = try await RelayClient.shared.getJarReceipts(
                        jarID: remoteJar.jarId,
                        after: 0,
                        limit: 100
                    )

                    guard !envelopes.isEmpty else {
                        print("⚠️  Jar \(jarPrefix) has no receipts yet")
                        continue
                    }

                    // Apply receipts to create jar locally (skipGapDetection = true for initial sync)
                    for envelope in envelopes {
                        try await JarSyncManager.shared.processEnvelope(envelope, skipGapDetection: true)
                    }

                    print("✅ Synced jar \(jarPrefix) with \(envelopes.count) receipts")

                } catch {
                    print("❌ Failed to sync new jar \(remoteJar.jarId): \(error)")
                    // Continue with other jars
                }
            }

        } catch {
            print("❌ Jar discovery failed: \(error)")
            // Non-fatal - continue with normal polling
        }
    }

    /// Poll receipts for a single jar
    private func pollJar(_ target: JarSyncTarget) async throws {
        let jarPrefix = String(target.jarID.prefix(8))

        // CRITICAL FIX 3: Skip halted jars (avoid spam during backfill)
        guard !target.isHalted else {
            print("⏸️  [JAR_SYNC] Skipping halted jar \(jarPrefix)...")
            return
        }

        print("📡 [JAR_SYNC] Polling jar \(jarPrefix)... (after seq=\(target.lastSequenceNumber))")

        // Fetch new receipts from relay (using ?after= API)
        let envelopes: [RelayEnvelope]
        do {
            envelopes = try await RelayClient.shared.getJarReceipts(
                jarID: target.jarID,
                after: target.lastSequenceNumber,
                limit: 100
            )
        } catch let error as RelayError {
            // CRITICAL FIX 3: Handle 403 gracefully (don't spam every 30s)
            if case .httpError(let statusCode, _) = error, statusCode == 403 {
                print("🚫 [JAR_SYNC] Not a member of jar \(jarPrefix), halting polling")
                // Mark jar as halted due to membership revocation
                try await JarSyncManager.shared.haltJar(
                    jarID: target.jarID,
                    reason: "Not a member (HTTP 403)"
                )
                return
            }
            throw error
        }

        guard !envelopes.isEmpty else {
            print("📭 [JAR_SYNC] No new receipts for \(jarPrefix)")
            return
        }

        print("📬 [JAR_SYNC] Received \(envelopes.count) receipts for \(jarPrefix)")

        // Process batch (JarSyncManager handles sorting, deduping, gap detection)
        try await JarSyncManager.shared.processEnvelopes(for: target.jarID, envelopes)

        // Notify UI to refresh jar
        await MainActor.run {
            NotificationCenter.default.post(
                name: .jarUpdated,
                object: nil,
                userInfo: ["jar_id": target.jarID]
            )
        }
    }

    // Process and decrypt a single message
    private func processMessage(_ message: EncryptedMessage) async throws {
        print("📥 [INBOX] Processing message \(message.messageId)")
        print("📥 [INBOX] Sender: \(message.senderDID)")
        print("📥 [INBOX] Receipt CID: \(message.receiptCID)")

        // Decrypt and verify sender is in Circle
        let rawCBOR = try await decryptAndVerify(message)

        // Decode receipt to determine type
        let receiptFields = try ReceiptCanonicalizer.decodeReceipt(from: rawCBOR)
        let receiptType = receiptFields.receiptType

        print("📦 [INBOX] Receipt type: \(receiptType)")

        // Route to appropriate handler based on receipt type
        switch receiptType {
        case ReceiptType.sessionCreated, ReceiptType.sessionEdited, ReceiptType.sessionDeleted:
            try await processMemoryReceipt(message, rawCBOR: rawCBOR)

        case ReceiptType.reactionAdded:
            try await processReactionReceipt(message, rawCBOR: rawCBOR)

        default:
            print("⚠️ [INBOX] Unknown receipt type: \(receiptType), skipping")
        }

        // Mark message as delivered on relay
        print("🗑️  [INBOX] Deleting message from relay...")
        try await RelayClient.shared.deleteMessage(messageId: message.messageId)

        print("✅ [INBOX] Message \(message.messageId) fully processed")
    }

    // Process memory (session) receipt
    private func processMemoryReceipt(_ message: EncryptedMessage, rawCBOR: Data) async throws {
        let repository = MemoryRepository()

        // Check if already processed (idempotency protection)
        print("🔍 [INBOX] Checking if memory already processed...")
        let alreadyProcessed = try await repository.isMessageProcessed(relayMessageId: message.messageId)
        if alreadyProcessed {
            print("⚠️  [INBOX] Memory \(message.messageId) already processed, skipping")
            return
        }

        // Store receipt in database
        print("🗄️  [INBOX] Storing memory receipt...")
        try await repository.storeSharedReceipt(
            receiptCID: message.receiptCID,
            rawCBOR: rawCBOR,
            signature: message.signature,
            senderDID: message.senderDID,
            senderDeviceId: message.senderDeviceId,
            relayMessageId: message.messageId
        )

        print("✅ [INBOX] Memory stored")
    }

    // Process reaction receipt (Phase 10.1 Module 1.5)
    private func processReactionReceipt(_ message: EncryptedMessage, rawCBOR: Data) async throws {
        let repository = ReactionRepository()

        // Decode reaction payload
        let receiptFields = try ReceiptCanonicalizer.decodeReceipt(from: rawCBOR)
        let payload = try ReceiptCanonicalizer.decodeReactionAddedPayload(from: receiptFields.payloadCBOR)

        print("❤️  [INBOX] Reaction: \(payload.reactionType) on memory \(payload.memoryID)")

        // Store reaction in database
        try await repository.storeReceivedReaction(
            memoryID: UUID(uuidString: payload.memoryID)!,
            senderDID: message.senderDID,
            reactionType: ReactionType(rawValue: payload.reactionType)!,
            createdAtMs: payload.createdAtMs
        )

        print("✅ [INBOX] Reaction stored")
    }

    // Helper to decrypt and verify message
    private func decryptAndVerify(_ message: EncryptedMessage) async throws -> Data {
        print("🔓 [INBOX] Decrypting message from \(message.senderDID)")
        print("🔓 [INBOX] Sender device: \(message.senderDeviceId)")
        print("🔓 [INBOX] Receipt CID: \(message.receiptCID)")

        // Step 1: Get device-specific pinned key (TOFU key pinning)
        print("🔐 [INBOX] Looking up device-specific pinned Ed25519 key...")
        var pinnedPubkeyData = try await JarManager.shared.getPinnedEd25519PublicKey(
            did: message.senderDID,
            deviceId: message.senderDeviceId
        )

        // Phase 10.3 Module 0.4: Dynamic Device Discovery
        if pinnedPubkeyData == nil {
            print("⚠️  [INBOX] Device \(message.senderDeviceId) not found locally - fetching from relay...")

            // Fetch device from relay
            let devices = try await DeviceManager.shared.getDevices(for: [message.senderDID])
            guard let newDevice = devices.first(where: { $0.deviceId == message.senderDeviceId }) else {
                print("❌ [INBOX] Device \(message.senderDeviceId) not found on relay")
                throw InboxError.senderDeviceNotFound
            }

            // Pin new device (updated TOFU)
            try await Database.shared.writeAsync { db in
                try newDevice.insert(db)
            }

            print("✅ [INBOX] New device pinned: \(newDevice.deviceId)")

            // Get pinned key from newly inserted device
            guard let pubkeyData = Data(base64Encoded: newDevice.pubkeyEd25519) else {
                throw InboxError.invalidPublicKey
            }
            pinnedPubkeyData = pubkeyData

            // Notify user of new device (toast warning)
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .newDeviceDetected,
                    object: nil,
                    userInfo: ["did": message.senderDID, "deviceId": message.senderDeviceId]
                )
            }
        }

        guard let pubkeyData = pinnedPubkeyData else {
            throw InboxError.senderDeviceNotPinned
        }
        print("✅ [INBOX] Found device-specific TOFU-pinned Ed25519 key")

        // Step 2: Decrypt message to get raw CBOR
        print("🔓 [INBOX] Decrypting E2EE payload...")
        let rawCBOR = try await E2EEManager.shared.decryptMessage(message)
        print("✅ [INBOX] Decryption successful, CBOR size: \(rawCBOR.count) bytes")

        // Step 3: Verify CID integrity (prevent tampering)
        print("🔐 [INBOX] Verifying CID integrity...")
        let computedCID = await ReceiptManager.shared.computeCID(from: rawCBOR)
        guard computedCID == message.receiptCID else {
            print("❌ [INBOX] CID mismatch! Expected: \(message.receiptCID), Got: \(computedCID)")
            throw InboxError.cidMismatch
        }
        print("✅ [INBOX] CID verified - content matches claimed CID")

        // Step 4: Verify Ed25519 signature over CBOR
        print("🔐 [INBOX] Verifying Ed25519 signature...")
        let senderPublicKey = try Curve25519.Signing.PublicKey(rawRepresentation: pubkeyData)

        let isValid = try await ReceiptManager.shared.verifyReceipt(
            cborData: rawCBOR,
            signature: message.signature,
            publicKey: senderPublicKey
        )

        guard isValid else {
            print("❌ [INBOX] Signature verification FAILED for \(message.senderDeviceId)")
            throw InboxError.signatureVerificationFailed
        }

        print("✅ [INBOX] Signature verified - message is authentic")
        return rawCBOR
    }
}

// Notification for UI updates
extension Notification.Name {
    static let inboxUpdated = Notification.Name("inboxUpdated")
    static let newDeviceDetected = Notification.Name("newDeviceDetected")  // Phase 10.3 Module 0.4
    static let jarUpdated = Notification.Name("jarUpdated")                // Phase 10.3 Module 5a
}

// MARK: - Errors

enum InboxError: Error, LocalizedError {
    case senderNotInCircle
    case senderDeviceNotPinned
    case senderDeviceNotFound        // Phase 10.3 Module 0.4
    case invalidPublicKey            // Phase 10.3 Module 0.4
    case cidMismatch
    case signatureVerificationFailed

    var errorDescription: String? {
        switch self {
        case .senderNotInCircle:
            return "Sender not in your Circle"
        case .senderDeviceNotPinned:
            return "Sender device not found or not pinned in Circle"
        case .senderDeviceNotFound:
            return "Sender device not found on relay"
        case .invalidPublicKey:
            return "Invalid device public key"
        case .cidMismatch:
            return "Receipt CID does not match decrypted content (tampering detected)"
        case .signatureVerificationFailed:
            return "Message signature verification failed"
        }
    }
}
