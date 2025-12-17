# Buds Build Resources

**Last Updated:** December 16, 2025
**Version:** v0.1
**Purpose:** Practical reference for building Buds iOS app

---

## Quick Reference

### Key Technologies
- **Language:** Swift 6 (strict concurrency)
- **Minimum iOS:** 17.0
- **UI Framework:** SwiftUI (no UIKit)
- **Database:** GRDB.swift
- **Crypto:** CryptoKit (built-in)
- **Auth:** Firebase Auth (phone only)
- **Push:** Firebase Cloud Messaging

---

## Design Tokens

### Colors

```swift
// Colors.swift
extension Color {
    // Primary Palette
    static let budsPrimary = Color(hex: "#4CAF50")      // Cannabis green
    static let budsSecondary = Color(hex: "#8BC34A")    // Light green
    static let budsAccent = Color(hex: "#FF6B35")       // Orange CTA

    // Backgrounds
    static let budsBackground = Color(hex: "#F5F5F5")   // Light gray
    static let budsSurface = Color.white
    static let budsSurfaceDark = Color(hex: "#1E1E1E")

    // Semantic
    static let budsSuccess = Color(hex: "#4CAF50")
    static let budsWarning = Color(hex: "#FFC107")
    static let budsError = Color(hex: "#F44336")
    static let budsInfo = Color(hex: "#2196F3")

    // Effect Tags
    static let effectRelaxed = Color(hex: "#64B5F6")    // Soft blue
    static let effectCreative = Color(hex: "#BA68C8")   // Purple
    static let effectEnergized = Color(hex: "#FFD54F")  // Yellow
    static let effectHappy = Color(hex: "#FF8A65")      // Orange
    static let effectAnxious = Color(hex: "#E57373")    // Red (warning)
    static let effectFocused = Color(hex: "#4DD0E1")    // Cyan
    static let effectSleepy = Color(hex: "#9575CD")     // Deep purple
}

// Helper for hex colors
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: // RGB
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
```

### Typography

```swift
// Typography.swift
extension Font {
    // Titles
    static let budsTitle = Font.system(size: 28, weight: .bold)
    static let budsHeadline = Font.system(size: 22, weight: .semibold)

    // Body
    static let budsBody = Font.system(size: 17, weight: .regular)
    static let budsBodyBold = Font.system(size: 17, weight: .semibold)

    // Small
    static let budsCaption = Font.system(size: 13, weight: .regular)
    static let budsTag = Font.system(size: 12, weight: .medium)
}

// Text Styles
extension Text {
    func titleStyle() -> some View {
        self.font(.budsTitle)
            .foregroundColor(.primary)
    }

    func headlineStyle() -> some View {
        self.font(.budsHeadline)
            .foregroundColor(.primary)
    }

    func bodyStyle() -> some View {
        self.font(.budsBody)
            .foregroundColor(.primary)
    }

    func captionStyle() -> some View {
        self.font(.budsCaption)
            .foregroundColor(.secondary)
    }
}
```

### Spacing

```swift
// Spacing.swift
enum BudsSpacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

// Common padding modifier
extension View {
    func budsPadding(_ edges: Edge.Set = .all) -> some View {
        self.padding(edges, BudsSpacing.m)
    }
}
```

### Corner Radius

```swift
enum BudsRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let pill: CGFloat = 999
}
```

---

## Reusable Components

### Memory Card

