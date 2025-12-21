# Phase 6: E2EE Sharing + Relay Integration

**Last Updated:** December 20, 2025
**Prerequisites:** Phase 5 complete (Circle mechanics working)
**Estimated Time:** 8-12 hours
**Goal:** Enable users to share memories with Circle using E2EE, device registration, and Firebase-based relay

---

## Quick Start for New Agent

**If you're a fresh Claude Code agent:**

1. Read this file completely (45 min)
2. Review `/docs/E2EE_DESIGN.md` for encryption details (30 min)
3. Review Phase 5 completion in `README.md` (10 min)
4. Follow the implementation steps below sequentially
5. Test at each checkpoint before proceeding

**Current State:**
- ✅ Firebase Auth working (phone verification)
- ✅ Profile view with DID display
- ✅ Memory creation with photos
- ✅ Timeline view
- ✅ Circle mechanics (add/remove/edit members)
- ⏳ E2EE sharing (this phase)
- ⏳ Device registration (this phase)
- ⏳ Message relay via Firebase (this phase)

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Firebase Setup](#firebase-setup)
3. [Core Components](#core-components)
4. [E2EE Implementation](#e2ee-implementation)
5. [UI Updates](#ui-updates)
6. [Testing Checkpoints](#testing-checkpoints)
7. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

### What Changes in Phase 6?

**Phase 5 (Local-Only):**
- Circle members have placeholder DIDs (`did:buds:placeholder_xxx`)
- No real sharing - just UI mockup
- No relay server

**Phase 6 (E2EE Sharing):**
- Device registration on first launch (send device pubkeys to Firebase)
- Phone → DID lookup via Firebase Functions
- Share memories → Encrypt with recipient device pubkeys
- Firebase Cloud Messaging (FCM) for delivery notifications
- Recipients decrypt messages locally

### E2EE Flow (Simplified)

```
1. Alice shares memory with Bob
   ↓
2. Look up Bob's devices from Firebase Firestore
   ↓
3. Generate ephemeral AES-256 key
   ↓
4. Encrypt memory (raw CBOR) with AES-256-GCM
   ↓
5. Wrap AES key for each of Bob's devices (X25519 key agreement)
   ↓
6. Store encrypted message in Firestore
   ↓
7. Send FCM push to Bob's devices
   ↓
8. Bob's device downloads message, unwraps AES key, decrypts
   ↓
9. Store decrypted receipt in local DB
```

### Key Architectural Decisions

1. **Firebase as Relay**: Use Firestore for message storage, Cloud Functions for DID lookup, FCM for push
2. **No Cloudflare Workers Yet**: Defer custom relay server to Phase 7+ (Firebase is faster to implement)
3. **Device-Based Encryption**: Each device gets unique X25519 keypair (multi-device support)
4. **Ephemeral AES Keys**: Each message uses new AES-256 key (wrapped per device)
5. **Raw CBOR Encryption**: Encrypt canonical CBOR bytes (not JSON) to preserve signature verification

---

## Firebase Setup

### Firestore Collections

**1. `devices` Collection**

Stores public keys for all registered devices.

```
devices/{deviceId}
  - owner_did: string (e.g., "did:buds:abc123")
  - owner_phone: string (hashed or encrypted, for phone → DID lookup)
  - device_name: string (e.g., "iPhone 15 Pro")
  - pubkey_x25519: string (base64)
  - pubkey_ed25519: string (base64)
  - status: string ("active" | "revoked")
  - registered_at: timestamp
  - last_seen_at: timestamp
```

**2. `encrypted_messages` Collection**

Stores encrypted messages for delivery.

```
encrypted_messages/{messageId}
  - receipt_cid: string
  - sender_did: string
  - sender_device_id: string
  - recipient_dids: array<string>
  - encrypted_payload: string (base64 combined: nonce || ciphertext || tag)
  - wrapped_keys: map<deviceId, base64_wrapped_key>
  - created_at: timestamp
  - expires_at: timestamp (TTL: 30 days)
```

**3. `phone_to_did` Collection**

Maps phone numbers to DIDs (for Circle invite flow).

```
phone_to_did/{hashedPhone}
  - did: string
  - updated_at: timestamp
```

**Note:** Hash phone numbers with SHA-256 for privacy (not plaintext).

### Cloud Functions

**Function 1: `registerDevice`**

Called when user signs in or adds new device.

```typescript
export const registerDevice = functions.https.onCall(async (data, context) => {
  // Verify user is authenticated
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Must be signed in');

  const { deviceId, deviceName, pubkeyX25519, pubkeyEd25519, ownerDID } = data;

  // Store device in Firestore
  await admin.firestore().collection('devices').doc(deviceId).set({
    owner_did: ownerDID,
    owner_phone: context.auth.token.phone_number,  // From Firebase Auth
    device_name: deviceName,
    pubkey_x25519: pubkeyX25519,
    pubkey_ed25519: pubkeyEd25519,
    status: 'active',
    registered_at: admin.firestore.FieldValue.serverTimestamp(),
    last_seen_at: admin.firestore.FieldValue.serverTimestamp()
  });

  // Map phone → DID
  const phoneHash = crypto.createHash('sha256').update(context.auth.token.phone_number).digest('hex');
  await admin.firestore().collection('phone_to_did').doc(phoneHash).set({
    did: ownerDID,
    updated_at: admin.firestore.FieldValue.serverTimestamp()
  });

  return { success: true };
});
```

**Function 2: `lookupDID`**

Look up DID by phone number (for adding Circle members).

```typescript
export const lookupDID = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Must be signed in');

  const { phoneNumber } = data;
  const phoneHash = crypto.createHash('sha256').update(phoneNumber).digest('hex');

  const doc = await admin.firestore().collection('phone_to_did').doc(phoneHash).get();
  if (!doc.exists) {
    throw new functions.https.HttpsError('not-found', 'User not found');
  }

  return { did: doc.data().did };
});
```

**Function 3: `getDevices`**

Get all active devices for a list of DIDs.

```typescript
export const getDevices = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Must be signed in');

  const { dids } = data;  // array of DIDs

  const devicesSnapshot = await admin.firestore()
    .collection('devices')
    .where('owner_did', 'in', dids)
    .where('status', '==', 'active')
    .get();

  const devices = devicesSnapshot.docs.map(doc => ({
    device_id: doc.id,
    ...doc.data()
  }));

  return { devices };
});
```

**Function 4: `sendMessage`**

Store encrypted message and send FCM push.

```typescript
export const sendMessage = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Must be signed in');

  const { messageId, receiptCID, encryptedPayload, wrappedKeys, recipientDIDs, senderDID, senderDeviceId } = data;

  // Store encrypted message
  await admin.firestore().collection('encrypted_messages').doc(messageId).set({
    receipt_cid: receiptCID,
    sender_did: senderDID,
    sender_device_id: senderDeviceId,
    recipient_dids: recipientDIDs,
    encrypted_payload: encryptedPayload,
    wrapped_keys: wrappedKeys,
    created_at: admin.firestore.FieldValue.serverTimestamp(),
    expires_at: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)  // 30 days
  });

  // Send FCM to recipient devices
  const deviceTokens = await getDeviceTokensFor(recipientDIDs);
  if (deviceTokens.length > 0) {
    await admin.messaging().sendMulticast({
      tokens: deviceTokens,
      notification: {
        title: 'New Memory Shared',
        body: 'Someone shared a memory with you'
      },
      data: {
        message_id: messageId,
        receipt_cid: receiptCID
      }
    });
  }

  return { success: true };
});
```

### Security Rules

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Devices: anyone authenticated can read, owner can write
    match /devices/{deviceId} {
      allow read: if request.auth != null;
      allow write: if request.auth.uid == resource.data.owner_phone;  // Only owner can update
    }

    // Encrypted messages: recipients can read, sender can write
    match /encrypted_messages/{messageId} {
      allow read: if request.auth != null &&
                    (request.auth.token.phone_number in resource.data.recipient_dids ||
                     request.auth.uid == resource.data.sender_did);
      allow create: if request.auth != null;
    }

    // Phone to DID: read-only for authenticated users
    match /phone_to_did/{phoneHash} {
      allow read: if request.auth != null;
    }
  }
}
```

---

## Core Components

### 1. DeviceManager

**Location:** `Buds/Buds/Buds/Core/DeviceManager.swift` (create new file)

Manages current device registration and device discovery.

```swift
//
//  DeviceManager.swift
//  Buds
//
//  Manages device registration and discovery
//

import Foundation
import FirebaseFunctions

@MainActor
class DeviceManager: ObservableObject {
    static let shared = DeviceManager()

    @Published var currentDevice: Device?
    @Published var isRegistered = false

    private let functions = Functions.functions()

    private init() {
        Task {
            await loadCurrentDevice()
        }
    }

    // MARK: - Device Registration

    func registerDevice() async throws {
        let identityManager = IdentityManager.shared
        let deviceId = try identityManager.deviceId
        let ownerDID = try identityManager.currentDID

        // Get keypairs
        let x25519Keys = try identityManager.getX25519Keypair()
        let ed25519Keys = try identityManager.getEd25519Keypair()

        let deviceName = await UIDevice.current.name

        // Call Firebase Function
        let data: [String: Any] = [
            "deviceId": deviceId,
            "deviceName": deviceName,
            "pubkeyX25519": x25519Keys.publicKey.rawRepresentation.base64EncodedString(),
            "pubkeyEd25519": ed25519Keys.publicKey.rawRepresentation.base64EncodedString(),
            "ownerDID": ownerDID
        ]

        let result = try await functions.httpsCallable("registerDevice").call(data)
        print("✅ Device registered: \(deviceId)")

        // Store locally
        let device = Device(
            deviceId: deviceId,
            ownerDID: ownerDID,
            deviceName: deviceName,
            pubkeyX25519: x25519Keys.publicKey.rawRepresentation.base64EncodedString(),
            pubkeyEd25519: ed25519Keys.publicKey.rawRepresentation.base64EncodedString(),
            status: .active,
            registeredAt: Date(),
            lastSeenAt: Date()
        )

        let db = Database.shared
        try await db.writeAsync { db in
            try device.insert(db)
        }

        currentDevice = device
        isRegistered = true
    }

    // MARK: - Load Current Device

    func loadCurrentDevice() async {
        do {
            let deviceId = try IdentityManager.shared.deviceId
            let db = Database.shared

            let device = try await db.readAsync { db in
                try Device
                    .filter(Device.Columns.deviceId == deviceId)
                    .fetchOne(db)
            }

            currentDevice = device
            isRegistered = device != nil
        } catch {
            print("❌ Failed to load current device: \(error)")
        }
    }

    // MARK: - Get Devices for DIDs

    func getDevices(for dids: [String]) async throws -> [Device] {
        let data: [String: Any] = ["dids": dids]
        let result = try await functions.httpsCallable("getDevices").call(data)

        guard let devices = result.data as? [[String: Any]] else {
            throw DeviceError.invalidResponse
        }

        return try devices.map { dict in
            try parseDevice(dict)
        }
    }

    // MARK: - Helper

    private func parseDevice(_ dict: [String: Any]) throws -> Device {
        guard
            let deviceId = dict["device_id"] as? String,
            let ownerDID = dict["owner_did"] as? String,
            let deviceName = dict["device_name"] as? String,
            let pubkeyX25519 = dict["pubkey_x25519"] as? String,
            let pubkeyEd25519 = dict["pubkey_ed25519"] as? String,
            let statusStr = dict["status"] as? String,
            let status = Device.DeviceStatus(rawValue: statusStr)
        else {
            throw DeviceError.invalidResponse
        }

        return Device(
            deviceId: deviceId,
            ownerDID: ownerDID,
            deviceName: deviceName,
            pubkeyX25519: pubkeyX25519,
            pubkeyEd25519: pubkeyEd25519,
            status: status,
            registeredAt: Date(),  // Simplified: use server timestamp if needed
            lastSeenAt: nil
        )
    }
}

// MARK: - Errors

enum DeviceError: Error, LocalizedError {
    case invalidResponse
    case notRegistered

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .notRegistered:
            return "Device not registered"
        }
    }
}
```

### 2. E2EEManager

**Location:** `Buds/Buds/Buds/Core/E2EEManager.swift` (create new file)

Handles encryption/decryption of messages.

```swift
//
//  E2EEManager.swift
//  Buds
//
//  End-to-end encryption manager
//

import Foundation
import CryptoKit

@MainActor
class E2EEManager {
    static let shared = E2EEManager()

    private init() {}

    // MARK: - Encrypt Message

    func encryptMessage(
        receiptCID: String,
        rawCBOR: Data,
        recipientDevices: [Device]
    ) throws -> EncryptedMessage {
        // 1. Generate ephemeral AES key
        let aesKey = SymmetricKey(size: .bits256)

        // 2. Encrypt payload with AES-GCM
        let nonce = AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(
            rawCBOR,
            using: aesKey,
            nonce: nonce,
            authenticating: receiptCID.data(using: .utf8)!  // AAD = receipt CID
        )

        // 3. Get sender keys
        let identityManager = IdentityManager.shared
        let senderPrivateKey = try identityManager.getX25519Keypair().privateKey
        let senderDID = try identityManager.currentDID
        let senderDeviceId = try identityManager.deviceId

        // 4. Wrap AES key for each recipient device
        var wrappedKeys: [String: String] = [:]  // deviceId -> base64 wrapped key

        for device in recipientDevices {
            let wrapped = try wrapKey(
                aesKey,
                forRecipient: device.pubkeyX25519,
                senderPrivateKey: senderPrivateKey
            )
            wrappedKeys[device.deviceId] = wrapped.base64EncodedString()
        }

        // 5. Create encrypted message
        return EncryptedMessage(
            messageId: UUID().uuidString,
            receiptCID: receiptCID,
            encryptedPayload: sealed.combined.base64EncodedString(),
            wrappedKeys: wrappedKeys,
            senderDID: senderDID,
            senderDeviceId: senderDeviceId,
            createdAt: Date()
        )
    }

    // MARK: - Decrypt Message

    func decryptMessage(_ encryptedMessage: EncryptedMessage) throws -> Data {
        let identityManager = IdentityManager.shared
        let myDeviceId = try identityManager.deviceId
        let myPrivateKey = try identityManager.getX25519Keypair().privateKey

        // 1. Find wrapped key for my device
        guard let wrappedKeyB64 = encryptedMessage.wrappedKeys[myDeviceId] else {
            throw E2EEError.noKeyForDevice
        }

        guard let wrappedKeyData = Data(base64Encoded: wrappedKeyB64) else {
            throw E2EEError.invalidWrappedKey
        }

        // 2. Unwrap AES key
        let aesKey = try unwrapKey(
            wrappedKeyData,
            fromSender: encryptedMessage.senderDeviceId,
            myPrivateKey: myPrivateKey
        )

        // 3. Decrypt payload
        guard let encryptedData = Data(base64Encoded: encryptedMessage.encryptedPayload) else {
            throw E2EEError.invalidPayload
        }

        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)

        let rawCBOR = try AES.GCM.open(
            sealedBox,
            using: aesKey,
            authenticating: encryptedMessage.receiptCID.data(using: .utf8)!  // AAD = receipt CID
        )

        return rawCBOR
    }

    // MARK: - Key Wrapping

    private func wrapKey(
        _ aesKey: SymmetricKey,
        forRecipient recipientPubkeyB64: String,
        senderPrivateKey: Curve25519.KeyAgreement.PrivateKey
    ) throws -> Data {
        // 1. Parse recipient public key
        guard let recipientKeyData = Data(base64Encoded: recipientPubkeyB64) else {
            throw E2EEError.invalidPublicKey
        }

        let recipientKey = try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: recipientKeyData
        )

        // 2. Perform X25519 key agreement
        let sharedSecret = try senderPrivateKey.sharedSecretFromKeyAgreement(
            with: recipientKey
        )

        // 3. Derive wrapping key with HKDF
        let wrappingKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: "buds.wrap.v1".data(using: .utf8)!,
            outputByteCount: 32
        )

        // 4. Wrap AES key with AES-GCM
        let wrapNonce = AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(
            aesKey.withUnsafeBytes { Data($0) },
            using: wrappingKey,
            nonce: wrapNonce
        )

        // 5. Return: nonce || ciphertext || tag
        var result = Data()
        result.append(wrapNonce.withUnsafeBytes { Data($0) })
        result.append(sealed.ciphertext)
        result.append(sealed.tag)

        return result
    }

    // MARK: - Key Unwrapping

    private func unwrapKey(
        _ wrappedData: Data,
        fromSender senderDeviceId: String,
        myPrivateKey: Curve25519.KeyAgreement.PrivateKey
    ) throws -> SymmetricKey {
        // 1. Get sender's public key from local DB or Firebase
        let senderDevice = try getDeviceFromDB(deviceId: senderDeviceId)

        guard let senderPubkeyData = Data(base64Encoded: senderDevice.pubkeyX25519) else {
            throw E2EEError.invalidPublicKey
        }

        let senderPubkey = try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: senderPubkeyData
        )

        // 2. Perform X25519 key agreement (same shared secret)
        let sharedSecret = try myPrivateKey.sharedSecretFromKeyAgreement(
            with: senderPubkey
        )

        // 3. Derive wrapping key with HKDF
        let wrappingKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: "buds.wrap.v1".data(using: .utf8)!,
            outputByteCount: 32
        )

        // 4. Parse wrapped data: nonce (12) || ciphertext || tag (16)
        guard wrappedData.count >= 28 else {  // 12 + 16 minimum
            throw E2EEError.invalidWrappedKey
        }

        let nonce = try AES.GCM.Nonce(data: wrappedData.prefix(12))
        let ciphertext = wrappedData.dropFirst(12).dropLast(16)
        let tag = wrappedData.suffix(16)

        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: ciphertext,
            tag: tag
        )

        // 5. Unwrap AES key
        let unwrappedData = try AES.GCM.open(sealedBox, using: wrappingKey)

        return SymmetricKey(data: unwrappedData)
    }

    // MARK: - Helper

    private func getDeviceFromDB(deviceId: String) throws -> Device {
        // TODO: Query local DB or fetch from Firebase if not cached
        // For now, simplified version
        fatalError("Not implemented - should query devices table")
    }
}

