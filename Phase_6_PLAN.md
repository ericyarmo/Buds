# Phase 6: E2EE Sharing + Cloudflare Relay

**Prerequisites:** Phase 5 complete (Circle mechanics working)
**Estimated:** 10-14 hours
**Status:** Ready to implement

---

## Context

**What exists:**
- ✅ Firebase Auth (phone only)
- ✅ Profile with DID display
- ✅ Memory creation (photos + CBOR signatures)
- ✅ Timeline view
- ✅ Circle UI (add/remove members with placeholder DIDs)
- ✅ Cloudflare Workers relay deployed (`buds-relay/`)

**What's missing:**
- ⏳ Device registration (send pubkeys to relay)
- ⏳ Real DID lookup (replace placeholders)
- ⏳ E2EE message encryption/decryption
- ⏳ Share memories to Circle
- ⏳ Message relay integration

**Critical files to reference:**
- `/docs/E2EE_DESIGN.md` - Encryption architecture
- `/Buds/PHASE_5_COMPLETE.md` - Circle mechanics
- `buds-relay/README.md` - Relay API documentation

---

## Architecture

```
Alice shares memory → Lookup Bob's devices (Cloudflare D1)
                   → Generate AES-256 key
                   → Encrypt CBOR with AES-GCM
                   → Wrap AES key per device (X25519 + HKDF)
                   → POST to /api/messages/send
                   → Cloudflare stores ciphertext
                   → Bob polls /api/messages/inbox
                   → Unwraps key + decrypts
                   → Verifies signature → stores locally
```

**Key decisions:**
1. Cloudflare Workers = zero-trust relay (sees only ciphertext)
2. Cloudflare D1 = device registry + message queue
3. X25519 key agreement (per-device encryption)
4. AES-256-GCM (ephemeral keys per message)
5. Raw CBOR encryption (preserves signatures)
6. HTTP polling (Phase 7 adds push)

---

## Implementation

### 1. Update IdentityManager

**File:** `Buds/Buds/Buds/Core/ChaingeKernel/IdentityManager.swift`

Add device ID and X25519 keypair:

```swift
// MARK: - Device ID
var deviceId: String {
    get throws {
        if let id = try? keychain.getString("device_id") {
            return id
        }
        let newId = UUID().uuidString
        try keychain.set(newId, key: "device_id")
        return newId
    }
}

// MARK: - X25519 Keypair
func getX25519Keypair() throws -> (publicKey: Curve25519.KeyAgreement.PublicKey, privateKey: Curve25519.KeyAgreement.PrivateKey) {
    if let data = try? keychain.getData("x25519_private_key"),
       let privateKey = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data) {
        return (privateKey.publicKey, privateKey)
    }

    let privateKey = Curve25519.KeyAgreement.PrivateKey()
    try keychain.set(privateKey.rawRepresentation, key: "x25519_private_key")
    print("✅ Generated X25519 keypair")
    return (privateKey.publicKey, privateKey)
}
```

### 2. Create RelayClient

**File:** `Buds/Buds/Buds/Core/RelayClient.swift` (new)