```swift
// MemoryCard.swift
struct MemoryCard: View {
    let memory: Memory
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BudsSpacing.s) {
            // Header
            HStack {
                Text("🌿 \(memory.strainName)")
                    .font(.budsHeadline)
                Spacer()
                Button(action: { /* toggle favorite */ }) {
                    Image(systemName: memory.isFavorited ? "heart.fill" : "heart")
                        .foregroundColor(memory.isFavorited ? .budsError : .secondary)
                }
            }

            // Timestamp
            Text(memory.relativeTimestamp)
                .font(.budsCaption)
                .foregroundColor(.secondary)

            Divider()

            // Photo (if present)
            if let imageData = memory.imageData {
                Image(uiImage: UIImage(data: imageData)!)
                    .resizable()
                    .scaledToFill()
                    .frame(maxHeight: 200)
                    .clipped()
                    .cornerRadius(BudsRadius.small)
            }

            // Notes (truncated)
            if let notes = memory.notes {
                Text(notes)
                    .font(.budsBody)
                    .lineLimit(3)
            }

            // Rating + Effects
            HStack {
                // Stars
                HStack(spacing: 2) {
                    ForEach(0..<5) { index in
                        Image(systemName: index < memory.rating ? "star.fill" : "star")
                            .foregroundColor(.budsWarning)
                            .font(.caption)
                    }
                }

                Spacer()

                // Effects
                HStack(spacing: 4) {
                    ForEach(memory.effects.prefix(3), id: \.self) { effect in
                        EffectTag(effect: effect)
                    }
                    if memory.effects.count > 3 {
                        Text("+\(memory.effects.count - 3)")
                            .font(.budsTag)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Location + Share indicator
            HStack {
                if memory.hasLocation {
                    Label("Home", systemImage: "location.fill")
                        .font(.budsCaption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: memory.isShared ? "globe" : "lock.fill")
                    .font(.caption)
                    .foregroundColor(memory.isShared ? .budsInfo : .secondary)
            }
        }
        .budsPadding()
        .background(Color.budsSurface)
        .cornerRadius(BudsRadius.medium)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        .onTapGesture(perform: onTap)
    }
}
```

### Effect Tag

```swift
// EffectTag.swift
struct EffectTag: View {
    let effect: String

    var body: some View {
        Text(effect.lowercased())
            .font(.budsTag)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(effectColor.opacity(0.2))
            .foregroundColor(effectColor)
            .cornerRadius(BudsRadius.small)
    }

    private var effectColor: Color {
        switch effect.lowercased() {
        case "relaxed": return .effectRelaxed
        case "creative": return .effectCreative
        case "energized": return .effectEnergized
        case "happy": return .effectHappy
        case "anxious": return .effectAnxious
        case "focused": return .effectFocused
        case "sleepy": return .effectSleepy
        default: return .secondary
        }
    }
}
```

### Primary Button

```swift
// BudsButton.swift
struct BudsButton: View {
    let title: String
    let style: ButtonStyle
    let action: () -> Void

    enum ButtonStyle {
        case primary
        case secondary
        case tertiary
        case destructive
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.budsBodyBold)
                .foregroundColor(textColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(backgroundColor)
                .cornerRadius(BudsRadius.medium)
                .overlay(
                    RoundedRectangle(cornerRadius: BudsRadius.medium)
                        .stroke(borderColor, lineWidth: style == .secondary ? 1 : 0)
                )
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary: return .budsAccent
        case .secondary: return .clear
        case .tertiary: return .clear
        case .destructive: return .budsError
        }
    }

    private var textColor: Color {
        switch style {
        case .primary, .destructive: return .white
        case .secondary, .tertiary: return .budsPrimary
        }
    }

    private var borderColor: Color {
        switch style {
        case .secondary: return .budsPrimary
        default: return .clear
        }
    }
}
```

### Loading State

```swift
// LoadingView.swift
struct LoadingView: View {
    let message: String?

    init(message: String? = nil) {
        self.message = message
    }

    var body: some View {
        VStack(spacing: BudsSpacing.m) {
            ProgressView()
                .scaleEffect(1.5)

            if let message {
                Text(message)
                    .font(.budsBody)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.budsBackground)
    }
}
```

### Empty State

```swift
// EmptyStateView.swift
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: BudsSpacing.l) {
            Text(icon)
                .font(.system(size: 60))

            Text(title)
                .font(.budsHeadline)

            Text(message)
                .font(.budsBody)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BudsSpacing.xl)

            if let actionTitle, let action {
                BudsButton(title: actionTitle, style: .primary, action: action)
                    .padding(.horizontal, BudsSpacing.xl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.budsBackground)
    }
}
```

---

## Core Models

### Memory (User-Facing)

