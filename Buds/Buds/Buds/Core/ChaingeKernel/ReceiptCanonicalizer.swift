//
//  ReceiptCanonicalizer.swift
//  Buds
//
//  Converts receipt structs to canonical CBOR
//  Ported from BudsKernelGolden (physics-tested)
//

import Foundation

enum ReceiptCanonicalizer {

    /// Encode unsigned receipt to canonical CBOR bytes
    static func canonicalCBOR(_ receipt: UnsignedReceiptPreimage) throws -> Data {
        let enc = CBORCanonical()

        // Decode the payload Data to extract fields
        // For now, we'll encode the payload as raw bytes
        // In production, we'd parse and encode as proper CBOR map

        // Build receipt as CBOR map
        var pairs: [(CBORValue, CBORValue)] = [
            (.text("did"), .text(receipt.did)),
            (.text("deviceId"), .text(receipt.deviceId)),
            (.text("receiptType"), .text(receipt.receiptType)),
            (.text("payload"), .bytes(receipt.payload)),
        ]

        if let p = receipt.parentCID {
            pairs.append((.text("parentCID"), .text(p)))
        }

        pairs.append((.text("rootCID"), .text(receipt.rootCID)))

        return try enc.encode(.map(pairs))
    }

    /// Encode SessionPayload to canonical CBOR map
    static func encodeSessionPayload(_ payload: SessionPayload) throws -> Data {
        let enc = CBORCanonical()

        var pairs: [(CBORValue, CBORValue)] = []

        // claimed_time_ms (required)
        if let time = payload.claimedTimeMs {
            pairs.append((.text("claimed_time_ms"), .int(time)))
        }

        // product_name
        pairs.append((.text("product_name"), .text(payload.productName)))

        // product_type
        pairs.append((.text("product_type"), .text(payload.productType)))

        // rating
        pairs.append((.text("rating"), .int(Int64(payload.rating))))

        // notes (optional)
        if let notes = payload.notes {
            pairs.append((.text("notes"), .text(notes)))
        }

        // effects
        let effectsArray = payload.effects.map { CBORValue.text($0) }
        pairs.append((.text("effects"), .array(effectsArray)))

        // consumption_method (optional)
        if let method = payload.consumptionMethod {
            pairs.append((.text("consumption_method"), .text(method)))
        }

        // brand (optional)
        if let brand = payload.brand {
            pairs.append((.text("brand"), .text(brand)))
        }

        // thc_percent (optional)
        if let thc = payload.thcPercent {
            pairs.append((.text("thc_percent"), .int(Int64(thc * 100))))  // Store as basis points
        }

        // cbd_percent (optional)
        if let cbd = payload.cbdPercent {
            pairs.append((.text("cbd_percent"), .int(Int64(cbd * 100))))
        }

        // amount_grams (optional)
        if let amount = payload.amountGrams {
            pairs.append((.text("amount_grams"), .int(Int64(amount * 1000))))  // Store as milligrams
        }

        // location_cid (optional)
        if let locationCID = payload.locationCID {
            pairs.append((.text("location_cid"), .text(locationCID)))
        }

        return try enc.encode(.map(pairs))
    }

    /// Encode ReactionAddedPayload to canonical CBOR map (Phase 10.1 Module 1.5)
    static func encodeReactionAddedPayload(_ payload: ReactionAddedPayload) throws -> Data {
        let enc = CBORCanonical()

        let pairs: [(CBORValue, CBORValue)] = [
            (.text("memory_id"), .text(payload.memoryID)),
            (.text("reaction_type"), .text(payload.reactionType)),
            (.text("created_at_ms"), .int(payload.createdAtMs))
        ]

        return try enc.encode(.map(pairs))
    }

    /// Encode ReactionRemovedPayload to canonical CBOR map (Phase 10.1 Module 1.5)
    static func encodeReactionRemovedPayload(_ payload: ReactionRemovedPayload) throws -> Data {
        let enc = CBORCanonical()

        let pairs: [(CBORValue, CBORValue)] = [
            (.text("memory_id"), .text(payload.memoryID)),
            (.text("reaction_type"), .text(payload.reactionType))
        ]

        return try enc.encode(.map(pairs))
    }

    // MARK: - Jar Receipt Payloads (Phase 10.3 Module 1)