// MARK: - Errors

enum E2EEError: Error, LocalizedError {
    case noKeyForDevice
    case invalidWrappedKey
    case invalidPayload
    case invalidPublicKey

    var errorDescription: String? {
        switch self {
        case .noKeyForDevice:
            return "No encryption key found for this device"
        case .invalidWrappedKey:
            return "Invalid wrapped key format"
        case .invalidPayload:
            return "Invalid encrypted payload"
        case .invalidPublicKey:
            return "Invalid public key"
        }
    }
}
```

### 3. EncryptedMessage Model

**Location:** `Buds/Buds/Buds/Core/Models/EncryptedMessage.swift` (create new file)

```swift
//
//  EncryptedMessage.swift
//  Buds
//
//  Represents an encrypted message ready for relay
//

import Foundation

struct EncryptedMessage: Codable {
    let messageId: String
    let receiptCID: String
    let encryptedPayload: String  // Base64 encoded: nonce || ciphertext || tag
    let wrappedKeys: [String: String]  // deviceId -> base64 wrapped AES key
    let senderDID: String
    let senderDeviceId: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case receiptCID = "receipt_cid"
        case encryptedPayload = "encrypted_payload"
        case wrappedKeys = "wrapped_keys"
        case senderDID = "sender_did"
        case senderDeviceId = "sender_device_id"
        case createdAt = "created_at"
    }
}
```

### 4. ShareManager

**Location:** `Buds/Buds/Buds/Core/ShareManager.swift` (create new file)

Orchestrates the sharing flow (combines E2EE + Firebase).

```swift
//
//  ShareManager.swift
//  Buds
//
//  Manages sharing memories with Circle
//