```swift
// Memory.swift
/// User-facing model for a cannabis session/experience
struct Memory: Identifiable, Codable {
    let id: UUID
    let receiptCID: String

    // Core data
    let strainName: String
    let productType: ProductType
    let rating: Int  // 1-5
    let notes: String?

    // Product details
    let brand: String?
    let thcPercent: Double?
    let cbdPercent: Double?
    let amountGrams: Double?

    // Effects & method
    let effects: [String]
    let consumptionMethod: ConsumptionMethod?

    // Timestamps
    let createdAt: Date
    let claimedTimeMs: Int64?  // User's claimed time (unverified)

    // Location
    let hasLocation: Bool
    let locationName: String?

    // Metadata
    var isFavorited: Bool
    var isShared: Bool
    var imageData: Data?

    // Computed
    var relativeTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
}

enum ProductType: String, Codable {
    case flower
    case edible
    case concentrate
    case vape
    case tincture
    case topical
    case other
}

enum ConsumptionMethod: String, Codable {
    case joint
    case bong
    case pipe
    case vape
    case edible
    case dab
    case tincture
    case topical
}
```

### UCRHeader (Receipt Layer)

```swift
// UCRHeader.swift
/// Universal Content Receipt Header (canonical representation)
struct UCRHeader: Codable {
    let cid: String                      // bafyre...
    let did: String                      // did:buds:xyz
    let deviceId: String                 // UUID
    let parentCID: String?               // Edit/delete chain
    let rootCID: String                  // First in chain
    let receiptType: String              // app.buds.session.created/v1
    let signature: String                // Ed25519 sig (base64)

    // Local only (not in raw_cbor)
    let rawCBOR: Data                    // Canonical encoding
    let payloadJSON: String              // For querying
    let receivedAt: Date                 // Local timestamp
}

/// Payload for session.created/v1
struct SessionPayload: Codable {
    let claimedTimeMs: Int64?
    let productName: String
    let productType: String
    let rating: Int
    let notes: String?
    let brand: String?
    let thcPercent: Double?
    let cbdPercent: Double?
    let amountGrams: Double?
    let effects: [String]
    let consumptionMethod: String?
    let locationCID: String?
}
```

---

## GRDB Patterns

### Database Setup

```swift
// Database.swift
import GRDB

final class Database {
    static let shared = Database()

    private let dbQueue: DatabaseQueue

    private init() {
        let fileManager = FileManager.default
        let appSupport = try! fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dbPath = appSupport.appendingPathComponent("buds.sqlite").path

        dbQueue = try! DatabaseQueue(path: dbPath)
        try! migrator.migrate(dbQueue)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1") { db in
            // Create all tables from DATABASE_SCHEMA.md
            try db.execute(sql: """
                CREATE TABLE ucr_headers (
                    cid TEXT PRIMARY KEY NOT NULL,
                    did TEXT NOT NULL,
                    device_id TEXT NOT NULL,
                    parent_cid TEXT,
                    root_cid TEXT NOT NULL,
                    receipt_type TEXT NOT NULL,
                    signature TEXT NOT NULL,
                    raw_cbor BLOB NOT NULL,
                    payload_json TEXT NOT NULL,
                    received_at REAL NOT NULL,
                    FOREIGN KEY (parent_cid) REFERENCES ucr_headers(cid) ON DELETE SET NULL
                );

                CREATE INDEX idx_ucr_headers_did ON ucr_headers(did);
                CREATE INDEX idx_ucr_headers_type ON ucr_headers(receipt_type);
                CREATE INDEX idx_ucr_headers_received ON ucr_headers(received_at DESC);
                """)

            // ... more tables (locations, local_receipts, etc.)
        }

        return migrator
    }

    func read<T>(_ block: (GRDB.Database) throws -> T) throws -> T {
        try dbQueue.read(block)
    }

    func write<T>(_ block: (GRDB.Database) throws -> T) throws -> T {
        try dbQueue.write(block)
    }
}
```

### Repository Pattern