```swift
import Foundation
import FirebaseAuth

class RelayClient {
    static let shared = RelayClient()
    private let baseURL = "https://buds-relay-dev.getstreams.workers.dev"

    private init() {}

    private func authHeader() async throws -> [String: String] {
        guard let user = Auth.auth().currentUser else {
            throw RelayError.notAuthenticated
        }
        let token = try await user.getIDToken()
        return ["Authorization": "Bearer \(token)"]
    }

    // Register device
    func registerDevice(deviceId: String, deviceName: String, pubkeyX25519: String, pubkeyEd25519: String, ownerDID: String) async throws {
        let headers = try await authHeader()
        let url = URL(string: "\(baseURL)/api/devices/register")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }

        let body: [String: Any] = ["deviceId": deviceId, "deviceName": deviceName, "pubkeyX25519": pubkeyX25519, "pubkeyEd25519": pubkeyEd25519, "ownerDID": ownerDID]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, res) = try await URLSession.shared.data(for: req)
        guard (res as? HTTPURLResponse)?.statusCode == 200 else { throw RelayError.serverError }
    }

    // Lookup DID
    func lookupDID(phoneNumber: String) async throws -> String {
        let headers = try await authHeader()
        let url = URL(string: "\(baseURL)/api/lookup/did")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }

        req.httpBody = try JSONSerialization.data(withJSONObject: ["phoneNumber": phoneNumber])

        let (data, res) = try await URLSession.shared.data(for: req)
        if (res as? HTTPURLResponse)?.statusCode == 404 { throw RelayError.userNotFound }
        guard (res as? HTTPURLResponse)?.statusCode == 200 else { throw RelayError.serverError }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let did = json?["did"] as? String else { throw RelayError.invalidResponse }
        return did
    }

    // Get devices for DIDs
    func getDevices(for dids: [String]) async throws -> [[String: Any]] {
        let headers = try await authHeader()
        let url = URL(string: "\(baseURL)/api/devices/list")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }

        req.httpBody = try JSONSerialization.data(withJSONObject: ["dids": dids])

        let (data, res) = try await URLSession.shared.data(for: req)
        guard (res as? HTTPURLResponse)?.statusCode == 200 else { throw RelayError.serverError }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let devices = json?["devices"] as? [[String: Any]] else { throw RelayError.invalidResponse }
        return devices
    }

    // Send message
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

        let (_, res) = try await URLSession.shared.data(for: req)
        guard (res as? HTTPURLResponse)?.statusCode == 200 else { throw RelayError.serverError }
    }

    // Get inbox
    func getInbox(for did: String) async throws -> [EncryptedMessage] {
        let headers = try await authHeader()
        let url = URL(string: "\(baseURL)/api/messages/inbox?did=\(did)")!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }

        let (data, res) = try await URLSession.shared.data(for: req)
        guard (res as? HTTPURLResponse)?.statusCode == 200 else { throw RelayError.serverError }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let msgs = json?["messages"] as? [[String: Any]] else { throw RelayError.invalidResponse }

        return try msgs.map { dict in
            guard let id = dict["message_id"] as? String,
                  let cid = dict["receipt_cid"] as? String,
                  let payload = dict["encrypted_payload"] as? String,
                  let keys = dict["wrapped_keys"] as? [String: String],
                  let senderDID = dict["sender_did"] as? String,
                  let senderDevice = dict["sender_device_id"] as? String,
                  let createdMs = dict["created_at"] as? Int64
            else { throw RelayError.invalidResponse }

            return EncryptedMessage(
                messageId: id,
                receiptCID: cid,
                encryptedPayload: payload,
                wrappedKeys: keys,
                senderDID: senderDID,
                senderDeviceId: senderDevice,
                recipientDIDs: [],
                createdAt: Date(timeIntervalSince1970: Double(createdMs) / 1000)
            )
        }
    }
}

enum RelayError: Error {
    case notAuthenticated, serverError, userNotFound, invalidResponse
}
```

### 3. Create EncryptedMessage Model

**File:** `Buds/Buds/Buds/Core/Models/EncryptedMessage.swift` (new)

```swift
import Foundation

struct EncryptedMessage: Codable {
    let messageId: String
    let receiptCID: String
    let encryptedPayload: String
    let wrappedKeys: [String: String]
    let senderDID: String
    let senderDeviceId: String
    let recipientDIDs: [String]
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case receiptCID = "receipt_cid"
        case encryptedPayload = "encrypted_payload"
        case wrappedKeys = "wrapped_keys"
        case senderDID = "sender_did"
        case senderDeviceId = "sender_device_id"
        case recipientDIDs = "recipient_dids"
        case createdAt = "created_at"
    }
}
```

### 4. Create DeviceManager

