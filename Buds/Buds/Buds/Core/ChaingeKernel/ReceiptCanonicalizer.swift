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
}