import Foundation
import FirebaseFunctions

@MainActor
class ShareManager: ObservableObject {
    static let shared = ShareManager()

    @Published var isSharing = false

    private let functions = Functions.functions()

    private init() {}

    // MARK: - Share Memory

    func shareMemory(memoryCID: String, with circleDIDs: [String]) async throws {
        isSharing = true
        defer { isSharing = false }

        // 1. Load receipt's raw CBOR bytes from DB
        let db = Database.shared
        let rawCBOR = try await db.readAsync { db in
            try UCRHeader
                .filter(UCRHeader.Columns.cid == memoryCID)
                .fetchOne(db)?.rawCBOR
        }

        guard let rawCBOR = rawCBOR else {
            throw ShareError.receiptNotFound
        }

        // 2. Get recipient devices
        let recipientDevices = try await DeviceManager.shared.getDevices(for: circleDIDs)

        guard !recipientDevices.isEmpty else {
            throw ShareError.noDevicesFound
        }

        // 3. Encrypt message
        let encryptedMessage = try E2EEManager.shared.encryptMessage(
            receiptCID: memoryCID,
            rawCBOR: rawCBOR,
            recipientDevices: recipientDevices
        )

        // 4. Send to Firebase
        let data: [String: Any] = [
            "messageId": encryptedMessage.messageId,
            "receiptCID": encryptedMessage.receiptCID,
            "encryptedPayload": encryptedMessage.encryptedPayload,
            "wrappedKeys": encryptedMessage.wrappedKeys,
            "recipientDIDs": circleDIDs,
            "senderDID": encryptedMessage.senderDID,
            "senderDeviceId": encryptedMessage.senderDeviceId
        ]

        let result = try await functions.httpsCallable("sendMessage").call(data)
        print("✅ Memory shared: \(memoryCID)")

        // 5. Mark memory as shared locally
        try await markMemoryAsShared(memoryCID, recipientDIDs: circleDIDs)
    }

