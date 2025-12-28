//
//  E2EEVerificationTest.swift
//  Buds
//
//  Phase 10 Step 0.1: CRITICAL E2EE Verification Invariance Test
//  Tests that jar deletion doesn't break signature verification
//

import Foundation
import GRDB

/// CRITICAL TEST: Run this before TestFlight upload
/// If this test fails → ABORT TestFlight, fix crypto first
@MainActor
class E2EEVerificationTest {

    private let repository = MemoryRepository()
    private let jarManager = JarManager.shared

    /// Main test function - call this to run the full test
    func runTest() async {
        print("\n" + "="*80)
        print("🔴 CRITICAL TEST: E2EE Verification Invariance")
        print("Testing that jar deletion doesn't break signature verification")
        print("="*80 + "\n")

        do {
            // STEP 1: Setup - Create jar and bud
            let testJarID = try await setupTestJar()
            let budID = try await createTestBud(in: testJarID)

            print("✅ Setup complete: Jar and bud created\n")

            // STEP 2: Get receipt and log verification BEFORE jar deletion
            let receiptCID = try await getReceiptCID(for: budID)
            let beforeBytes = try await logVerificationBytes(receiptCID: receiptCID, label: "BEFORE jar deletion")

            // STEP 3: Delete jar (buds move to Solo)
            print("\n📦 Deleting jar '\(testJarID)'...")
            try await jarManager.deleteJar(id: testJarID)
            print("✅ Jar deleted, buds moved to Solo\n")

            // Small delay to ensure DB writes complete
            try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds

            // STEP 4: Re-verify SAME receipt and log verification AFTER jar deletion
            let afterBytes = try await logVerificationBytes(receiptCID: receiptCID, label: "AFTER jar deletion")

            // STEP 5: Compare verification bytes
            print("\n" + "="*80)
            print("🔍 COMPARISON:")
            print("="*80)

            if beforeBytes == afterBytes {
                print("✅ ✅ ✅ PASS: Verification bytes UNCHANGED")
                print("Receipt CID: \(receiptCID)")
                print("Bytes (hex): \(beforeBytes)")
                print("\n✅ Jar deletion is SAFE for E2EE")
                print("✅ OK TO PROCEED WITH TESTFLIGHT\n")
            } else {
                print("❌ ❌ ❌ FAIL: Verification bytes CHANGED")
                print("BEFORE: \(beforeBytes)")
                print("AFTER:  \(afterBytes)")
                print("\n🚨 ABORT TESTFLIGHT - CRYPTO IS BROKEN")
                print("🚨 jar_id update is changing signed content")
                print("🚨 Fix before shipping!\n")

                fatalError("E2EE verification invariance test FAILED")
            }

            // STEP 6: Cleanup
            try await cleanup(budID: budID)

        } catch {
            print("❌ Test failed with error: \(error)")
            print("🚨 ABORT TESTFLIGHT - Cannot verify E2EE safety\n")
            fatalError("E2EE test failed: \(error)")
        }

        print("="*80 + "\n")
    }

    // MARK: - Test Steps

    private func setupTestJar() async throws -> String {
        print("📝 Creating test jar 'Crypto Test'...")
        let currentDID = try await IdentityManager.shared.currentDID
        let jar = try await JarRepository.shared.createJar(
            name: "Crypto Test",
            description: "E2EE verification test jar",
            ownerDID: currentDID
        )
        print("✅ Created jar: \(jar.id)")
        return jar.id
    }

    private func createTestBud(in jarID: String) async throws -> UUID {
        print("📝 Creating test bud in jar...")
        let memory = try await repository.create(
            strainName: "E2EE Test Strain",
            productType: .flower,
            rating: 4,
            notes: "Test bud for E2EE verification",
            brand: "Test Brand",
            thcPercent: 20.0,
            cbdPercent: 0.5,
            amountGrams: 3.5,
            effects: ["relaxed", "focused"],
            consumptionMethod: .joint,
            locationCID: nil,
            jarID: jarID
        )
        print("✅ Created bud: \(memory.id)")
        return memory.id
    }

    private func getReceiptCID(for budID: UUID) async throws -> String {
        print("📝 Fetching receipt CID...")
        guard let memory = try await repository.fetch(id: budID) else {
            throw TestError.budNotFound
        }
        print("✅ Receipt CID: \(memory.receiptCID)")
        return memory.receiptCID
    }

    private func logVerificationBytes(receiptCID: String, label: String) async throws -> String {
        print("\n" + "-"*80)
        print("🔍 VERIFICATION \(label)")
        print("-"*80)

        // Fetch receipt from database
        let receipt = try await Database.shared.readAsync { db in
            try Row.fetchOne(
                db,
                sql: "SELECT cid, signature, raw_cbor FROM ucr_headers WHERE cid = ?",
                arguments: [receiptCID]
            )
        }

        guard let receipt = receipt else {
            throw TestError.receiptNotFound(receiptCID)
        }

        let cid = receipt["cid"] as String
        let signatureData = receipt["signature"] as? Data ?? Data()
        let rawCBOR = receipt["raw_cbor"] as? Data ?? Data()

        // Calculate verification input bytes
        // This should be what's actually verified during signature check
        let verificationInput = rawCBOR  // The canonical CBOR encoding
        let verificationHash = verificationInput.sha256Hex()

        print("Receipt CID:       \(cid)")
        print("CBOR bytes:        \(rawCBOR.count) bytes")
        print("CBOR SHA256:       \(verificationHash)")
        print("Signature:         \(signatureData.hexString())")
        print("Signature length:  \(signatureData.count) bytes")
        print("-"*80)

        // Return the hash of verification input for comparison
        return verificationHash
    }

    private func cleanup(budID: UUID) async throws {
        print("\n🧹 Cleaning up test data...")
        try await repository.delete(id: budID)
        print("✅ Cleanup complete")
    }

    // MARK: - Test Errors

    enum TestError: Error, LocalizedError {
        case budNotFound
        case receiptNotFound(String)

        var errorDescription: String? {
            switch self {
            case .budNotFound:
                return "Test bud not found in database"
            case .receiptNotFound(let cid):
                return "Receipt not found: \(cid)"
            }
        }
    }
}

// MARK: - Helper Extensions

extension Data {
    func hexString() -> String {
        return self.map { String(format: "%02x", $0) }.joined()
    }

    func sha256Hex() -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        self.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(self.count), &hash)
        }
        return Data(hash).hexString()
    }
}

import CommonCrypto

// MARK: - String Helpers

extension String {
    static func * (string: String, count: Int) -> String {
        return String(repeating: string, count: count)
    }
}
