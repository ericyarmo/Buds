//
//  RelayClient.swift
//  Buds
//
//  Phase 6: API client for Cloudflare Workers relay
//

import Foundation
import FirebaseAuth
import CryptoKit

class RelayClient {
    static let shared = RelayClient()
    let baseURL = "https://buds-relay.getstreams.workers.dev"  // Production relay

    private init() {}

    func authHeader() async throws -> [String: String] {  // Changed to internal for extensions
        guard let user = Auth.auth().currentUser else {
            throw RelayError.notAuthenticated
        }
        let token = try await user.getIDToken()

        // DEBUG: Print token for testing (remove in production)
        print("🔐 Firebase ID Token: \(token)")

        return ["Authorization": "Bearer \(token)"]
    }

    // MARK: - Device Registration

    func registerDevice(deviceId: String, deviceName: String, pubkeyX25519: String, pubkeyEd25519: String, ownerDID: String, phoneNumber: String, apnsToken: String? = nil) async throws {
        let headers = try await authHeader()
        let url = URL(string: "\(baseURL)/api/devices/register")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }

        // Phase 10.3 Module 0.3: Send plaintext phone number
        // Server will encrypt it server-side for storage
        // Security: Phone sent over HTTPS (TLS), encrypted at rest in DB
        var body: [String: Any] = [
            "device_id": deviceId,
            "device_name": deviceName,
            "owner_did": ownerDID,
            "phone_number": phoneNumber,  // Changed from owner_phone_hash to phone_number
            "pubkey_x25519": pubkeyX25519,
            "pubkey_ed25519": pubkeyEd25519
        ]

