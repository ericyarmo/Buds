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
}