    // MARK: - Mark as Shared

    private func markMemoryAsShared(_ memoryCID: String, recipientDIDs: [String]) async throws {
        let db = Database.shared
        try await db.writeAsync { db in
            // Update local_receipts.is_shared or create shared_memories entry
            // For now, simplified
            print("TODO: Mark memory as shared in local DB")
        }
    }
}

// MARK: - Errors

enum ShareError: Error, LocalizedError {
    case receiptNotFound
    case noDevicesFound

    var errorDescription: String? {
        switch self {
        case .receiptNotFound:
            return "Memory not found"
        case .noDevicesFound:
            return "No devices found for recipients"
        }
    }
}
```

---

## E2EE Implementation

### Step 1: Update IdentityManager

Add device ID generation and X25519 keypair retrieval.

**Location:** `Buds/Buds/Buds/Core/ChaingeKernel/IdentityManager.swift`

Add these methods:

```swift
// MARK: - Device ID

var deviceId: String {
    get throws {
        // Check keychain first
        if let existingId = try? keychain.getString("device_id") {
            return existingId
        }

        // Generate new device ID
        let newId = UUID().uuidString
        try keychain.set(newId, key: "device_id")
        return newId
    }
}

// MARK: - X25519 Keypair (for encryption)

func getX25519Keypair() throws -> (publicKey: Curve25519.KeyAgreement.PublicKey, privateKey: Curve25519.KeyAgreement.PrivateKey) {
    // Check keychain
    if let privateKeyData = try? keychain.getData("x25519_private_key"),
       let privateKey = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKeyData) {
        return (privateKey.publicKey, privateKey)
    }

    // Generate new keypair
    let privateKey = Curve25519.KeyAgreement.PrivateKey()
    try keychain.set(privateKey.rawRepresentation, key: "x25519_private_key")

    print("✅ Generated X25519 keypair")
    return (privateKey.publicKey, privateKey)
}
```

### Step 2: Device Registration on First Launch

Update `BudsApp.swift` to register device after auth.

**Location:** `Buds/Buds/Buds/BudsApp.swift`

```swift
.task {
    // Register device if signed in and not yet registered
    if AuthManager.shared.isSignedIn && !DeviceManager.shared.isRegistered {
        do {
            try await DeviceManager.shared.registerDevice()
        } catch {
            print("❌ Device registration failed: \(error)")
        }
    }
}
```

### Step 3: Update CircleManager to Use Real DIDs

Replace placeholder DID generation with Firebase lookup.

**Location:** `Buds/Buds/Buds/Core/CircleManager.swift`

```swift
func addMember(phoneNumber: String, displayName: String) async throws {
    guard members.count < maxCircleSize else {
        throw CircleError.circleFull
    }

    // Look up DID via Firebase
    let functions = Functions.functions()
    let data: [String: Any] = ["phoneNumber": phoneNumber]
    let result = try await functions.httpsCallable("lookupDID").call(data)

    guard let did = result.data as? [String: Any],
          let didString = did["did"] as? String else {
        throw CircleError.userNotFound
    }

    // Get their devices
    let devices = try await DeviceManager.shared.getDevices(for: [didString])
    guard let firstDevice = devices.first else {
        throw CircleError.userNotRegistered
    }

    let member = CircleMember(
        id: UUID().uuidString,
        did: didString,
        displayName: displayName,
        phoneNumber: phoneNumber,
        avatarCID: nil,
        pubkeyX25519: firstDevice.pubkeyX25519,  // Use real pubkey
        status: .active,  // Active immediately if found
        joinedAt: Date(),
        invitedAt: Date(),
        removedAt: nil,
        createdAt: Date(),
        updatedAt: Date()
    )

    let db = Database.shared
    try await db.writeAsync { db in
        try member.insert(db)
    }

    await loadMembers()
    print("✅ Added Circle member: \(displayName)")
}
```

Add new error cases:

```swift
enum CircleError: Error, LocalizedError {
    case circleFull
    case memberNotFound
    case invalidPhoneNumber
    case userNotFound
    case userNotRegistered