    /// Encode JarCreatedPayload to canonical CBOR map
    static func encodeJarCreatedPayload(_ payload: JarCreatedPayload) throws -> Data {
        let enc = CBORCanonical()

        var pairs: [(CBORValue, CBORValue)] = [
            (.text("jar_name"), .text(payload.jarName)),
            (.text("owner_did"), .text(payload.ownerDID)),
            (.text("created_at_ms"), .int(payload.createdAtMs))
        ]

        if let desc = payload.jarDescription {
            pairs.append((.text("jar_description"), .text(desc)))
        }

        return try enc.encode(.map(pairs))
    }

    /// Encode JarMemberAddedPayload to canonical CBOR map
    static func encodeJarMemberAddedPayload(_ payload: JarMemberAddedPayload) throws -> Data {
        let enc = CBORCanonical()

        let pairs: [(CBORValue, CBORValue)] = [
            (.text("member_did"), .text(payload.memberDID)),
            (.text("member_display_name"), .text(payload.memberDisplayName)),
            (.text("member_phone_number"), .text(payload.memberPhoneNumber)),
            (.text("added_by_did"), .text(payload.addedByDID)),
            (.text("added_at_ms"), .int(payload.addedAtMs))
        ]

        return try enc.encode(.map(pairs))
    }

    /// Encode JarInviteAcceptedPayload to canonical CBOR map
    static func encodeJarInviteAcceptedPayload(_ payload: JarInviteAcceptedPayload) throws -> Data {
        let enc = CBORCanonical()

        let pairs: [(CBORValue, CBORValue)] = [
            (.text("member_did"), .text(payload.memberDID)),
            (.text("accepted_at_ms"), .int(payload.acceptedAtMs))
        ]

        return try enc.encode(.map(pairs))
    }

    /// Encode JarMemberRemovedPayload to canonical CBOR map
    static func encodeJarMemberRemovedPayload(_ payload: JarMemberRemovedPayload) throws -> Data {
        let enc = CBORCanonical()

        var pairs: [(CBORValue, CBORValue)] = [
            (.text("member_did"), .text(payload.memberDID)),
            (.text("removed_by_did"), .text(payload.removedByDID)),
            (.text("removed_at_ms"), .int(payload.removedAtMs))
        ]

        if let reason = payload.reason {
            pairs.append((.text("reason"), .text(reason)))
        }

        return try enc.encode(.map(pairs))
    }

    /// Encode JarMemberLeftPayload to canonical CBOR map
    static func encodeJarMemberLeftPayload(_ payload: JarMemberLeftPayload) throws -> Data {
        let enc = CBORCanonical()

        let pairs: [(CBORValue, CBORValue)] = [
            (.text("member_did"), .text(payload.memberDID)),
            (.text("left_at_ms"), .int(payload.leftAtMs))
        ]

        return try enc.encode(.map(pairs))
    }

    /// Encode JarRenamedPayload to canonical CBOR map
    static func encodeJarRenamedPayload(_ payload: JarRenamedPayload) throws -> Data {
        let enc = CBORCanonical()

        let pairs: [(CBORValue, CBORValue)] = [
            (.text("jar_name"), .text(payload.jarName)),
            (.text("renamed_by_did"), .text(payload.renamedByDID)),
            (.text("renamed_at_ms"), .int(payload.renamedAtMs))
        ]

        return try enc.encode(.map(pairs))
    }

    /// Encode JarDeletedPayload to canonical CBOR map
    static func encodeJarDeletedPayload(_ payload: JarDeletedPayload) throws -> Data {
        let enc = CBORCanonical()

        let pairs: [(CBORValue, CBORValue)] = [
            (.text("deleted_by_did"), .text(payload.deletedByDID)),
            (.text("deleted_at_ms"), .int(payload.deletedAtMs)),
            (.text("jar_name"), .text(payload.jarName))
        ]

        return try enc.encode(.map(pairs))
    }

    /// Encode JarBudSharedPayload to canonical CBOR map
    static func encodeJarBudSharedPayload(_ payload: JarBudSharedPayload) throws -> Data {
        let enc = CBORCanonical()

        let pairs: [(CBORValue, CBORValue)] = [
            (.text("bud_uuid"), .text(payload.budUUID)),
            (.text("shared_by_did"), .text(payload.sharedByDID)),
            (.text("shared_at_ms"), .int(payload.sharedAtMs)),
            (.text("bud_cid"), .text(payload.budCID))
        ]

        return try enc.encode(.map(pairs))
    }