**File:** `Buds/Buds/Buds/Core/DeviceManager.swift` (new)

```swift
import Foundation

@MainActor
class DeviceManager: ObservableObject {
    static let shared = DeviceManager()
    @Published var isRegistered = false

    private init() {
        Task { await loadStatus() }
    }

    func registerDevice() async throws {
        let identity = IdentityManager.shared
        let deviceId = try identity.deviceId
        let did = try identity.currentDID
        let x25519 = try identity.getX25519Keypair()
        let ed25519 = try identity.getEd25519Keypair()
        let name = await UIDevice.current.name

        try await RelayClient.shared.registerDevice(
            deviceId: deviceId,
            deviceName: name,
            pubkeyX25519: x25519.publicKey.rawRepresentation.base64EncodedString(),
            pubkeyEd25519: ed25519.publicKey.rawRepresentation.base64EncodedString(),
            ownerDID: did
        )

        let device = Device(deviceId: deviceId, ownerDID: did, deviceName: name, pubkeyX25519: x25519.publicKey.rawRepresentation.base64EncodedString(), pubkeyEd25519: ed25519.publicKey.rawRepresentation.base64EncodedString(), status: .active, registeredAt: Date(), lastSeenAt: Date())

        try await Database.shared.writeAsync { try device.insert($0) }
        isRegistered = true
        print("✅ Device registered: \(deviceId)")
    }

    func loadStatus() async {
        do {
            let deviceId = try IdentityManager.shared.deviceId
            let exists = try await Database.shared.readAsync {
                try Device.filter(Device.Columns.deviceId == deviceId).fetchOne($0) != nil
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
            else { throw DeviceError.invalidResponse }

            return Device(deviceId: id, ownerDID: owner, deviceName: name, pubkeyX25519: x25519, pubkeyEd25519: ed25519, status: status, registeredAt: Date(), lastSeenAt: nil)
        }
    }
}

enum DeviceError: Error {
    case invalidResponse, notRegistered
}
```

### 5. Create E2EEManager

**File:** `Buds/Buds/Buds/Core/E2EEManager.swift` (new)