    var errorDescription: String? {
        switch self {
        case .circleFull:
            return "Your Circle is full (max 12 members)"
        case .memberNotFound:
            return "Circle member not found"
        case .invalidPhoneNumber:
            return "Invalid phone number"
        case .userNotFound:
            return "User not found. They may not have signed up yet."
        case .userNotRegistered:
            return "User hasn't registered any devices yet"
        }
    }
}
```

---

## UI Updates

### 1. Add "Share to Circle" Button to MemoryDetailView

**Location:** `Buds/Buds/Buds/Features/Timeline/MemoryDetailView.swift`

Add share button in toolbar:

```swift
.toolbar {
    ToolbarItem(placement: .navigationBarTrailing) {
        Menu {
            Button(action: { showingShareSheet = true }) {
                Label("Share to Circle", systemImage: "person.2.fill")
            }

            Button(action: { /* TODO: Share externally */ }) {
                Label("Share Externally", systemImage: "square.and.arrow.up")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .foregroundColor(.budsPrimary)
        }
    }
}
.sheet(isPresented: $showingShareSheet) {
    ShareToCircleView(memoryCID: memory.receiptCID)
}
```

### 2. Create ShareToCircleView

**Location:** `Buds/Buds/Buds/Features/Share/ShareToCircleView.swift` (create new file)

```swift
//
//  ShareToCircleView.swift
//  Buds
//
//  Share memory to Circle members
//

import SwiftUI

struct ShareToCircleView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var circleManager = CircleManager.shared
    @StateObject private var shareManager = ShareManager.shared

    let memoryCID: String

    @State private var selectedMemberDIDs: Set<String> = []
    @State private var shareError: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.budsPrimary)

                    Text("Share to Circle")
                        .font(.budsTitle)
                        .foregroundColor(.white)

                    Text("Select who can see this memory. Messages are end-to-end encrypted.")
                        .font(.budsBody)
                        .foregroundColor(.budsTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .padding(.top, 40)
                .padding(.bottom, 24)

                // Member selection list
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(circleManager.members, id: \.id) { member in
                            MemberSelectionRow(
                                member: member,
                                isSelected: selectedMemberDIDs.contains(member.did),
                                onToggle: {
                                    toggleSelection(member.did)
                                }
                            )
                        }
                    }
                    .padding()
                }

                // Error message
                if let shareError = shareError {
                    Text(shareError)
                        .font(.budsCaption)
                        .foregroundColor(.budsDanger)
                        .padding()
                }

                // Share button
                Button(action: shareMemory) {
                    if shareManager.isSharing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Text("Share (\(selectedMemberDIDs.count) members)")
                            .font(.budsBodyBold)
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(selectedMemberDIDs.isEmpty ? Color.budsTextSecondary : Color.budsPrimary)
                .cornerRadius(12)
                .disabled(selectedMemberDIDs.isEmpty || shareManager.isSharing)
                .padding()
            }
            .background(Color.black)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func toggleSelection(_ did: String) {
        if selectedMemberDIDs.contains(did) {
            selectedMemberDIDs.remove(did)
        } else {
            selectedMemberDIDs.insert(did)
        }
    }

    private func shareMemory() {
        shareError = nil

        Task {
            do {
                try await shareManager.shareMemory(
                    memoryCID: memoryCID,
                    with: Array(selectedMemberDIDs)
                )
                dismiss()
            } catch {
                shareError = error.localizedDescription
            }
        }
    }
}

