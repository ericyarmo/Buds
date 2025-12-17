//
//  UCRHeader.swift
//  Buds
//
//  Universal Content Receipt - Canonical receipt structure
//

import Foundation

/// Universal Content Receipt Header
/// Represents a signed, content-addressed event
struct UCRHeader: Codable {
    let cid: String                      // bafyre... (computed from unsigned preimage)
    let did: String                      // did:buds:xyz (author)
    let deviceId: String                 // UUID
    let parentCID: String?               // Edit/delete chain parent
    let rootCID: String                  // First in chain
    let receiptType: String              // app.buds.session.created/v1
    let signature: String                // Ed25519 (base64)

    // Note: NO timestamp field in header!
    // Time is in payload as claimed_time_ms (author's claim, not verifiable truth)
}

/// GRDB row representation (includes local fields)
struct UCRHeaderRow: Codable {
    let cid: String
    let did: String
    let deviceId: String
    let parentCID: String?
    let rootCID: String
    let receiptType: String
    let signature: String

    // Local-only fields (not in canonical CBOR)
    let rawCBOR: Data                    // Canonical encoding (for verification)
    let payloadJSON: String              // For querying
    let receivedAt: Double               // Local timestamp (for ordering)

    enum CodingKeys: String, CodingKey {
        case cid, did, deviceId = "device_id", parentCID = "parent_cid"
        case rootCID = "root_cid", receiptType = "receipt_type", signature
        case rawCBOR = "raw_cbor", payloadJSON = "payload_json", receivedAt = "received_at"
    }
}

// MARK: - Receipt Types

enum ReceiptType {
    static let sessionCreated = "app.buds.session.created/v1"
    static let sessionEdited = "app.buds.session.edited/v1"
    static let sessionDeleted = "app.buds.session.deleted/v1"
    static let profileCreated = "app.buds.profile.created/v1"
    static let inviteCreated = "app.buds.circle.invite.created/v1"
    static let inviteAccepted = "app.buds.circle.invite.accepted/v1"
}

// MARK: - Session Payload

/// Payload for app.buds.session.created/v1
struct SessionPayload: Codable {
    let claimedTimeMs: Int64?            // User's claimed time (UNVERIFIED)
    let productName: String              // e.g. "Blue Dream"
    let productType: String              // flower, edible, concentrate, etc.
    let rating: Int                      // 1-5 stars
    let notes: String?

    // Product details
    let brand: String?
    let thcPercent: Double?
    let cbdPercent: Double?
    let amountGrams: Double?

    // Effects & method
    let effects: [String]                // ["relaxed", "creative", ...]
    let consumptionMethod: String?       // joint, vape, edible, etc.

    // Optional location
    let locationCID: String?             // Reference to locations table

    enum CodingKeys: String, CodingKey {
        case claimedTimeMs = "claimed_time_ms"
        case productName = "product_name"
        case productType = "product_type"
        case rating, notes, brand
        case thcPercent = "thc_percent"
        case cbdPercent = "cbd_percent"
        case amountGrams = "amount_grams"
        case effects
        case consumptionMethod = "consumption_method"
        case locationCID = "location_cid"
    }
}

// MARK: - Profile Payload

/// Payload for app.buds.profile.created/v1
struct ProfilePayload: Codable {
    let displayName: String              // Local nickname (NOT shared)
    let preferences: ProfilePreferences?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case preferences
    }
}

struct ProfilePreferences: Codable {
    let locationEnabled: Bool
    let defaultShareMode: String         // "private" | "circle"
    let fuzzyLocationOnly: Bool

    enum CodingKeys: String, CodingKey {
        case locationEnabled = "location_enabled"
        case defaultShareMode = "default_share_mode"
        case fuzzyLocationOnly = "fuzzy_location_only"
    }
}

// MARK: - Invite Payloads

struct InviteCreatedPayload: Codable {
    let inviteCode: String
    let expiresAtMs: Int64
    let message: String?

    enum CodingKeys: String, CodingKey {
        case inviteCode = "invite_code"
        case expiresAtMs = "expires_at_ms"
        case message
    }
}

struct InviteAcceptedPayload: Codable {
    let inviteCode: String
    let inviterDID: String
    let acceptedAtMs: Int64

    enum CodingKeys: String, CodingKey {
        case inviteCode = "invite_code"
        case inviterDID = "inviter_did"
        case acceptedAtMs = "accepted_at_ms"
    }
}