```swift
import Foundation
import CryptoKit

@MainActor
class E2EEManager {
    static let shared = E2EEManager()
    private init() {}

    // Encrypt message
    func encryptMessage(receiptCID: String, rawCBOR: Data, recipientDevices: [Device]) throws -> EncryptedMessage {
        let aesKey = SymmetricKey(size: .bits256)
        let nonce = AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(rawCBOR, using: aesKey, nonce: nonce, authenticating: receiptCID.data(using: .utf8)!)

        let identity = IdentityManager.shared
        let senderPrivate = try identity.getX25519Keypair().privateKey
        let senderDID = try identity.currentDID
        let senderDevice = try identity.deviceId

        var wrappedKeys: [String: String] = [:]
        for device in recipientDevices {
            let wrapped = try wrapKey(aesKey, forRecipient: device.pubkeyX25519, senderPrivate: senderPrivate)
            wrappedKeys[device.deviceId] = wrapped.base64EncodedString()
        }

        return EncryptedMessage(
            messageId: UUID().uuidString,
            receiptCID: receiptCID,
            encryptedPayload: sealed.combined.base64EncodedString(),
            wrappedKeys: wrappedKeys,
            senderDID: senderDID,
            senderDeviceId: senderDevice,
            recipientDIDs: recipientDevices.map(\.ownerDID),
            createdAt: Date()
        )
    }

    // Decrypt message
    func decryptMessage(_ msg: EncryptedMessage) async throws -> Data {
        let identity = IdentityManager.shared
        let myDevice = try identity.deviceId
        let myPrivate = try identity.getX25519Keypair().privateKey

        guard let wrappedB64 = msg.wrappedKeys[myDevice],
              let wrappedData = Data(base64Encoded: wrappedB64)
        else { throw E2EEError.noKeyForDevice }

        let aesKey = try await unwrapKey(wrappedData, fromSender: msg.senderDeviceId, myPrivate: myPrivate)

        guard let encryptedData = Data(base64Encoded: msg.encryptedPayload) else { throw E2EEError.invalidPayload }
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)

        return try AES.GCM.open(sealedBox, using: aesKey, authenticating: msg.receiptCID.data(using: .utf8)!)
    }

    // Wrap AES key for recipient
    private func wrapKey(_ aesKey: SymmetricKey, forRecipient pubkeyB64: String, senderPrivate: Curve25519.KeyAgreement.PrivateKey) throws -> Data {
        guard let recipientData = Data(base64Encoded: pubkeyB64) else { throw E2EEError.invalidPublicKey }
        let recipientKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientData)

        let sharedSecret = try senderPrivate.sharedSecretFromKeyAgreement(with: recipientKey)
        let wrappingKey = sharedSecret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(), sharedInfo: "buds.wrap.v1".data(using: .utf8)!, outputByteCount: 32)

        let wrapNonce = AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(aesKey.withUnsafeBytes { Data($0) }, using: wrappingKey, nonce: wrapNonce)

        var result = Data()
        result.append(wrapNonce.withUnsafeBytes { Data($0) })
        result.append(sealed.ciphertext)
        result.append(sealed.tag)
        return result
    }

    // Unwrap AES key from sender
    private func unwrapKey(_ wrappedData: Data, fromSender senderDevice: String, myPrivate: Curve25519.KeyAgreement.PrivateKey) async throws -> SymmetricKey {
        let senderDev = try await Database.shared.readAsync {
            try Device.filter(Device.Columns.deviceId == senderDevice).fetchOne($0)
        }
        guard let senderDev = senderDev,
              let senderPubData = Data(base64Encoded: senderDev.pubkeyX25519)
        else { throw E2EEError.deviceNotFound }

        let senderPub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: senderPubData)
        let sharedSecret = try myPrivate.sharedSecretFromKeyAgreement(with: senderPub)
        let wrappingKey = sharedSecret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(), sharedInfo: "buds.wrap.v1".data(using: .utf8)!, outputByteCount: 32)

        guard wrappedData.count >= 28 else { throw E2EEError.invalidWrappedKey }
        let nonce = try AES.GCM.Nonce(data: wrappedData.prefix(12))
        let ciphertext = wrappedData.dropFirst(12).dropLast(16)
        let tag = wrappedData.suffix(16)

        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        let unwrapped = try AES.GCM.open(sealedBox, using: wrappingKey)

        return SymmetricKey(data: unwrapped)
    }
}

enum E2EEError: Error {
    case noKeyForDevice, invalidWrappedKey, invalidPayload, invalidPublicKey, deviceNotFound
}
```

### 6. Create ShareManager

**File:** `Buds/Buds/Buds/Core/ShareManager.swift` (new)

```swift
import Foundation

@MainActor
class ShareManager: ObservableObject {
    static let shared = ShareManager()
    @Published var isSharing = false

    private init() {}

    func shareMemory(memoryCID: String, with circleDIDs: [String]) async throws {
        isSharing = true
        defer { isSharing = false }

        let rawCBOR = try await Database.shared.readAsync {
            try UCRHeader.filter(UCRHeader.Columns.cid == memoryCID).fetchOne($0)?.rawCBOR
        }
        guard let rawCBOR = rawCBOR else { throw ShareError.receiptNotFound }

        let devices = try await DeviceManager.shared.getDevices(for: circleDIDs)
        guard !devices.isEmpty else { throw ShareError.noDevicesFound }

        let encrypted = try E2EEManager.shared.encryptMessage(receiptCID: memoryCID, rawCBOR: rawCBOR, recipientDevices: devices)
        try await RelayClient.shared.sendMessage(encrypted)

        print("✅ Memory shared: \(memoryCID)")
    }
}

enum ShareError: Error {
    case receiptNotFound, noDevicesFound
}
```