// MARK: - Member Selection Row

struct MemberSelectionRow: View {
    let member: CircleMember
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Avatar
            Circle()
                .fill(Color.budsPrimary.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay(
                    Text(member.displayName.prefix(1).uppercased())
                        .font(.budsHeadline)
                        .foregroundColor(.budsPrimary)
                )

            // Name
            Text(member.displayName)
                .font(.budsBodyBold)
                .foregroundColor(.white)

            Spacer()

            // Checkbox
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .budsPrimary : .budsTextSecondary)
                .font(.title2)
        }
        .padding()
        .background(Color.budsCard)
        .cornerRadius(12)
        .onTapGesture {
            onToggle()
        }
    }
}

#Preview {
    ShareToCircleView(memoryCID: "bafyreiabc123")
}
```

---

## Testing Checkpoints

### Checkpoint 1: Device Registration
- ✅ App launches and registers device on first sign-in
- ✅ Console shows "✅ Device registered: [deviceId]"
- ✅ Firebase Console → Firestore → `devices` collection has entry
- ✅ `phone_to_did` collection maps phone → DID

### Checkpoint 2: Circle Member Lookup
- ✅ Add Circle member with real phone number (must be registered user)
- ✅ Sees real DID (not placeholder)
- ✅ Member shows "active" status
- ✅ Console shows "✅ Added Circle member: [name]"

### Checkpoint 3: E2EE Encryption
- ✅ Share memory to 1 Circle member
- ✅ Console shows encryption process (key wrapping, device lookup)
- ✅ Firebase Console → `encrypted_messages` collection has entry
- ✅ `encrypted_payload` and `wrapped_keys` are base64 strings

### Checkpoint 4: Message Delivery (Manual Test)
- ✅ Use Firebase Console to trigger FCM push
- ✅ Recipient device receives push notification
- ✅ App downloads encrypted message
- ✅ Successfully decrypts and displays memory

---

## Troubleshooting

### Build Errors

**"Cannot find 'Functions' in scope"**
→ Add Firebase Functions SDK to project: `https://github.com/firebase/firebase-ios-sdk`

