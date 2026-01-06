/**
 * Jar Receipt Payloads (Phase 10.3 Module 1)
 *
 * CRITICAL ARCHITECTURE (Jan 3, 2026):
 * - Sequence number is NOT in these payloads (relay assigns in envelope)
 * - Client signs payload → sends to relay → relay assigns sequence
 * - These structs represent the SIGNED portion (canonical CBOR)
 *
 * Relay Envelope Architecture:
 * - Client payload (signed): jarID, receiptType, senderDID, timestamp, parentCID, payload
 * - Relay envelope (NOT signed): sequenceNumber, receiptCID, receiptData, signature, receivedAt
 */

import Foundation

// MARK: - Base Receipt Payload

/**
 * Common fields for all jar receipts (NOT including sequence)
 *
 * CRITICAL: This is what gets signed by the client
 * Sequence number lives in relay envelope, NOT here
 */
struct JarReceiptPayload: Codable {
    let jarID: String              // Which jar this receipt belongs to
    let receiptType: String        // "jar.created", "jar.member_added", etc.
    let senderDID: String          // Who created this receipt (DID)
    let timestamp: Int64           // Local time (UX only, not for ordering)
    let parentCID: String?         // Previous receipt CID (optional causal metadata)

    // Receipt-specific fields (encoded as nested CBOR)
    let payload: Data              // Type-specific fields (jar name, member info, etc.)
}

// MARK: - Jar Operation Receipts

/**
 * jar.created - Owner creates new jar
 *
 * First receipt for any jar:
 * - sequence: 1 (assigned by relay)
 * - parentCID: nil (root receipt)
 */
struct JarCreatedPayload: Codable {
    let jarName: String
    let jarDescription: String?
    let ownerDID: String           // Redundant with senderDID but explicit
    let createdAtMs: Int64
}

/**
 * Device info for TOFU key pinning
 *
 * Included in jar.member_added receipts so all jar members can pin invitee's devices
 */
struct DeviceInfo: Codable {
    let deviceId: String
    let pubkeyEd25519: String       // For signature verification
    let pubkeyX25519: String        // For E2EE encryption
}

/**
 * jar.member_added - Owner adds member to jar
 *
 * Sets member status to "pending" (awaiting invite_accepted)
 * Module 6: Includes device list for TOFU key pinning across all jar members
 */
struct JarMemberAddedPayload: Codable {
    let memberDID: String
    let memberDisplayName: String
    let memberPhoneNumber: String   // For UI
    let memberDevices: [DeviceInfo] // TOFU: All jar members pin these devices
    let addedByDID: String          // Owner (redundant but explicit)
    let addedAtMs: Int64
}

/**
 * jar.invite_accepted - Member accepts invite
 *
 * Changes member status from "pending" to "active"
 */
struct JarInviteAcceptedPayload: Codable {
    let memberDID: String           // Who accepted (redundant with senderDID)
    let acceptedAtMs: Int64
}

/**
 * jar.member_removed - Owner removes member
 *
 * Changes member status to "removed"
 */
struct JarMemberRemovedPayload: Codable {
    let memberDID: String           // Who was removed
    let removedByDID: String        // Owner
    let removedAtMs: Int64
    let reason: String?             // Optional reason
}

/**
 * jar.member_left - Member leaves jar voluntarily
 *
 * Changes member status to "removed"
 */
struct JarMemberLeftPayload: Codable {
    let memberDID: String           // Who left (redundant with senderDID)
    let leftAtMs: Int64
}

/**
 * jar.renamed - Owner renames jar
 *
 * Updates jar name (conflict resolution: relay sequence order wins)
 */
struct JarRenamedPayload: Codable {
    let jarName: String             // New name
    let renamedByDID: String        // Owner
    let renamedAtMs: Int64
}

/**
 * jar.deleted - Owner deletes jar
 *
 * Creates tombstone, prevents future operations
 * Final receipt for this jar
 */
struct JarDeletedPayload: Codable {
    let deletedByDID: String
    let deletedAtMs: Int64
    let jarName: String             // For tombstone (UX)
}

// MARK: - Bud Operation Receipts

/**
 * jar.bud_shared - Member shares bud to jar
 *
 * Adds bud to jar (visible to all active members)
 */
struct JarBudSharedPayload: Codable {
    let budUUID: String             // Which bud (UUID from ucr_headers)
    let sharedByDID: String         // Who shared it (redundant with senderDID)
    let sharedAtMs: Int64
    let budCID: String              // CID of bud receipt (for verification)
}

/**
 * jar.bud_deleted - Owner deletes bud from jar
 *
 * Removes bud from jar (propagates to all members)
 * Validation: deletedByDID must match bud.ownerDID (only owner can delete)
 */
struct JarBudDeletedPayload: Codable {
    let budUUID: String             // Which bud
    let deletedByDID: String        // Who deleted it (must be bud owner)
    let deletedAtMs: Int64          // Claimed time
    let reason: String?             // "owner_deleted", "jar_deleted", etc.
}

// MARK: - Receipt Type Constants

extension String {
    static let jarCreated = "jar.created"
    static let jarMemberAdded = "jar.member_added"
    static let jarInviteAccepted = "jar.invite_accepted"
    static let jarMemberRemoved = "jar.member_removed"
    static let jarMemberLeft = "jar.member_left"
    static let jarRenamed = "jar.renamed"
    static let jarDeleted = "jar.deleted"
    static let jarBudShared = "jar.bud_shared"
    static let jarBudDeleted = "jar.bud_deleted"
}

// MARK: - Relay Envelope (Receive-Only)

/**
 * Relay envelope (what we receive from relay)
 *
 * CRITICAL: This is NOT what we sign
 * Relay adds sequence number + metadata AFTER we send signed receipt
 */
struct RelayEnvelope: Codable {
    let jarID: String
    let sequenceNumber: Int        // AUTHORITATIVE (relay-assigned)
    let receiptCID: String         // CID of signed payload
    let receiptData: Data          // The signed CBOR bytes
    let signature: Data            // Ed25519 signature
    let senderDID: String
    let receivedAt: Int64          // Server timestamp
    let parentCID: String?
}

// MARK: - Relay Response

/**
 * Response from POST /api/jars/{jar_id}/receipts
 */
struct StoreReceiptResponse: Codable {
    let success: Bool
    let receiptCID: String         // CID of stored receipt
    let sequenceNumber: Int        // AUTHORITATIVE (relay-assigned)
    let jarID: String
}