### 7. Update CircleManager

**File:** `Buds/Buds/Buds/Core/CircleManager.swift`

Replace placeholder DID generation in `addMember`:

```swift
func addMember(phoneNumber: String, displayName: String) async throws {
    guard members.count < maxCircleSize else { throw CircleError.circleFull }

    // Look up real DID
    let did = try await RelayClient.shared.lookupDID(phoneNumber: phoneNumber)
    let devices = try await DeviceManager.shared.getDevices(for: [did])
    guard let firstDevice = devices.first else { throw CircleError.userNotRegistered }

    let member = CircleMember(
        id: UUID().uuidString,
        did: did,
        displayName: displayName,
        phoneNumber: phoneNumber,
        avatarCID: nil,
        pubkeyX25519: firstDevice.pubkeyX25519,
        status: .active,
        joinedAt: Date(),
        invitedAt: Date(),
        removedAt: nil,
        createdAt: Date(),
        updatedAt: Date()
    )

    try await Database.shared.writeAsync { try member.insert($0) }
    await loadMembers()
    print("✅ Added Circle member: \(displayName)")
}
```

Add error case:

```swift
enum CircleError: Error {
    case circleFull, memberNotFound, invalidPhoneNumber, userNotFound, userNotRegistered
}
```

### 8. Register Device on Launch

**File:** `Buds/Buds/Buds/BudsApp.swift`

Add after `.onAppear`:

```swift
.task {
    if AuthManager.shared.isSignedIn && !DeviceManager.shared.isRegistered {
        do {
            try await DeviceManager.shared.registerDevice()
        } catch {
            print("❌ Device registration failed: \(error)")
        }
    }
}
```

### 9. Add Share Button to MemoryDetailView

**File:** `Buds/Buds/Buds/Features/Timeline/MemoryDetailView.swift`

Add state:

```swift
@State private var showingShareSheet = false
```

Add to toolbar:

```swift
.toolbar {
    ToolbarItem(placement: .navigationBarTrailing) {
        Menu {
            Button(action: { showingShareSheet = true }) {
                Label("Share to Circle", systemImage: "person.2.fill")
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

### 10. Create ShareToCircleView

**File:** `Buds/Buds/Buds/Features/Share/ShareToCircleView.swift` (new)

```swift
import SwiftUI

