//
//  IdentityManager.swift
//  Buds
//
//  Manages cryptographic identity (Ed25519 + X25519 keypairs)
//  Stores keys securely in iOS Keychain
//
//  Phase 10.3 Module 0.2: Phone-based DID derivation
//

import Foundation
import CryptoKit
import FirebaseAuth

actor IdentityManager {
    static let shared = IdentityManager()

    private let keychainService = "app.getbuds.identity"

    // MARK: - Ed25519 Keypair (Signing)

    /// Get or generate Ed25519 signing keypair
    func getSigningKeypair() throws -> Curve25519.Signing.PrivateKey {
        if let existing = try loadFromKeychain(key: "ed25519_private") {
            return try Curve25519.Signing.PrivateKey(rawRepresentation: existing)
        }

        // Generate new keypair
        let keypair = Curve25519.Signing.PrivateKey()
        try saveToKeychain(key: "ed25519_private", data: keypair.rawRepresentation)
        print("✅ Generated new Ed25519 signing keypair")
        return keypair
    }

    /// Sign data with Ed25519
    func sign(data: Data) async throws -> Data {
        let privateKey = try getSigningKeypair()
        return try privateKey.signature(for: data)
    }

    /// Verify Ed25519 signature
    func verify(signature: Data, for data: Data, publicKey: Data) throws -> Bool {
        let pubKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
        return pubKey.isValidSignature(signature, for: data)
    }

    // MARK: - X25519 Keypair (Encryption/Key Agreement)

    /// Get or generate X25519 encryption keypair
    func getEncryptionKeypair() throws -> Curve25519.KeyAgreement.PrivateKey {
        if let existing = try loadFromKeychain(key: "x25519_private") {
            return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: existing)
        }

        // Generate new keypair
        let keypair = Curve25519.KeyAgreement.PrivateKey()
        try saveToKeychain(key: "x25519_private", data: keypair.rawRepresentation)
        print("✅ Generated new X25519 encryption keypair")
        return keypair
    }

    // MARK: - DID Generation (Phase 10.3 Module 0.2)

    /// Generate DID from phone number + account salt
    /// Format: did:phone:SHA256(phone + salt)
    ///
    /// This enables multi-device identity:
    /// - All devices with same phone → same DID
    /// - Each device has own signing/encryption keys
    /// - Salt prevents DID → phone reversal
    func getDID() async throws -> String {
        // Get phone from Firebase Auth
        guard let phone = Auth.auth().currentUser?.phoneNumber else {
            throw IdentityError.phoneNotAvailable
        }

        // Get or create account salt (cached locally)
        let salt = try await getAccountSalt()

        // Derive DID: did:phone:SHA256(phone + salt)
        return deriveDID(phoneNumber: phone, accountSalt: salt)
    }

    /// Derive DID from phone + salt
    private func deriveDID(phoneNumber: String, accountSalt: String) -> String {
        let combined = phoneNumber + accountSalt
        guard let data = combined.data(using: .utf8) else {
            fatalError("Failed to encode phone + salt")
        }

        let hash = SHA256.hash(data: data)
        let hashHex = hash.map { String(format: "%02x", $0) }.joined()
        return "did:phone:\(hashHex)"
    }

    /// Get account salt (cached in keychain)
    /// Fetches from relay on first call, caches locally for subsequent calls
    private func getAccountSalt() async throws -> String {
        // Check keychain cache first
        if let cached = try loadStringFromKeychain(key: "account_salt") {
            return cached
        }

        // Fetch from relay
        let salt = try await RelayClient.shared.getOrCreateAccountSalt()

        // Cache in keychain
        try saveStringToKeychain(key: "account_salt", value: salt)
        print("✅ Cached account salt in keychain")

        return salt
    }

    // MARK: - Device ID

    /// Device ID property (for compatibility with Phase 6)
    var deviceId: String {
        get throws {
            try getDeviceID()
        }
    }

    /// Get or generate stable device UUID
    func getDeviceID() throws -> String {
        if let existing = try loadStringFromKeychain(key: "device_id") {
            return existing
        }

        let deviceID = UUID().uuidString
        try saveStringToKeychain(key: "device_id", value: deviceID)
        print("✅ Generated device ID: \(deviceID)")
        return deviceID
    }

    // MARK: - DID Property (Convenience)

    /// Current DID property (async - Phase 10.3 Module 0.2)
    var currentDID: String {
        get async throws {
            try await getDID()
        }
    }

    // MARK: - Keypair Getters (Phase 6 compatibility)

    /// Get X25519 keypair as tuple
    func getX25519Keypair() throws -> (publicKey: Curve25519.KeyAgreement.PublicKey, privateKey: Curve25519.KeyAgreement.PrivateKey) {
        let privateKey = try getEncryptionKeypair()
        return (privateKey.publicKey, privateKey)
    }

    /// Get Ed25519 keypair as tuple
    func getEd25519Keypair() throws -> (publicKey: Curve25519.Signing.PublicKey, privateKey: Curve25519.Signing.PrivateKey) {
        let privateKey = try getSigningKeypair()
        return (privateKey.publicKey, privateKey)
    }

    // MARK: - Keychain Helpers

    private func saveToKeychain(key: String, data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        // Delete existing item first
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw IdentityError.keychainSaveFailed(status)
        }
    }

    private func loadFromKeychain(key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw IdentityError.keychainLoadFailed(status)
        }

        return result as? Data
    }

    private func saveStringToKeychain(key: String, value: String) throws {
        try saveToKeychain(key: key, data: Data(value.utf8))
    }

    private func loadStringFromKeychain(key: String) throws -> String? {
        guard let data = try loadFromKeychain(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Reset (for testing)

    func resetIdentity() throws {
        let keys = ["ed25519_private", "x25519_private", "device_id"]
        for key in keys {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: key
            ]
            SecItemDelete(query as CFDictionary)
        }
        print("⚠️ Identity reset")
    }
}