```swift
// MemoryRepository.swift
struct MemoryRepository {
    func fetchAll() async throws -> [Memory] {
        try await Database.shared.read { db in
            let sql = """
                SELECT
                    lr.uuid,
                    h.cid,
                    h.payload_json,
                    h.received_at,
                    lr.is_favorited,
                    lr.tags_json,
                    lr.local_notes,
                    lr.image_cid
                FROM local_receipts lr
                JOIN ucr_headers h ON lr.header_cid = h.cid
                WHERE h.receipt_type = 'app.buds.session.created/v1'
                ORDER BY h.received_at DESC
                """

            let rows = try Row.fetchAll(db, sql: sql)
            return try rows.map { row in
                let payloadJSON = row["payload_json"] as String
                let payload = try JSONDecoder().decode(SessionPayload.self, from: payloadJSON.data(using: .utf8)!)

                return Memory(
                    id: UUID(uuidString: row["uuid"])!,
                    receiptCID: row["cid"],
                    strainName: payload.productName,
                    productType: ProductType(rawValue: payload.productType) ?? .other,
                    rating: payload.rating,
                    notes: payload.notes,
                    brand: payload.brand,
                    thcPercent: payload.thcPercent,
                    cbdPercent: payload.cbdPercent,
                    amountGrams: payload.amountGrams,
                    effects: payload.effects,
                    consumptionMethod: payload.consumptionMethod.flatMap { ConsumptionMethod(rawValue: $0) },
                    createdAt: Date(timeIntervalSince1970: row["received_at"]),
                    claimedTimeMs: payload.claimedTimeMs,
                    hasLocation: payload.locationCID != nil,
                    locationName: nil,  // TODO: join with locations table
                    isFavorited: row["is_favorited"] == 1,
                    isShared: false,  // TODO: check shared_memories table
                    imageData: nil  // TODO: load from blobs table
                )
            }
        }
    }

    func create(_ memory: Memory) async throws {
        // 1. Build payload
        // 2. Encode to canonical CBOR
        // 3. Compute CID
        // 4. Sign with Ed25519
        // 5. Insert into ucr_headers + local_receipts
        // See ReceiptManager.swift
    }
}
```

---

## Crypto Patterns

### Identity Manager

```swift
// IdentityManager.swift
import CryptoKit

actor IdentityManager {
    static let shared = IdentityManager()

    private let keychainService = "app.getbuds.identity"

    // Ed25519 keypair (signing)
    func getSigningKeypair() throws -> Curve25519.Signing.PrivateKey {
        if let existing = try loadFromKeychain(key: "ed25519_private") {
            return try Curve25519.Signing.PrivateKey(rawRepresentation: existing)
        }

        let keypair = Curve25519.Signing.PrivateKey()
        try saveToKeychain(key: "ed25519_private", data: keypair.rawRepresentation)
        return keypair
    }

    // X25519 keypair (E2EE)
    func getEncryptionKeypair() throws -> Curve25519.KeyAgreement.PrivateKey {
        if let existing = try loadFromKeychain(key: "x25519_private") {
            return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: existing)
        }

        let keypair = Curve25519.KeyAgreement.KeyAgreement.PrivateKey()
        try saveToKeychain(key: "x25519_private", data: keypair.rawRepresentation)
        return keypair
    }

    // Generate DID from Ed25519 pubkey
    func getDID() throws -> String {
        let signingKey = try getSigningKeypair()
        let pubkeyBytes = signingKey.publicKey.rawRepresentation
        let first20 = pubkeyBytes.prefix(20)
        let base58 = Base58.encode(Data(first20))
        return "did:buds:\(base58)"
    }

    // Keychain helpers
    private func saveToKeychain(key: String, data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary)  // Delete existing
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
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
            throw KeychainError.loadFailed(status)
        }

        return result as? Data
    }
}

enum KeychainError: Error {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
}
```

### E2EE Encryption

