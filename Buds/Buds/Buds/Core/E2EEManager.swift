//
//  E2EEManager.swift
//  Buds
//
//  Phase 6: End-to-end encryption for Circle sharing
//

import Foundation
import Combine
import CryptoKit
import GRDB

@MainActor
class E2EEManager {
    static let shared = E2EEManager()
    private init() {}

    // MARK: - Encryption

    /// Encrypt message for Circle sharing
    func encryptMessage(receiptCID: String, rawCBOR: Data, recipientDevices: [Device]) async throws -> EncryptedMessage {
        // Generate ephemeral AES-256 key for this message
        let aesKey = SymmetricKey(size: .bits256)
        let nonce = AES.GCM.Nonce()

        // Encrypt CBOR with AES-GCM (using receipt CID as authenticated data)
        let sealed = try AES.GCM.seal(
            rawCBOR,
            using: aesKey,
            nonce: nonce,
            authenticating: receiptCID.data(using: .utf8)!
        )

        let identity = IdentityManager.shared
        let senderPrivate = try await identity.getX25519Keypair().privateKey
        let senderDID = try await identity.currentDID
        let senderDevice = try await identity.deviceId

        // Wrap AES key for each recipient device
        var wrappedKeys: [String: String] = [:]
        for device in recipientDevices {
            let wrapped = try wrapKey(
                aesKey,
                forRecipient: device.pubkeyX25519,
                senderPrivate: senderPrivate
            )
            wrappedKeys[device.deviceId] = wrapped.base64EncodedString()
        }

        // Combine nonce + ciphertext + tag manually since combined might be optional
        var combinedData = Data()
        combinedData.append(sealed.nonce.withUnsafeBytes { Data($0) })
        combinedData.append(sealed.ciphertext)
        combinedData.append(sealed.tag)

        // Fetch signature from database
        let signature = try await Database.shared.readAsync { db in
            try String.fetchOne(
                db,
                sql: "SELECT signature FROM ucr_headers WHERE cid = ?",
                arguments: [receiptCID]
            )
        }

        guard let signature = signature else {
            throw E2EEError.signatureNotFound
        }

        return EncryptedMessage(
            messageId: UUID().uuidString,
            receiptCID: receiptCID,
            encryptedPayload: combinedData.base64EncodedString(),
            wrappedKeys: wrappedKeys,
            senderDID: senderDID,
            senderDeviceId: senderDevice,
            recipientDIDs: recipientDevices.map(\.ownerDID),
            createdAt: Date(),
            signature: signature
        )
    }

    // MARK: - Decryption

    /// Decrypt message from Circle (returns raw CBOR)
    func decryptMessage(_ msg: EncryptedMessage) async throws -> Data {
        let identity = IdentityManager.shared
        let myDevice = try await identity.deviceId
        let myPrivate = try await identity.getX25519Keypair().privateKey

        // Find wrapped key for this device
        guard let wrappedB64 = msg.wrappedKeys[myDevice],
              let wrappedData = Data(base64Encoded: wrappedB64)
        else {
            throw E2EEError.noKeyForDevice
        }

        // Unwrap AES key using sender's public key
        let aesKey = try await unwrapKey(
            wrappedData,
            fromSender: msg.senderDeviceId,
            myPrivate: myPrivate
        )

        // Decrypt payload
        guard let encryptedData = Data(base64Encoded: msg.encryptedPayload) else {
            throw E2EEError.invalidPayload
        }
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)