        // Add APNs token if provided
        if let apnsToken = apnsToken {
            body["apns_token"] = apnsToken
        }

        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, res) = try await URLSession.shared.data(for: req)
        let statusCode = (res as? HTTPURLResponse)?.statusCode ?? 0

        if statusCode != 200 && statusCode != 201 {
            // Log the error response for debugging
            if let errorBody = String(data: data, encoding: .utf8) {
                print("❌ Device registration failed (HTTP \(statusCode)): \(errorBody)")
            } else {
                print("❌ Device registration failed (HTTP \(statusCode)): No response body")
            }
            throw RelayError.serverError
        }
    }

    // MARK: - Phone Hashing

    private func hashPhoneNumber(_ phoneNumber: String) throws -> String {
        // Hash exactly as-is (E.164 format with + sign)
        // Must match relay's hashPhone function in crypto.ts
        guard let data = phoneNumber.data(using: .utf8) else {
            throw RelayError.invalidResponse
        }

        // SHA-256 hash
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Account Salt (Phase 10.3 Module 0.2)

    /// Get or create account salt for phone-based DID derivation
    /// DID = did:phone:SHA256(phone + salt)
    func getOrCreateAccountSalt() async throws -> String {
        let headers = try await authHeader()
        let url = URL(string: "\(baseURL)/api/account/salt")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }

        // No body needed - endpoint uses authenticated user's phone

        let (data, res) = try await URLSession.shared.data(for: req)
        let statusCode = (res as? HTTPURLResponse)?.statusCode ?? 0

        guard statusCode == 200 else {
            if let errorBody = String(data: data, encoding: .utf8) {
                print("❌ Account salt request failed (HTTP \(statusCode)): \(errorBody)")
            }
            throw RelayError.serverError
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let salt = json?["salt"] as? String else {
            print("❌ Failed to extract salt from response")
            throw RelayError.invalidResponse
        }

        let wasCreated = (json?["created"] as? Bool) ?? false
        if wasCreated {
            print("✅ Generated new account salt")
        } else {
            print("✅ Retrieved existing account salt")
        }

        return salt
    }

    // MARK: - DID Lookup

    func lookupDID(phoneNumber: String) async throws -> String {
        let headers = try await authHeader()
        let url = URL(string: "\(baseURL)/api/lookup/did")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }

        // Phase 10.3 Module 0.3: Send plaintext phone number
        // Server will encrypt it server-side for deterministic lookup
        print("[DEBUG] Looking up DID for phone number: \(phoneNumber)")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["phone_number": phoneNumber])

        let (data, res) = try await URLSession.shared.data(for: req)
        let statusCode = (res as? HTTPURLResponse)?.statusCode ?? 0
        print("[DEBUG] DID lookup response status: \(statusCode)")

        // Log raw response
        if let responseBody = String(data: data, encoding: .utf8) {
            print("[DEBUG] DID lookup response body: \(responseBody)")
        }

        if statusCode == 404 {
            throw RelayError.userNotFound
        }
        guard statusCode == 200 else {
            throw RelayError.serverError
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        print("[DEBUG] Parsed JSON: \(String(describing: json))")

        guard let did = json?["did"] as? String else {
            print("[DEBUG] Failed to extract DID from response")
            throw RelayError.invalidResponse
        }

        print("[DEBUG] Successfully extracted DID: \(did)")
        return did
    }

    // MARK: - Device Queries

    func getDevices(for dids: [String]) async throws -> [[String: Any]] {
        let headers = try await authHeader()
        let url = URL(string: "\(baseURL)/api/devices/list")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }

        print("[DEBUG] Getting devices for DIDs: \(dids)")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["dids": dids])

        let (data, res) = try await URLSession.shared.data(for: req)
        let statusCode = (res as? HTTPURLResponse)?.statusCode ?? 0
        print("[DEBUG] Get devices response status: \(statusCode)")

        // Log raw response
        if let responseBody = String(data: data, encoding: .utf8) {
            print("[DEBUG] Get devices response body: \(responseBody)")
        }

        guard statusCode == 200 else {
            throw RelayError.serverError
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        print("[DEBUG] Parsed JSON: \(String(describing: json))")

        // Relay returns devices grouped by DID: { "devices": { "did:buds:xxx": [...] } }
        guard let devicesByDid = json?["devices"] as? [String: [[String: Any]]] else {
            print("[DEBUG] Failed to extract devices dictionary from response")
            throw RelayError.invalidResponse
        }

        // Flatten into array with owner_did added to each device
        var allDevices: [[String: Any]] = []
        for (ownerDid, devicesArray) in devicesByDid {
            for var device in devicesArray {
                device["owner_did"] = ownerDid
                device["status"] = "active" // Relay only returns active devices
                allDevices.append(device)
            }
        }

        print("[DEBUG] Successfully extracted \(allDevices.count) devices")
        return allDevices
    }

    // MARK: - Message Send/Receive

    func sendMessage(_ msg: EncryptedMessage) async throws {
        let headers = try await authHeader()
        let url = URL(string: "\(baseURL)/api/messages/send")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        req.httpBody = try encoder.encode(msg)

        // Debug log the request
        if let requestBody = String(data: req.httpBody ?? Data(), encoding: .utf8) {
            print("[DEBUG] Send message request body: \(requestBody)")
        }

        let (data, res) = try await URLSession.shared.data(for: req)
        let statusCode = (res as? HTTPURLResponse)?.statusCode ?? 0
        print("[DEBUG] Send message response status: \(statusCode)")

        // Log raw response
        if let responseBody = String(data: data, encoding: .utf8) {
            print("[DEBUG] Send message response body: \(responseBody)")
        }

        guard statusCode == 200 || statusCode == 201 else {
            throw RelayError.serverError
        }
    }

    func getInbox(for did: String) async throws -> [EncryptedMessage] {
        let headers = try await authHeader()
        let url = URL(string: "\(baseURL)/api/messages/inbox?did=\(did)")!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }

        let (data, res) = try await URLSession.shared.data(for: req)
        guard (res as? HTTPURLResponse)?.statusCode == 200 else {
            throw RelayError.serverError
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let msgs = json?["messages"] as? [[String: Any]] else {
            throw RelayError.invalidResponse
        }

        return try msgs.map { dict in
            guard let id = dict["message_id"] as? String,
                  let cid = dict["receipt_cid"] as? String,
                  let payload = dict["encrypted_payload"] as? String,
                  let keys = dict["wrapped_keys"] as? [String: String],
                  let senderDID = dict["sender_did"] as? String,
                  let senderDevice = dict["sender_device_id"] as? String,
                  let createdMs = dict["created_at"] as? Int64,
                  let signature = dict["signature"] as? String
            else {
                throw RelayError.invalidResponse
            }

            return EncryptedMessage(
                messageId: id,
                receiptCID: cid,
                encryptedPayload: payload,
                wrappedKeys: keys,
                senderDID: senderDID,
                senderDeviceId: senderDevice,
                recipientDIDs: [],
                createdAt: Date(timeIntervalSince1970: Double(createdMs) / 1000),
                signature: signature
            )
        }
    }

    // Delete message after processing
    func deleteMessage(messageId: String) async throws {
        let headers = try await authHeader()
        let url = URL(string: "\(baseURL)/api/messages/\(messageId)")!
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }

        let (_, res) = try await URLSession.shared.data(for: req)
        let statusCode = (res as? HTTPURLResponse)?.statusCode ?? 0

        guard statusCode == 200 || statusCode == 204 else {
            throw RelayError.serverError
        }

        print("✅ Message \(messageId) deleted from relay")
    }

    // MARK: - Jar Discovery (Phase 10.3 Module 6.5)

    /// List all jars where the user is an active member
    /// Enables discovering jars the user has been added to
    func listUserJars() async throws -> [(jarId: String, role: String)] {
        let headers = try await authHeader()
        let url = URL(string: "\(baseURL)/api/jars/list")!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }

        let (data, res) = try await URLSession.shared.data(for: req)
        let statusCode = (res as? HTTPURLResponse)?.statusCode ?? 0

        guard statusCode == 200 else {
            throw RelayError.serverError
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let jarsArray = json?["jars"] as? [[String: Any]] else {
            throw RelayError.invalidResponse
        }

        return try jarsArray.map { dict in
            guard let jarId = dict["jar_id"] as? String,
                  let role = dict["role"] as? String else {
                throw RelayError.invalidResponse
            }
            return (jarId: jarId, role: role)
        }
    }
}

// MARK: - Errors

enum RelayError: Error, LocalizedError {
    case notAuthenticated
    case serverError
    case userNotFound
    case invalidResponse
    case httpError(statusCode: Int, message: String)  // Phase 10.3 Module 1: Detailed HTTP errors

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User not authenticated"
        case .serverError:
            return "Relay server error"
        case .userNotFound:
            return "User not found"
        case .invalidResponse:
            return "Invalid relay response"
        case .httpError(let statusCode, let message):
            return "HTTP \(statusCode): \(message)"
        }
    }
}