```swift
// CryptoManager.swift
import CryptoKit

struct CryptoManager {
    /// Encrypt receipt payload for Circle sharing
    func encryptReceipt(
        rawCBOR: Data,
        recipientDeviceKeys: [String: Curve25519.KeyAgreement.PublicKey]  // deviceId → pubkey
    ) throws -> EncryptedEnvelope {
        // 1. Generate ephemeral AES key
        let aesKey = SymmetricKey(size: .bits256)

        // 2. Encrypt payload with AES-256-GCM
        let sealed = try AES.GCM.seal(rawCBOR, using: aesKey)

        // 3. Wrap AES key for each recipient device
        let myX25519 = try IdentityManager.shared.getEncryptionKeypair()
        var wrappedKeys: [String: String] = [:]

        for (deviceId, recipientPubkey) in recipientDeviceKeys {
            let sharedSecret = try myX25519.sharedSecretFromKeyAgreement(with: recipientPubkey)
            let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
                using: SHA256.self,
                salt: Data(),
                sharedInfo: Data("buds.e2ee.v1".utf8),
                outputByteCount: 32
            )

            let wrappedKey = try AES.GCM.seal(aesKey.withUnsafeBytes { Data($0) }, using: symmetricKey)
            wrappedKeys[deviceId] = wrappedKey.combined.base64EncodedString()
        }

        return EncryptedEnvelope(
            encryptedPayload: sealed.combined.base64EncodedString(),  // nonce || ciphertext || tag
            wrappedKeys: wrappedKeys
        )
    }

    /// Decrypt received message
    func decryptReceipt(
        encryptedPayload: String,
        wrappedKey: String,
        senderPubkey: Curve25519.KeyAgreement.PublicKey
    ) throws -> Data {
        // 1. Unwrap AES key
        let myX25519 = try IdentityManager.shared.getEncryptionKeypair()
        let sharedSecret = try myX25519.sharedSecretFromKeyAgreement(with: senderPubkey)
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: Data("buds.e2ee.v1".utf8),
            outputByteCount: 32
        )

        let wrappedKeyData = Data(base64Encoded: wrappedKey)!
        let wrappedBox = try AES.GCM.SealedBox(combined: wrappedKeyData)
        let aesKeyData = try AES.GCM.open(wrappedBox, using: symmetricKey)
        let aesKey = SymmetricKey(data: aesKeyData)

        // 2. Decrypt payload
        let encryptedData = Data(base64Encoded: encryptedPayload)!
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let plaintext = try AES.GCM.open(sealedBox, using: aesKey)

        return plaintext
    }
}

struct EncryptedEnvelope {
    let encryptedPayload: String  // Base64(nonce || ciphertext || tag)
    let wrappedKeys: [String: String]  // deviceId → base64(wrapped AES key)
}
```

---

## Testing Patterns

### Unit Test Example

```swift
// MemoryRepositoryTests.swift
import XCTest
@testable import Buds

final class MemoryRepositoryTests: XCTestCase {
    var repository: MemoryRepository!

    override func setUp() async throws {
        // Use in-memory database for tests
        repository = MemoryRepository()
    }

    func testCreateAndFetchMemory() async throws {
        // Given
        let memory = Memory(
            id: UUID(),
            receiptCID: "bafyreitest",
            strainName: "Blue Dream",
            productType: .flower,
            rating: 5,
            notes: "Great strain",
            brand: "Cookies",
            thcPercent: 23.5,
            cbdPercent: 0.8,
            amountGrams: 3.5,
            effects: ["relaxed", "creative"],
            consumptionMethod: .vape,
            createdAt: Date(),
            claimedTimeMs: nil,
            hasLocation: false,
            locationName: nil,
            isFavorited: false,
            isShared: false,
            imageData: nil
        )

        // When
        try await repository.create(memory)
        let fetched = try await repository.fetchAll()

        // Then
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.strainName, "Blue Dream")
        XCTAssertEqual(fetched.first?.rating, 5)
    }
}
```

### UI Test Example

```swift
// TimelineUITests.swift
import XCTest

final class TimelineUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["UI_TESTING"]
        app.launch()
    }

    func testCreateMemoryFlow() {
        // Tap FAB
        app.buttons["addMemoryButton"].tap()

        // Fill in strain
        let strainField = app.textFields["strainNameField"]
        strainField.tap()
        strainField.typeText("Blue Dream")

        // Select rating
        app.buttons["star5"].tap()

        // Add note
        let notesField = app.textViews["notesField"]
        notesField.tap()
        notesField.typeText("Great strain for creativity")

        // Save
        app.buttons["saveMemoryButton"].tap()

        // Verify appears in timeline
        XCTAssertTrue(app.staticTexts["Blue Dream"].exists)
    }
}
```

---

## Performance Guidelines

### Memory Card Optimization

```swift
// Use lazy loading for images
struct OptimizedMemoryCard: View {
    let memory: Memory
    @State private var image: UIImage?

    var body: some View {
        MemoryCard(memory: memory)
            .task {
                // Load image asynchronously
                if let imageCID = memory.imageCID {
                    image = await loadImage(cid: imageCID)
                }
            }
    }

    private func loadImage(cid: String) async -> UIImage? {
        // Load from blobs table
        // Resize/compress if needed
        return nil
    }
}
```

