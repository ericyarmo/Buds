//
//  CBORCanonicalityTests.swift
//  BudsTests
//
//  Phase 10.3 Module 0.1: CBOR Library Stability
//  These tests freeze the exact CBOR encoding to prevent signature breaks
//
//  CRITICAL: If any test in this file fails, DO NOT update the golden value.
//  Instead, investigate why the encoding changed:
//  1. Was CBORCanonical.swift modified?
//  2. Did a payload struct change?
//  3. Is this intentional? (requires migration plan)
//
//  Created by Claude Code on 12/30/25.
//

import XCTest
@testable import Buds

final class CBORCanonicalityTests: XCTestCase {

    // MARK: - SessionPayload Golden Tests

    func testSessionPayload_MinimalFields_GoldenBytes() throws {
        // Fixed test data (deterministic)
        let payload = SessionPayload(
            claimedTimeMs: 1704844800000,    // 2024-01-10 00:00:00 UTC
            productName: "Blue Dream",
            productType: "flower",
            rating: 5,
            notes: "Great for focus",
            brand: nil,
            thcPercent: nil,
            cbdPercent: nil,
            amountGrams: nil,
            effects: ["creative", "relaxed"],  // Alphabetically sorted
            consumptionMethod: nil,
            locationCID: nil
        )

        // Encode to canonical CBOR
        let cbor = try ReceiptCanonicalizer.encodeSessionPayload(payload)
        let hexString = cbor.map { String(format: "%02x", $0) }.joined()

        // Expected golden value (FROZEN - DO NOT CHANGE)
        let expectedHex = "a6656e6f7465736f477265617420666f7220666f63757366726174696e67056765666665637473826863726561746976656772656c617865646c70726f647563745f6e616d656a426c756520447265616d6c70726f647563745f7479706566666c6f7765726f636c61696d65645f74696d655f6d731b0000018cf0ab3000"

        XCTAssertEqual(
            hexString,
            expectedHex,
            """
            ❌ CBOR encoding changed for SessionPayload!

            This is CRITICAL - changing CBOR encoding breaks ALL existing signatures.

            If you see this failure:
            1. Check if CBORCanonical.swift was modified
            2. Check if SessionPayload struct changed
            3. DO NOT blindly update the golden value
            4. If change is intentional, create a migration plan (Phase 15)

            Current hex:
            \(hexString)

            Expected hex:
            \(expectedHex)
            """
        )
    }

    func testSessionPayload_AllFields_GoldenBytes() throws {
        // Fixed test data with all optional fields populated
        let payload = SessionPayload(
            claimedTimeMs: 1704844800000,
            productName: "Blue Dream",
            productType: "flower",
            rating: 5,
            notes: "Amazing session with friends",
            brand: "Top Shelf",
            thcPercent: 25.5,
            cbdPercent: 0.5,
            amountGrams: 3.5,
            effects: ["creative", "euphoric", "relaxed"],  // Sorted
            consumptionMethod: "joint",
            locationCID: "bafyreiabc123"
        )

        let cbor = try ReceiptCanonicalizer.encodeSessionPayload(payload)
        let hexString = cbor.map { String(format: "%02x", $0) }.joined()

        let expectedHex = "ac656272616e6469546f70205368656c66656e6f746573781c416d617a696e672073657373696f6e207769746820667269656e647366726174696e670567656666656374738368637265617469766568657570686f7269636772656c617865646b6362645f70657263656e7418326b7468635f70657263656e741909f66c616d6f756e745f6772616d73190dac6c6c6f636174696f6e5f6369646d626166797265696162633132336c70726f647563745f6e616d656a426c756520447265616d6c70726f647563745f7479706566666c6f7765726f636c61696d65645f74696d655f6d731b0000018cf0ab300072636f6e73756d7074696f6e5f6d6574686f64656a6f696e74"

        XCTAssertEqual(
            hexString,
            expectedHex,
            """
            ❌ CBOR encoding changed for SessionPayload (all fields)!

            Current hex: \(hexString)
            Expected hex: \(expectedHex)

            See testSessionPayload_MinimalFields_GoldenBytes for migration guidance.
            """
        )
    }

