//
//  ShareManager.swift
//  Buds
//
//  Phase 6: Memory sharing to Circle with E2EE
//

import Foundation
import Combine
import GRDB

@MainActor
class ShareManager: ObservableObject {
    static let shared = ShareManager()
    @Published var isSharing = false

    private init() {}

    /// Share memory to Circle members
    func shareMemory(memoryCID: String, with circleDIDs: [String]) async throws {
        isSharing = true
        defer { isSharing = false }

        // Fetch raw CBOR from database
        let rawCBOR = try await Database.shared.readAsync { db in
            try UCRHeaderRow.fetchOne(db, sql: "SELECT * FROM ucr_headers WHERE cid = ?", arguments: [memoryCID])?.rawCBOR
        }
        guard let rawCBOR = rawCBOR else {
            throw ShareError.receiptNotFound
        }

        // Lookup devices for all Circle members
        let devices = try await DeviceManager.shared.getDevices(for: circleDIDs)
        guard !devices.isEmpty else {
            throw ShareError.noDevicesFound
        }

        // Encrypt message for all devices
        let encrypted = try await E2EEManager.shared.encryptMessage(
            receiptCID: memoryCID,
            rawCBOR: rawCBOR,
            recipientDevices: devices
        )

        // Send to relay
        try await RelayClient.shared.sendMessage(encrypted)

        print("✅ Memory shared: \(memoryCID) to \(devices.count) devices")
    }
}

// MARK: - Errors

enum ShareError: Error, LocalizedError {
    case receiptNotFound
    case noDevicesFound

    var errorDescription: String? {
        switch self {
        case .receiptNotFound:
            return "Memory receipt not found"
        case .noDevicesFound:
            return "No devices found for recipients"
        }
    }
}