    /// Encode JarBudDeletedPayload to canonical CBOR map
    static func encodeJarBudDeletedPayload(_ payload: JarBudDeletedPayload) throws -> Data {
        let enc = CBORCanonical()

        var pairs: [(CBORValue, CBORValue)] = [
            (.text("bud_uuid"), .text(payload.budUUID)),
            (.text("deleted_by_did"), .text(payload.deletedByDID)),
            (.text("deleted_at_ms"), .int(payload.deletedAtMs))
        ]

        if let reason = payload.reason {
            pairs.append((.text("reason"), .text(reason)))
        }

        return try enc.encode(.map(pairs))
    }

    /// Encode JarReceiptPayload (envelope with type-specific payload) to canonical CBOR
    /// CRITICAL: NO sequence number (relay assigns in envelope)
    static func encodeJarReceiptPayload(_ receipt: JarReceiptPayload) throws -> Data {
        let enc = CBORCanonical()

        var pairs: [(CBORValue, CBORValue)] = [
            (.text("jar_id"), .text(receipt.jarID)),
            (.text("receipt_type"), .text(receipt.receiptType)),
            (.text("sender_did"), .text(receipt.senderDID)),
            (.text("timestamp"), .int(receipt.timestamp)),
            (.text("payload"), .bytes(receipt.payload))
        ]

        if let parentCID = receipt.parentCID {
            pairs.append((.text("parent_cid"), .text(parentCID)))
        }

        return try enc.encode(.map(pairs))
    }

    // MARK: - Decoding

    /// Decode raw CBOR to extract receipt fields
    static func decodeReceipt(from cborData: Data) throws -> (
        did: String,
        deviceId: String,
        parentCID: String?,
        rootCID: String,
        receiptType: String,
        payloadCBOR: Data
    ) {
        let decoder = CBORDecoder()
        let value = try decoder.decode(cborData)

        guard case .map(let pairs) = value else {
            throw CBORDecodeError.invalidStructure
        }

        // Convert pairs to dictionary for easier lookup
        var fields: [String: CBORValue] = [:]
        for (key, val) in pairs {
            guard case .text(let keyStr) = key else { continue }
            fields[keyStr] = val
        }

        // Extract required fields
        guard case .text(let did) = fields["did"] else {
            throw CBORDecodeError.missingRequiredField("did")
        }
        guard case .text(let deviceId) = fields["deviceId"] else {
            throw CBORDecodeError.missingRequiredField("deviceId")
        }
        guard case .text(let receiptType) = fields["receiptType"] else {
            throw CBORDecodeError.missingRequiredField("receiptType")
        }
        guard case .bytes(let payloadCBOR) = fields["payload"] else {
            throw CBORDecodeError.missingRequiredField("payload")
        }
        guard case .text(let rootCID) = fields["rootCID"] else {
            throw CBORDecodeError.missingRequiredField("rootCID")
        }

        // Extract optional parentCID
        let parentCID: String?
        if case .text(let parent) = fields["parentCID"] {
            parentCID = parent
        } else {
            parentCID = nil
        }

        return (did, deviceId, parentCID, rootCID, receiptType, payloadCBOR)
    }