        return try AES.GCM.open(
            sealedBox,
            using: aesKey,
            authenticating: msg.receiptCID.data(using: .utf8)!
        )
    }

    /// Decrypt and verify message with TOFU signature verification (Phase 7)
    /// NOTE: This method is currently unused - InboxManager handles decryption directly
    func decryptAndVerifyMessage(_ msg: EncryptedMessage) async throws -> UCRHeader {
        // Decrypt to get raw CBOR
        let rawCBOR = try await decryptMessage(msg)

        // SECURITY: Get sender's device-specific Ed25519 public key (TOFU key pinning)
        // DO NOT trust message.senderSigningPublicKey (relay could swap it)
        guard let pinnedPubkey = try await JarManager.shared.getPinnedEd25519PublicKey(
            did: msg.senderDID,
            deviceId: msg.senderDeviceId
        ) else {
            throw E2EEError.senderNotInCircle
        }

        // Verify signature over raw CBOR using pinned key
        let senderPublicKey = try Curve25519.Signing.PublicKey(rawRepresentation: pinnedPubkey)
        let isValid = try await ReceiptManager.shared.verifyReceipt(
            cborData: rawCBOR,
            signature: msg.signature,
            publicKey: senderPublicKey
        )
        guard isValid else {
            throw E2EEError.signatureVerificationFailed
        }

        // Decode CBOR to UCRHeader
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let receipt = try decoder.decode(UCRHeader.self, from: rawCBOR)

        print("✅ Message decrypted and verified from \(msg.senderDID)")
        return receipt
    }

    // MARK: - Key Wrapping (X25519 + HKDF + AES-GCM)

    /// Wrap AES key for recipient using X25519 key agreement
    private func wrapKey(
        _ aesKey: SymmetricKey,
        forRecipient pubkeyB64: String,
        senderPrivate: Curve25519.KeyAgreement.PrivateKey
    ) throws -> Data {
        // Parse recipient's public key
        guard let recipientData = Data(base64Encoded: pubkeyB64) else {
            throw E2EEError.invalidPublicKey
        }
        let recipientKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientData)

        // X25519 key agreement (ECDH)
        let sharedSecret = try senderPrivate.sharedSecretFromKeyAgreement(with: recipientKey)

        // Derive wrapping key using HKDF
        let wrappingKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: "buds.wrap.v1".data(using: .utf8)!,
            outputByteCount: 32
        )

        // Encrypt AES key with wrapping key (AES-GCM)
        let wrapNonce = AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(
            aesKey.withUnsafeBytes { Data($0) },
            using: wrappingKey,
            nonce: wrapNonce
        )

        // Combine: nonce (12) + ciphertext + tag (16)
        var result = Data()
        result.append(wrapNonce.withUnsafeBytes { Data($0) })
        result.append(sealed.ciphertext)
        result.append(sealed.tag)
        return result
    }

    /// Unwrap AES key from sender using X25519 key agreement
    private func unwrapKey(
        _ wrappedData: Data,
        fromSender senderDevice: String,
        myPrivate: Curve25519.KeyAgreement.PrivateKey
    ) async throws -> SymmetricKey {
        // Lookup sender's device to get public key
        let senderDev = try await Database.shared.readAsync {
            try Device.filter(sql: "device_id = ?", arguments: [senderDevice]).fetchOne($0)
        }
        guard let senderDev = senderDev,
              let senderPubData = Data(base64Encoded: senderDev.pubkeyX25519)
        else {
            throw E2EEError.deviceNotFound
        }

        // X25519 key agreement
        let senderPub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: senderPubData)
        let sharedSecret = try myPrivate.sharedSecretFromKeyAgreement(with: senderPub)

        // Derive wrapping key (same HKDF as sender)
        let wrappingKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: "buds.wrap.v1".data(using: .utf8)!,
            outputByteCount: 32
        )

        // Parse wrapped data: nonce (12) + ciphertext + tag (16)
        guard wrappedData.count >= 28 else {
            throw E2EEError.invalidWrappedKey
        }
        let nonce = try AES.GCM.Nonce(data: wrappedData.prefix(12))
        let ciphertext = wrappedData.dropFirst(12).dropLast(16)
        let tag = wrappedData.suffix(16)

        // Decrypt wrapped key
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        let unwrapped = try AES.GCM.open(sealedBox, using: wrappingKey)

        return SymmetricKey(data: unwrapped)
    }
}

// MARK: - Errors

enum E2EEError: Error, LocalizedError {
    case noKeyForDevice
    case invalidWrappedKey
    case invalidPayload
    case invalidPublicKey
    case deviceNotFound
    case senderNotInCircle
    case signatureVerificationFailed
    case signatureNotFound

    var errorDescription: String? {
        switch self {
        case .noKeyForDevice:
            return "No encryption key for this device"
        case .invalidWrappedKey:
            return "Invalid wrapped key format"
        case .invalidPayload:
            return "Invalid encrypted payload"
        case .invalidPublicKey:
            return "Invalid recipient public key"
        case .deviceNotFound:
            return "Sender device not found"
        case .senderNotInCircle:
            return "Sender not in your Circle"
        case .signatureVerificationFailed:
            return "Message signature verification failed"
        case .signatureNotFound:
            return "Receipt signature not found in database"
        }
    }
}

