//
//  StressTestGenerator.swift
//  Buds
//
//  Phase 10.1 Module 5.1: Stress testing with 100+ buds
//  Use this to generate test data for performance testing
//

import Foundation
import UIKit

class StressTestGenerator {
    static let shared = StressTestGenerator()
    private init() {}

    // MARK: - Test Data Arrays

    private let strainNames = [
        "Blue Dream", "Girl Scout Cookies", "OG Kush", "Sour Diesel", "Granddaddy Purple",
        "Green Crack", "Jack Herer", "White Widow", "AK-47", "Northern Lights",
        "Pineapple Express", "Durban Poison", "Purple Haze", "Strawberry Cough", "Trainwreck",
        "Chemdawg", "Gelato", "Wedding Cake", "Gorilla Glue", "Zkittlez",
        "Sunset Sherbet", "Do-Si-Dos", "Animal Cookies", "Cherry Pie", "Lemon Haze",
        "Super Silver Haze", "Critical Mass", "Bubba Kush", "Purple Kush", "Master Kush",
        "Hindu Kush", "Afghani", "LA Confidential", "Blueberry", "Blackberry Kush",
        "Raspberry Kush", "Tangie", "Clementine", "Orange Crush", "Mango Kush",
        "Pineapple Kush", "Banana Kush", "Grape Ape", "Grapefruit", "Watermelon Zkittlez"
    ]

    private let productTypes: [ProductType] = [
        .flower, .vape, .edible, .concentrate, .tincture, .topical, .other
    ]

    private let consumptionMethods: [ConsumptionMethod] = [
        .joint, .bong, .pipe, .vape, .edible, .dab, .tincture, .topical
    ]

    private let effects: [String] = [
        "relaxed", "happy", "euphoric", "uplifted", "creative",
        "energetic", "focused", "sleepy", "hungry", "giggly",
        "aroused", "tingly"
    ]

    private let notes = [
        "Great for evening relaxation. Helped with stress after a long day.",
        "Very smooth smoke, fruity taste. Uplifting and social.",
        "Strong effects, great for sleep. Couch lock for sure.",
        "Perfect daytime strain. Focused and productive without anxiety.",
        "Sweet and earthy flavor. Nice balanced high.",
        "Intense cerebral high. Very creative and giggly.",
        "Powerful indica. Knocked me out in 30 minutes.",
        "Energetic and uplifting. Great for hiking.",
        "Smooth vape, citrus notes. Clean high.",
        "Strong body high. Perfect for pain relief.",
        "Melllow and calming. Good for anxiety.",
        "Fun and social. Lots of laughs with friends.",
        "Potent! A little goes a long way.",
        "Nice flavor profile. Would buy again.",
        "Balanced hybrid. Best of both worlds."
    ]

    // MARK: - Generate Test Buds

    /// Generate multiple test buds for stress testing
    /// - Parameters:
    ///   - count: Number of buds to generate (default: 100)
    ///   - jarID: Jar ID to add buds to (default: "solo")
    ///   - completion: Callback with success/failure count
    func generateTestBuds(
        count: Int = 100,
        jarID: String = "solo",
        progress: @escaping (Int, Int) -> Void,
        completion: @escaping (Int, Int) -> Void
    ) async {
        var successCount = 0
        var failureCount = 0

        print("🧪 Starting stress test: Generating \(count) test buds...")

        for i in 0..<count {
            do {
                let memory = generateRandomMemory(jarID: jarID, index: i)
                try await saveMemory(memory)
                successCount += 1

                // Report progress every 10 buds
                if (i + 1) % 10 == 0 {
                    await MainActor.run {
                        progress(successCount, failureCount)
                    }
                    print("✅ Progress: \(i + 1)/\(count) buds created")
                }
            } catch {
                failureCount += 1
                print("❌ Failed to create bud \(i + 1): \(error)")
            }
        }

        await MainActor.run {
            completion(successCount, failureCount)
        }

        print("🎉 Stress test complete: \(successCount) success, \(failureCount) failures")
    }

    // MARK: - Generate Random Memory

    private func generateRandomMemory(jarID: String, index: Int) -> Memory {
        let strainName = strainNames.randomElement()!
        let productType = productTypes.randomElement()!
        let consumptionMethod = consumptionMethods.randomElement()!
        let rating = Int.random(in: 1...5)

        // Random number of effects (1-4)
        let effectCount = Int.random(in: 1...4)
        let selectedEffects = effects.shuffled().prefix(effectCount).map { $0 }

        // Random notes (70% chance)
        let includeNotes = Double.random(in: 0...1) > 0.3
        let selectedNotes = includeNotes ? notes.randomElement() : nil

        // Random date within last 90 days
        let randomDaysAgo = Int.random(in: 0...90)
        let createdAt = Calendar.current.date(byAdding: .day, value: -randomDaysAgo, to: Date())!

        return Memory(
            id: UUID(),
            receiptCID: "test_cid_\(index)_\(UUID().uuidString)",
            strainName: strainName,
            productType: productType,
            rating: rating,
            notes: selectedNotes,
            brand: nil,
            thcPercent: nil,
            cbdPercent: nil,
            amountGrams: nil,
            effects: selectedEffects,
            consumptionMethod: consumptionMethod,
            createdAt: createdAt,
            claimedTimeMs: Int64(createdAt.timeIntervalSince1970 * 1000),
            hasLocation: false,
            locationName: nil,
            isFavorited: false,
            isShared: false,
            imageData: [], // No images for stress test (too heavy)
            jarID: jarID,
            senderDID: nil
        )
    }

    // MARK: - Save Memory

    private func saveMemory(_ memory: Memory) async throws {
        // Save to repository using create method
        let repository = MemoryRepository()
        _ = try await repository.create(
            strainName: memory.strainName,
            productType: memory.productType,
            rating: memory.rating,
            notes: memory.notes,
            brand: memory.brand,
            thcPercent: memory.thcPercent,
            cbdPercent: memory.cbdPercent,
            amountGrams: memory.amountGrams,
            effects: memory.effects,
            consumptionMethod: memory.consumptionMethod,
            locationCID: nil,
            jarID: memory.jarID
        )
    }

    // MARK: - Clear Test Data

    /// Delete all test buds (receipts starting with "test_cid_")
    func clearTestBuds(completion: @escaping (Int) -> Void) async {
        print("🧹 Clearing test buds...")

        do {
            let repository = MemoryRepository()
            let allMemories = try await repository.fetchAll()

            var deletedCount = 0
            for memory in allMemories where memory.receiptCID.starts(with: "test_cid_") {
                try await repository.delete(id: memory.id)
                deletedCount += 1
            }

            await MainActor.run {
                completion(deletedCount)
            }

            print("✅ Cleared \(deletedCount) test buds")
        } catch {
            print("❌ Failed to clear test buds: \(error)")
            await MainActor.run {
                completion(0)
            }
        }
    }
}