**"Ambiguous use of 'seal'"**
→ Make sure you're importing `CryptoKit`, not a conflicting crypto library

### Runtime Errors

**"Device not registered"**
→ Call `DeviceManager.shared.registerDevice()` after sign-in

**"No key for device"**
→ Recipient device wasn't included in encryption (check device lookup logic)

**"User not found"**
→ Phone number hasn't registered with Buds yet (expected for new users)

### Firebase Errors

**"PERMISSION_DENIED"**
→ Check Firestore security rules allow authenticated reads/writes

**"Function not found"**
→ Deploy Cloud Functions: `firebase deploy --only functions`

---

## What's Next (Phase 7+)

Phase 7 will add:
1. **Message Inbox** - View received shared memories
2. **Map View** - Visualize memories with fuzzy location
3. **Push Notifications** - Real-time delivery alerts
4. **Message Syncing** - Background fetch for new messages

**For now:** Phase 6 creates the E2EE foundation. Messages can be shared manually, decryption works locally.

---

## Summary

**Files Created (6):**
- `Core/DeviceManager.swift` (~150 lines)
- `Core/E2EEManager.swift` (~200 lines)
- `Core/ShareManager.swift` (~80 lines)
- `Core/Models/EncryptedMessage.swift` (~25 lines)
- `Features/Share/ShareToCircleView.swift` (~150 lines)
- `functions/index.ts` (Firebase Functions - ~200 lines)

**Files Modified (4):**
- `Core/ChaingeKernel/IdentityManager.swift` (+30 lines: device ID, X25519 keypair)
- `Core/CircleManager.swift` (+30 lines: real DID lookup)
- `Features/Timeline/MemoryDetailView.swift` (+10 lines: share button)
- `BudsApp.swift` (+5 lines: device registration on launch)

**Firebase Setup:**
- 3 Firestore collections (devices, encrypted_messages, phone_to_did)
- 4 Cloud Functions (registerDevice, lookupDID, getDevices, sendMessage)
- Security rules for read/write access

**Estimated Lines of Code:** ~850 lines Swift + 200 lines TypeScript

**Next Steps:** Test E2EE flow end-to-end, then proceed to Phase 7 (UI polish + message inbox).

---

**December 20, 2025: Ready to implement Phase 6! Let's add real E2EE sharing. 🔐🌿**