struct ShareToCircleView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var circleManager = CircleManager.shared
    @StateObject private var shareManager = ShareManager.shared

    let memoryCID: String

    @State private var selectedDIDs: Set<String> = []
    @State private var error: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.budsPrimary)
                    Text("Share to Circle")
                        .font(.budsTitle)
                        .foregroundColor(.white)
                    Text("End-to-end encrypted. Only selected members can see this.")
                        .font(.budsBody)
                        .foregroundColor(.budsTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .padding(.top, 40)
                .padding(.bottom, 24)

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(circleManager.members, id: \.id) { member in
                            MemberRow(member: member, isSelected: selectedDIDs.contains(member.did)) {
                                if selectedDIDs.contains(member.did) {
                                    selectedDIDs.remove(member.did)
                                } else {
                                    selectedDIDs.insert(member.did)
                                }
                            }
                        }
                    }
                    .padding()
                }

                if let error = error {
                    Text(error)
                        .font(.budsCaption)
                        .foregroundColor(.budsDanger)
                        .padding()
                }

                Button(action: share) {
                    if shareManager.isSharing {
                        ProgressView().tint(.white)
                    } else {
                        Text("Share (\(selectedDIDs.count))")
                            .font(.budsBodyBold)
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(selectedDIDs.isEmpty ? Color.budsTextSecondary : Color.budsPrimary)
                .cornerRadius(12)
                .disabled(selectedDIDs.isEmpty || shareManager.isSharing)
                .padding()
            }
            .background(Color.black)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func share() {
        error = nil
        Task {
            do {
                try await shareManager.shareMemory(memoryCID: memoryCID, with: Array(selectedDIDs))
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

struct MemberRow: View {
    let member: CircleMember
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(Color.budsPrimary.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay(Text(member.displayName.prefix(1).uppercased()).font(.budsHeadline).foregroundColor(.budsPrimary))

            Text(member.displayName)
                .font(.budsBodyBold)
                .foregroundColor(.white)

            Spacer()

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .budsPrimary : .budsTextSecondary)
                .font(.title2)
        }
        .padding()
        .background(Color.budsCard)
        .cornerRadius(12)
        .onTapGesture { onToggle() }
    }
}
```

---

## Validation Checkpoints

**Before proceeding, verify each:**

### Checkpoint 1: Relay Running
```bash
curl https://buds-relay-dev.getstreams.workers.dev/health
# → {"status":"healthy","version":"1.0.0","environment":"development"}
```

### Checkpoint 2: Device Registration
- Launch app after sign-in
- Console: `✅ Device registered: [uuid]`
- Check D1: `SELECT * FROM devices;`

### Checkpoint 3: Circle Lookup
- Add Circle member (must be registered Buds user)
- Member shows real DID (not `did:buds:placeholder_`)
- Status = `active`

### Checkpoint 4: Share Flow
- Create memory → Detail view → Share button
- Select Circle member → Share
- Console: `✅ Memory shared: [cid]`
- Check D1: `SELECT * FROM encrypted_messages;`

### Checkpoint 5: Decryption (Manual)
- Recipient device polls: `GET /api/messages/inbox?did=xxx`
- Successfully decrypts message
- Verifies signature

---

## Critical Integration Points

**Database schema dependency:**
- Relay must be deployed with D1 schema applied
- App needs `Device` model in GRDB

**Relay URL configuration:**
- Production relay: `https://buds-relay-dev.getstreams.workers.dev`
- Already configured in RelayClient.swift
- Switch to custom domain for production (e.g., api.getbuds.app)

**Authentication flow:**
- Device registration requires Firebase Auth token
- Token must be valid for all relay calls
- Refresh token if 401 errors

**Encryption dependencies:**
- `import CryptoKit` required
- X25519 keypair stored in keychain
- Ed25519 keypair already exists (from IdentityManager)

**CBOR requirement:**
- Encrypt `rawCBOR` bytes, not JSON
- Preserves signature verification
- `UCRHeader.rawCBOR` must be stored in DB

---

## Common Errors

**"User not found" during Circle add:**
→ Phone number hasn't signed up for Buds yet

**"Device not registered":**
→ Run device registration in `BudsApp.task`

**"No key for device":**
→ Recipient device wasn't in encryption loop (check device lookup)

**"Invalid token":**
→ Firebase token expired, re-authenticate

**Decryption fails:**
→ Check sender device exists in local DB (needed for unwrap)

---

## Success Criteria

- ✅ Device auto-registers on first launch
- ✅ Circle members show real DIDs
- ✅ Share button works in MemoryDetailView
- ✅ Encrypted message posted to relay
- ✅ Recipient can decrypt and verify signature
- ✅ Zero plaintext stored in Cloudflare D1

---

## Files Summary

**New files (9):**
- `Core/RelayClient.swift` (250 lines)
- `Core/DeviceManager.swift` (100 lines)
- `Core/E2EEManager.swift` (180 lines)
- `Core/ShareManager.swift` (50 lines)
- `Core/Models/EncryptedMessage.swift` (25 lines)
- `Features/Share/ShareToCircleView.swift` (120 lines)

**Modified files (4):**
- `Core/ChaingeKernel/IdentityManager.swift` (+30 lines)
- `Core/CircleManager.swift` (+25 lines)
- `Features/Timeline/MemoryDetailView.swift` (+10 lines)
- `BudsApp.swift` (+8 lines)

**Total:** ~800 lines Swift

---

**Ready to implement. Start with Checkpoint 1 (verify relay is running).**