// MARK: - Errors

enum IdentityError: Error, LocalizedError {
    case keychainSaveFailed(OSStatus)
    case keychainLoadFailed(OSStatus)
    case invalidPublicKey
    case signatureFailed
    case phoneNotAvailable  // Phase 10.3 Module 0.2

    var errorDescription: String? {
        switch self {
        case .keychainSaveFailed(let status):
            return "Failed to save to keychain: \(status)"
        case .keychainLoadFailed(let status):
            return "Failed to load from keychain: \(status)"
        case .invalidPublicKey:
            return "Invalid public key format"
        case .signatureFailed:
            return "Signature generation failed"
        case .phoneNotAvailable:
            return "Phone number not available (user not authenticated)"
        }
    }
}

// MARK: - Base58 Encoding

struct Base58 {
    private static let alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    private static let base = alphabet.count

    static func encode(_ data: Data) -> String {
        var bytes = [UInt8](data)
        var encoded = ""

        // Count leading zeros
        var leadingZeros = 0
        for byte in bytes {
            if byte == 0 {
                leadingZeros += 1
            } else {
                break
            }
        }

        // Convert to base58 using digit-by-digit encoding (avoids overflow)
        var digits: [Int] = []

        for byte in bytes {
            var carry = Int(byte)
            for i in 0..<digits.count {
                carry = digits[i] * 256 + carry
                digits[i] = carry % base
                carry = carry / base
            }
            while carry > 0 {
                digits.append(carry % base)
                carry = carry / base
            }
        }

        // Convert digits to string (reverse order)
        for digit in digits.reversed() {
            let index = alphabet.index(alphabet.startIndex, offsetBy: digit)
            encoded.append(alphabet[index])
        }

        // Add leading '1's for leading zeros
        let leading = String(repeating: alphabet.first!, count: leadingZeros)
        return leading + encoded
    }

    static func decode(_ string: String) -> Data? {
        var leadingZeros = 0

        for char in string {
            if char == alphabet.first {
                leadingZeros += 1
            } else {
                break
            }
        }

        // Decode using digit-by-digit approach (avoids overflow)
        var bytes: [UInt8] = []

        for char in string {
            guard let index = alphabet.firstIndex(of: char) else { return nil }
            let digit = alphabet.distance(from: alphabet.startIndex, to: index)

            var carry = digit
            for i in 0..<bytes.count {
                carry = Int(bytes[i]) * base + carry
                bytes[i] = UInt8(carry % 256)
                carry = carry / 256
            }
            while carry > 0 {
                bytes.append(UInt8(carry % 256))
                carry = carry / 256
            }
        }

        // Reverse to get proper byte order and add leading zeros
        bytes.reverse()
        bytes.insert(contentsOf: [UInt8](repeating: 0, count: leadingZeros), at: 0)

        return Data(bytes)
    }
}