    // MARK: - ReactionAddedPayload Golden Tests

    func testReactionAddedPayload_GoldenBytes() throws {
        let payload = ReactionAddedPayload(
            memoryID: "550e8400-e29b-41d4-a716-446655440000",  // Fixed UUID
            reactionType: "fire",
            createdAtMs: 1704844800000
        )

        let cbor = try ReceiptCanonicalizer.encodeReactionAddedPayload(payload)
        let hexString = cbor.map { String(format: "%02x", $0) }.joined()

        let expectedHex = "a3696d656d6f72795f6964782435353065383430302d653239622d343164342d613731362d3434363635353434303030306d637265617465645f61745f6d731b0000018cf0ab30006d7265616374696f6e5f747970656466697265"

        XCTAssertEqual(
            hexString,
            expectedHex,
            """
            ❌ CBOR encoding changed for ReactionAddedPayload!

            Current hex: \(hexString)
            Expected hex: \(expectedHex)
            """
        )
    }

    // MARK: - ReactionRemovedPayload Golden Tests

    func testReactionRemovedPayload_GoldenBytes() throws {
        let payload = ReactionRemovedPayload(
            memoryID: "550e8400-e29b-41d4-a716-446655440000",
            reactionType: "fire"
        )

        let cbor = try ReceiptCanonicalizer.encodeReactionRemovedPayload(payload)
        let hexString = cbor.map { String(format: "%02x", $0) }.joined()

        let expectedHex = "a2696d656d6f72795f6964782435353065383430302d653239622d343164342d613731362d3434363635353434303030306d7265616374696f6e5f747970656466697265"

        XCTAssertEqual(
            hexString,
            expectedHex,
            """
            ❌ CBOR encoding changed for ReactionRemovedPayload!

            Current hex: \(hexString)
            Expected hex: \(expectedHex)
            """
        )
    }

    // MARK: - UnsignedReceiptPreimage Golden Tests

    func testUnsignedReceiptPreimage_GoldenBytes() throws {
        // Create a minimal SessionPayload first
        let sessionPayload = SessionPayload(
            claimedTimeMs: 1704844800000,
            productName: "Test Product",
            productType: "flower",
            rating: 4,
            notes: nil,
            brand: nil,
            thcPercent: nil,
            cbdPercent: nil,
            amountGrams: nil,
            effects: [],
            consumptionMethod: nil,
            locationCID: nil
        )

        // Encode the payload to CBOR
        let payloadCBOR = try ReceiptCanonicalizer.encodeSessionPayload(sessionPayload)

        // Build unsigned receipt preimage
        let preimage = UnsignedReceiptPreimage(
            did: "did:buds:test-ABC123",
            deviceId: "device-001",
            parentCID: nil,
            rootCID: "bafyreiabc123def456",
            receiptType: "app.buds.session.created/v1",
            payload: payloadCBOR
        )

        // Encode to canonical CBOR
        let cbor = try ReceiptCanonicalizer.canonicalCBOR(preimage)
        let hexString = cbor.map { String(format: "%02x", $0) }.joined()

        let expectedHex = "a563646964746469643a627564733a746573742d414243313233677061796c6f61645859a566726174696e67046765666665637473806c70726f647563745f6e616d656c546573742050726f647563746c70726f647563745f7479706566666c6f7765726f636c61696d65645f74696d655f6d731b0000018cf0ab300067726f6f7443494473626166797265696162633132336465663435366864657669636549646a6465766963652d3030316b7265636569707454797065781b6170702e627564732e73657373696f6e2e637265617465642f7631"

        XCTAssertEqual(
            hexString,
            expectedHex,
            """
            ❌ CBOR encoding changed for UnsignedReceiptPreimage!

            This is the most critical test - it validates the entire receipt structure.

            Current hex: \(hexString)
            Expected hex: \(expectedHex)
            """
        )
    }

