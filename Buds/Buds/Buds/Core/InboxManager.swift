//
//  InboxManager.swift
//  Buds
//
//  Phase 7: Message inbox polling and processing
//

import Foundation
import Combine
import CryptoKit

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
            // Get authenticated user's DID
            let did = try await IdentityManager.shared.currentDID

            // Fetch messages from relay
            let messages = try await RelayClient.shared.getInbox(for: did)

            guard !messages.isEmpty else {
                print("📭 Inbox empty")
                return
            }

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

        } catch {
            print("❌ Inbox poll failed: \(error)")
        }
    }

    // Process and decrypt a single message
    private func processMessage(_ message: EncryptedMessage) async throws {
        print("📥 [INBOX] Processing message \(message.messageId)")
        print("📥 [INBOX] Sender: \(message.senderDID)")
        print("📥 [INBOX] Receipt CID: \(message.receiptCID)")

        let repository = MemoryRepository()

        // Check if already processed (idempotency protection)
        print("🔍 [INBOX] Checking if message already processed...")
        let alreadyProcessed = try await repository.isMessageProcessed(relayMessageId: message.messageId)
        if alreadyProcessed {
            print("⚠️  [INBOX] Message \(message.messageId) already processed, skipping")
            // Still delete from relay to clean up
            try await RelayClient.shared.deleteMessage(messageId: message.messageId)
            return
        }
        print("✅ [INBOX] Message is new, proceeding with decryption")

        // Decrypt and verify sender is in Circle
        let rawCBOR = try await decryptAndVerify(message)

        // Store receipt in database with relay message ID and raw CBOR
        // Use metadata from the EncryptedMessage (receiptCID, senderDID, etc.)
        print("🗄️  [INBOX] Storing receipt in database...")
        try await repository.storeSharedReceipt(
            receiptCID: message.receiptCID,
            rawCBOR: rawCBOR,
            signature: message.signature,
            senderDID: message.senderDID,
            senderDeviceId: message.senderDeviceId,
            relayMessageId: message.messageId
        )

        // Mark message as delivered on relay
        print("🗑️  [INBOX] Deleting message from relay...")
        try await RelayClient.shared.deleteMessage(messageId: message.messageId)

        print("✅ [INBOX] Message \(message.messageId) fully processed and stored")
    }

    // Helper to decrypt and verify message
    private func decryptAndVerify(_ message: EncryptedMessage) async throws -> Data {
        print("🔓 [INBOX] Decrypting message from \(message.senderDID)")
        print("🔓 [INBOX] Sender device: \(message.senderDeviceId)")
        print("🔓 [INBOX] Receipt CID: \(message.receiptCID)")

        // Step 1: Get device-specific pinned key (TOFU key pinning)
        print("🔐 [INBOX] Looking up device-specific pinned Ed25519 key...")
        guard let pinnedPubkeyData = try await JarManager.shared.getPinnedEd25519PublicKey(
            did: message.senderDID,
            deviceId: message.senderDeviceId
        ) else {
            print("❌ [INBOX] Sender device not pinned: \(message.senderDeviceId) (DID: \(message.senderDID))")
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
        let senderPublicKey = try Curve25519.Signing.PublicKey(rawRepresentation: pinnedPubkeyData)

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
}

// MARK: - Errors

enum InboxError: Error, LocalizedError {
    case senderNotInCircle
    case senderDeviceNotPinned
    case cidMismatch
    case signatureVerificationFailed

    var errorDescription: String? {
        switch self {
        case .senderNotInCircle:
            return "Sender not in your Circle"
        case .senderDeviceNotPinned:
            return "Sender device not found or not pinned in Circle"
        case .cidMismatch:
            return "Receipt CID does not match decrypted content (tampering detected)"
        case .signatureVerificationFailed:
            return "Message signature verification failed"
        }
    }
}
