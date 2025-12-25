//
//  EncryptedMessage.swift
//  Buds
//
//  Phase 6: E2EE message structure for relay transport
//

import Foundation

struct EncryptedMessage: Codable {
    let messageId: String
    let receiptCID: String
    let encryptedPayload: String
    let wrappedKeys: [String: String]
    let senderDID: String
    let senderDeviceId: String
    let recipientDIDs: [String]
    let createdAt: Date
    let signature: String  // Ed25519 signature for verification

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case receiptCID = "receipt_cid"
        case encryptedPayload = "encrypted_payload"
        case wrappedKeys = "wrapped_keys"
        case senderDID = "sender_did"
        case senderDeviceId = "sender_device_id"
        case recipientDIDs = "recipient_dids"
        case createdAt = "created_at"
        case signature
    }
}