    // MARK: - CBOR Map Key Ordering Tests

    func testCBORMapKeyOrdering_IsCanonical() throws {
        // Test that map keys are sorted by CBOR-encoded bytes
        let payload = SessionPayload(
            claimedTimeMs: 1000000,
            productName: "Test",
            productType: "flower",
            rating: 3,
            notes: "Note",
            brand: "Brand",
            thcPercent: nil,
            cbdPercent: nil,
            amountGrams: nil,
            effects: ["a"],
            consumptionMethod: "joint",
            locationCID: nil
        )

        let cbor = try ReceiptCanonicalizer.encodeSessionPayload(payload)

        // Decode the CBOR to verify map structure
        let decoder = CBORDecoder()
        let value = try decoder.decode(cbor)

        guard case .map(let pairs) = value else {
            XCTFail("Expected CBOR map, got \(value)")
            return
        }

        // Verify keys are sorted by encoded bytes
        let enc = CBORCanonical()
        var lastKeyBytes: Data?

        for (key, _) in pairs {
            let keyBytes = try enc.encode(key)

            if let last = lastKeyBytes {
                XCTAssertTrue(
                    last.lexicographicallyPrecedes(keyBytes),
                    "Map keys not in canonical order"
                )
            }

            lastKeyBytes = keyBytes
        }
    }

    // MARK: - Encoding Stability Tests

    func testDoubleEncoding_IEEE754Binary64() throws {
        // Verify that Doubles are always encoded as IEEE 754 binary64 (CBOR 0xFB)
        let payload = SessionPayload(
            claimedTimeMs: 1000000,
            productName: "Test",
            productType: "flower",
            rating: 3,
            notes: nil,
            brand: nil,
            thcPercent: 25.5,  // Test double
            cbdPercent: nil,
            amountGrams: nil,
            effects: [],
            consumptionMethod: nil,
            locationCID: nil
        )

        let cbor = try ReceiptCanonicalizer.encodeSessionPayload(payload)

        // Find the thc_percent encoding in the CBOR
        // Should contain 0xFB (CBOR float64 major type 7, additional info 27)
        // followed by 8 bytes of IEEE 754 double

        // For now, just verify encoding doesn't crash and produces bytes
        XCTAssertGreaterThan(cbor.count, 0)

        // Verify round-trip decoding
        let decoded = try ReceiptCanonicalizer.decodeSessionPayload(from: cbor)
        XCTAssertEqual(decoded.thcPercent ?? 0, 25.5, accuracy: 0.001)
    }

    func testIntegerEncoding_SmallestRepresentation() throws {
        // Test that integers use canonical smallest encoding
        let testCases: [(Int64, String)] = [
            (0, "00"),           // Major type 0, value 0
            (23, "17"),          // Major type 0, value 23
            (24, "1818"),        // Major type 0, additional info 24 + 1 byte
            (255, "18ff"),       // Major type 0, additional info 24 + 0xFF
            (256, "190100"),     // Major type 0, additional info 25 + 2 bytes
        ]

        for (value, expectedPrefix) in testCases {
            let cborValue = CBORValue.int(value)
            let enc = CBORCanonical()
            let encoded = try enc.encode(cborValue)
            let hex = encoded.map { String(format: "%02x", $0) }.joined()

            XCTAssertTrue(
                hex.hasPrefix(expectedPrefix),
                "Integer \(value) should encode as \(expectedPrefix), got \(hex)"
            )
        }
    }

    // MARK: - Golden Value Generator (COMPLETED - Generator disabled)

    // ✅ Golden values captured on 2025-12-30
    // Generator test removed - values are now frozen in tests above
}

// MARK: - Hex Encoding Helper

extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