### List Performance

```swift
// Use LazyVStack for long lists
struct TimelineView: View {
    @StateObject private var viewModel = TimelineViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: BudsSpacing.m) {
                ForEach(viewModel.memories) { memory in
                    MemoryCard(memory: memory) {
                        viewModel.selectMemory(memory)
                    }
                }
            }
            .padding(.horizontal)
        }
        .task {
            await viewModel.loadMemories()
        }
    }
}
```

### Database Query Optimization

```swift
// Use prepared statements + indexes
func fetchMemoriesSince(_ date: Date) async throws -> [Memory] {
    try await Database.shared.read { db in
        // This query uses idx_ucr_headers_received index
        let sql = """
            SELECT * FROM ucr_headers
            WHERE received_at > ?
            ORDER BY received_at DESC
            LIMIT 50
            """

        let statement = try db.cachedStatement(sql: sql)
        return try Memory.fetchAll(statement, arguments: [date.timeIntervalSince1970])
    }
}
```

---

## Common Pitfalls

### ❌ Don't: Store sensitive data in UserDefaults
```swift
// BAD - UserDefaults is not encrypted
UserDefaults.standard.set(privateKey, forKey: "privateKey")
```

✅ **Do: Use Keychain**
```swift
// GOOD - Keychain is encrypted
try IdentityManager.shared.saveToKeychain(key: "ed25519_private", data: privateKeyData)
```

### ❌ Don't: Sign JSON
```swift
// BAD - JSON is not deterministic
let json = try JSONEncoder().encode(payload)
let signature = try signingKey.signature(for: json)
```

✅ **Do: Sign canonical CBOR**
```swift
// GOOD - CBOR is canonical
let cbor = try CBOREncoder.canonical.encode(payload)
let signature = try signingKey.signature(for: cbor)
```

### ❌ Don't: Share precise location by default
```swift
// BAD - shares exact coordinates
memory.latitude = locationManager.location.latitude
```

✅ **Do: Snap to fuzzy grid**
```swift
// GOOD - 500m grid for privacy
memory.latitude = snapToGrid(locationManager.location.latitude, gridSize: 0.0045)
```

### ❌ Don't: Block main thread for crypto
```swift
// BAD - encryption blocks UI
let encrypted = try CryptoManager().encryptReceipt(...)
```

✅ **Do: Use async/await**
```swift
// GOOD - encryption runs off main thread
Task {
    let encrypted = try await CryptoManager().encryptReceipt(...)
}
```

---

## Debugging Tips

### Enable SQL Logging
```swift
// In Database.swift init
var configuration = Configuration()
configuration.prepareDatabase { db in
    db.trace { print("SQL: \($0)") }
}
dbQueue = try DatabaseQueue(path: dbPath, configuration: configuration)
```

### Print CBOR Encoding
```swift
// Debug canonical CBOR
let cbor = try CBOREncoder.canonical.encode(payload)
print("CBOR hex: \(cbor.hexString)")
print("CID: \(computeCID(cbor))")
```

### Test E2EE Round-Trip
```swift
// Verify encrypt/decrypt works
let plaintext = "test".data(using: .utf8)!
let encrypted = try CryptoManager().encrypt(plaintext, for: recipientKeys)
let decrypted = try CryptoManager().decrypt(encrypted, with: myKey)
assert(plaintext == decrypted)
```

---

## Build Checklist

Before committing:
- [ ] Run SwiftLint (no warnings)
- [ ] All tests pass (`Cmd+U`)
- [ ] No force unwraps in production code
- [ ] No hardcoded strings (use localized strings)
- [ ] Accessibility labels on all interactive elements
- [ ] Dark mode tested
- [ ] VoiceOver tested (key flows)

Before TestFlight:
- [ ] Privacy manifest added (PrivacyInfo.xcprivacy)
- [ ] App Transport Security configured
- [ ] Signing certificates valid
- [ ] Version number incremented
- [ ] Release notes written
- [ ] No debug logs in release build

---

**Next:** See [DEVELOPMENT_ROADMAP.md](./DEVELOPMENT_ROADMAP.md) for implementation phases.