    /// Decode SessionPayload from CBOR
    static func decodeSessionPayload(from cborData: Data) throws -> SessionPayload {
        let decoder = CBORDecoder()
        let value = try decoder.decode(cborData)

        guard case .map(let pairs) = value else {
            throw CBORDecodeError.invalidStructure
        }

        // Convert pairs to dictionary
        var fields: [String: CBORValue] = [:]
        for (key, val) in pairs {
            guard case .text(let keyStr) = key else { continue }
            fields[keyStr] = val
        }

        // Extract required fields
        guard case .text(let productName) = fields["product_name"] else {
            throw CBORDecodeError.missingRequiredField("product_name")
        }
        guard case .text(let productType) = fields["product_type"] else {
            throw CBORDecodeError.missingRequiredField("product_type")
        }
        guard case .int(let rating) = fields["rating"] else {
            throw CBORDecodeError.missingRequiredField("rating")
        }

        // Extract optional claimed_time_ms
        let claimedTimeMs: Int64?
        if case .int(let time) = fields["claimed_time_ms"] {
            claimedTimeMs = time
        } else {
            claimedTimeMs = nil
        }

        // Extract optional notes
        let notes: String?
        if case .text(let n) = fields["notes"] {
            notes = n
        } else {
            notes = nil
        }

        // Extract optional brand
        let brand: String?
        if case .text(let b) = fields["brand"] {
            brand = b
        } else {
            brand = nil
        }

        // Extract optional thc_percent (stored as basis points)
        let thcPercent: Double?
        if case .int(let thc) = fields["thc_percent"] {
            thcPercent = Double(thc) / 100.0
        } else {
            thcPercent = nil
        }

        // Extract optional cbd_percent (stored as basis points)
        let cbdPercent: Double?
        if case .int(let cbd) = fields["cbd_percent"] {
            cbdPercent = Double(cbd) / 100.0
        } else {
            cbdPercent = nil
        }

        // Extract optional amount_grams (stored as milligrams)
        let amountGrams: Double?
        if case .int(let amount) = fields["amount_grams"] {
            amountGrams = Double(amount) / 1000.0
        } else {
            amountGrams = nil
        }

        // Extract effects array
        let effects: [String]
        if case .array(let effectsArray) = fields["effects"] {
            effects = effectsArray.compactMap {
                if case .text(let effect) = $0 { return effect }
                return nil
            }
        } else {
            effects = []
        }

        // Extract optional consumption_method
        let consumptionMethod: String?
        if case .text(let method) = fields["consumption_method"] {
            consumptionMethod = method
        } else {
            consumptionMethod = nil
        }

        // Extract optional location_cid
        let locationCID: String?
        if case .text(let loc) = fields["location_cid"] {
            locationCID = loc
        } else {
            locationCID = nil
        }

        return SessionPayload(
            claimedTimeMs: claimedTimeMs,
            productName: productName,
            productType: productType,
            rating: Int(rating),
            notes: notes,
            brand: brand,
            thcPercent: thcPercent,
            cbdPercent: cbdPercent,
            amountGrams: amountGrams,
            effects: effects,
            consumptionMethod: consumptionMethod,
            locationCID: locationCID
        )
    }

    /// Decode ReactionAddedPayload from CBOR (Phase 10.1 Module 1.5)
    static func decodeReactionAddedPayload(from cborData: Data) throws -> ReactionAddedPayload {
        let decoder = CBORDecoder()
        let value = try decoder.decode(cborData)

        guard case .map(let pairs) = value else {
            throw CBORDecodeError.invalidStructure
        }

        var fields: [String: CBORValue] = [:]
        for (key, val) in pairs {
            guard case .text(let keyStr) = key else { continue }
            fields[keyStr] = val
        }

        guard case .text(let memoryID) = fields["memory_id"] else {
            throw CBORDecodeError.missingRequiredField("memory_id")
        }
        guard case .text(let reactionType) = fields["reaction_type"] else {
            throw CBORDecodeError.missingRequiredField("reaction_type")
        }
        guard case .int(let createdAtMs) = fields["created_at_ms"] else {
            throw CBORDecodeError.missingRequiredField("created_at_ms")
        }

        return ReactionAddedPayload(
            memoryID: memoryID,
            reactionType: reactionType,
            createdAtMs: createdAtMs
        )
    }

    /// Decode ReactionRemovedPayload from CBOR (Phase 10.1 Module 1.5)
    static func decodeReactionRemovedPayload(from cborData: Data) throws -> ReactionRemovedPayload {
        let decoder = CBORDecoder()
        let value = try decoder.decode(cborData)

        guard case .map(let pairs) = value else {
            throw CBORDecodeError.invalidStructure
        }

        var fields: [String: CBORValue] = [:]
        for (key, val) in pairs {
            guard case .text(let keyStr) = key else { continue }
            fields[keyStr] = val
        }

        guard case .text(let memoryID) = fields["memory_id"] else {
            throw CBORDecodeError.missingRequiredField("memory_id")
        }
        guard case .text(let reactionType) = fields["reaction_type"] else {
            throw CBORDecodeError.missingRequiredField("reaction_type")
        }

        return ReactionRemovedPayload(
            memoryID: memoryID,
            reactionType: reactionType
        )
    }
}
