//
//  DeviceManager.swift
//  Buds
//
//  Phase 6: Device registration and multi-device management
//

import Foundation
import UIKit
import Combine
import CryptoKit
import GRDB
import FirebaseAuth

@MainActor
class DeviceManager: ObservableObject {
    static let shared = DeviceManager()
    @Published var isRegistered = false

    private init() {
        Task { await loadStatus() }
    }

    func registerDevice() async throws {
        // Get phone number from Firebase Auth
        guard let phoneNumber = Auth.auth().currentUser?.phoneNumber else {
            throw DeviceError.notAuthenticated
        }

        let identity = IdentityManager.shared
        let deviceId = try await identity.deviceId
        let did = try await identity.currentDID
        let x25519 = try await identity.getX25519Keypair()
        let ed25519 = try await identity.getEd25519Keypair()
        let name = UIDevice.current.name

        do {
            try await RelayClient.shared.registerDevice(
                deviceId: deviceId,
                deviceName: name,
                pubkeyX25519: x25519.publicKey.rawRepresentation.base64EncodedString(),
                pubkeyEd25519: ed25519.publicKey.rawRepresentation.base64EncodedString(),
                ownerDID: did,
                phoneNumber: phoneNumber
            )
        } catch let error as RelayError {
            // If already registered, that's fine - just mark as registered
            if case .serverError = error {
                print("⚠️ Device may already be registered, continuing...")
            } else {
                throw error
            }
        }

        let device = Device(
            deviceId: deviceId,
            ownerDID: did,
            deviceName: name,
            pubkeyX25519: x25519.publicKey.rawRepresentation.base64EncodedString(),
            pubkeyEd25519: ed25519.publicKey.rawRepresentation.base64EncodedString(),
            status: .active,
            registeredAt: Date(),
            lastSeenAt: Date()
        )

        // Insert or update device in local database
        try await Database.shared.writeAsync { db in
            try device.save(db)
        }
        isRegistered = true
        print("✅ Device registered: \(deviceId)")
    }

    func loadStatus() async {
        do {
            let deviceId = try await IdentityManager.shared.deviceId
            let exists = try await Database.shared.readAsync {
                try Device.filter(sql: "device_id = ?", arguments: [deviceId]).fetchOne($0) != nil
            }
            isRegistered = exists
        } catch {
            print("❌ Load device status failed: \(error)")
        }
    }

    func getDevices(for dids: [String]) async throws -> [Device] {
        let devicesData = try await RelayClient.shared.getDevices(for: dids)
        return try devicesData.map { dict in
            guard let id = dict["device_id"] as? String,
                  let owner = dict["owner_did"] as? String,
                  let name = dict["device_name"] as? String,
                  let x25519 = dict["pubkey_x25519"] as? String,
                  let ed25519 = dict["pubkey_ed25519"] as? String,
                  let statusStr = dict["status"] as? String,
                  let status = Device.DeviceStatus(rawValue: statusStr)
            else {
                throw DeviceError.invalidResponse
            }

            return Device(
                deviceId: id,
                ownerDID: owner,
                deviceName: name,
                pubkeyX25519: x25519,
                pubkeyEd25519: ed25519,
                status: status,
                registeredAt: Date(),
                lastSeenAt: nil
            )
        }
    }
}

// MARK: - Errors

enum DeviceError: Error, LocalizedError {
    case invalidResponse
    case notRegistered
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid device response"
        case .notRegistered:
            return "Device not registered"
        case .notAuthenticated:
            return "User not authenticated"
        }
    }
}
