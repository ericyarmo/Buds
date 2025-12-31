//
//  GenerateGoldenValues.swift
//  BudsTests
//
//  Temporary script to generate CBOR golden values
//  Run this once, capture output, update CBORCanonicalityTests.swift
//
//  Created by Claude Code on 12/30/25.
//

import Foundation
@testable import Buds

/// Helper to generate golden hex values for CBOR canonicality tests
enum GoldenValueGenerator {

    static func generateAll() throws {
        print("=== CBOR Golden Values Generator ===\n")

        try generateSessionPayloadMinimal()
        try generateSessionPayloadFull()
        try generateReactionAddedPayload()
        try generateReactionRemovedPayload()
        try generateUnsignedReceiptPreimage()

        print("\n=== Done! Copy these hex values to CBORCanonicalityTests.swift ===")
    }

    private static func generateSessionPayloadMinimal() throws {
        print("📦 SessionPayload (minimal fields)")

        let payload = SessionPayload(
            claimedTimeMs: 1704844800000,
            productName: "Blue Dream",
            productType: "flower",
            rating: 5,
            notes: "Great for focus",
            brand: nil,
            thcPercent: nil,
            cbdPercent: nil,
            amountGrams: nil,
            effects: ["creative", "relaxed"],
            consumptionMethod: nil,
            locationCID: nil
        )

        let cbor = try ReceiptCanonicalizer.encodeSessionPayload(payload)
        let hex = cbor.map { String(format: "%02x", $0) }.joined()

        print("   Hex: \(hex)")
        print("   Length: \(cbor.count) bytes\n")
    }

    private static func generateSessionPayloadFull() throws {
        print("📦 SessionPayload (all fields)")

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
            effects: ["creative", "euphoric", "relaxed"],
            consumptionMethod: "joint",
            locationCID: "bafyreiabc123"
        )

        let cbor = try ReceiptCanonicalizer.encodeSessionPayload(payload)
        let hex = cbor.map { String(format: "%02x", $0) }.joined()

        print("   Hex: \(hex)")
        print("   Length: \(cbor.count) bytes\n")
    }

    private static func generateReactionAddedPayload() throws {
        print("📦 ReactionAddedPayload")

        let payload = ReactionAddedPayload(
            memoryID: "550e8400-e29b-41d4-a716-446655440000",
            reactionType: "fire",
            createdAtMs: 1704844800000
        )

        let cbor = try ReceiptCanonicalizer.encodeReactionAddedPayload(payload)
        let hex = cbor.map { String(format: "%02x", $0) }.joined()

        print("   Hex: \(hex)")
        print("   Length: \(cbor.count) bytes\n")
    }

    private static func generateReactionRemovedPayload() throws {
        print("📦 ReactionRemovedPayload")

        let payload = ReactionRemovedPayload(
            memoryID: "550e8400-e29b-41d4-a716-446655440000",
            reactionType: "fire"
        )

        let cbor = try ReceiptCanonicalizer.encodeReactionRemovedPayload(payload)
        let hex = cbor.map { String(format: "%02x", $0) }.joined()

        print("   Hex: \(hex)")
        print("   Length: \(cbor.count) bytes\n")
    }

    private static func generateUnsignedReceiptPreimage() throws {
        print("📦 UnsignedReceiptPreimage")

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

        let payloadCBOR = try ReceiptCanonicalizer.encodeSessionPayload(sessionPayload)

        let preimage = UnsignedReceiptPreimage(
            did: "did:buds:test-ABC123",
            deviceId: "device-001",
            parentCID: nil,
            rootCID: "bafyreiabc123def456",
            receiptType: "app.buds.session.created/v1",
            payload: payloadCBOR
        )

        let cbor = try ReceiptCanonicalizer.canonicalCBOR(preimage)
        let hex = cbor.map { String(format: "%02x", $0) }.joined()

        print("   Hex: \(hex)")
        print("   Length: \(cbor.count) bytes\n")
    }
}
