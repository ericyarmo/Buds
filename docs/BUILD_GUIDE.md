# Buds Build Guide - Zero to TestFlight

**Last Updated:** December 16, 2025
**Goal:** Working iOS app on TestFlight in 2-4 weeks
**Prerequisites:** Mac with Xcode 15+, Apple Developer account ($99/yr)

---

## Phase 0: Foundation Setup (Day 1)

### Step 1: Create Xcode Project

```bash
# Open Xcode
# File > New > Project
# iOS > App
# Product Name: Buds
# Team: [Your Apple Developer Team]
# Organization Identifier: app.getbuds (or your reverse domain)
# Interface: SwiftUI
# Language: Swift
# ✓ Include Tests
# ✗ Core Data (we use GRDB)
# ✗ CloudKit

# Save to: /Users/ericyarmolinsky/Developer/Buds/
```

**Project Settings:**
- Minimum Deployment: iOS 17.0
- Swift Language Version: Swift 6
- Enable strict concurrency checking

### Step 2: Project Structure

Create this folder structure in Xcode:

```
Buds/
├── App/
│   ├── BudsApp.swift
│   └── AppDelegate.swift
├── Core/
│   ├── ChaingeKernel/
│   │   ├── ReceiptManager.swift
│   │   ├── IdentityManager.swift
│   │   ├── CryptoManager.swift
│   │   └── SyncManager.swift
│   ├── Database/
│   │   ├── Database.swift
│   │   ├── Migrations/
│   │   │   └── Migration_v1.swift
│   │   └── Repositories/
│   │       └── MemoryRepository.swift
│   └── Models/
│       ├── UCRHeader.swift
│       ├── Receipt.swift
│       ├── Memory.swift
│       └── Circle.swift
├── Features/
│   ├── Timeline/
│   │   ├── TimelineView.swift
│   │   └── TimelineViewModel.swift
│   ├── CreateMemory/
│   │   ├── CreateMemoryView.swift
│   │   └── CreateMemoryViewModel.swift
│   ├── Map/
│   ├── Circle/
│   ├── Profile/
│   └── Agent/
├── Shared/
│   ├── Views/
│   │   ├── MemoryCard.swift
│   │   ├── EffectTag.swift
│   │   └── BudsButton.swift
│   ├── Components/
│   └── Utilities/
│       ├── Colors.swift
│       ├── Typography.swift
│       └── Spacing.swift
└── Resources/
    ├── Assets.xcassets
    ├── GoogleService-Info.plist (add later)
    └── Info.plist
```

### Step 3: Add Dependencies via SPM

In Xcode:
1. File > Add Package Dependencies
2. Add these packages:

**GRDB.swift:**
```
https://github.com/groue/GRDB.swift
Version: 6.24.0 (or latest)
```

**Firebase:**
```
https://github.com/firebase/firebase-ios-sdk
Version: 10.20.0 (or latest)
Select:
- FirebaseAuth
- FirebaseMessaging
```

**SwiftyCBOR (for CBOR encoding):**
```
https://github.com/unrelenting-technology/SwiftCBOR
Version: 0.4.5 (or latest)
```

**Optional (for testing):**
```
https://github.com/Quick/Nimble
Version: 13.0.0
```

### Step 4: Configure Info.plist

Add these keys:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>To add photos to your cannabis memories</string>

<key>NSCameraUsageDescription</key>
<string>To capture photos of your cannabis experiences</string>

<key>NSLocationWhenInUseUsageDescription</key>
<string>To remember where you had your experiences (optional, off by default)</string>

<key>NSUserTrackingUsageDescription</key>
<string>This app does not track you. This permission is not used.</string>

<key>UIBackgroundModes</key>
<array>
    <string>remote-notification</string>
</array>
```

---

## Phase 1: Firebase Setup (Day 1)

### Step 1: Create Firebase Project

1. Go to https://console.firebase.google.com
2. Click "Add project"
3. Name: `Buds` (or `buds-dev` for development)
4. Disable Google Analytics (optional)
5. Click "Create project"

### Step 2: Add iOS App

1. In Firebase Console > Project Overview > Add app > iOS
2. iOS bundle ID: `app.getbuds.Buds` (match your Xcode bundle ID)
3. App nickname: `Buds iOS`
4. Download `GoogleService-Info.plist`
5. **Drag into Xcode** under `Resources/` folder
6. ✓ Ensure "Copy items if needed" is checked
7. ✓ Add to target: Buds

### Step 3: Enable Phone Authentication

1. Firebase Console > Authentication > Get Started
2. Sign-in method > Phone
3. Click "Enable"
4. Add test phone number (optional):
   - `+1 650-555-1234` → code `123456`

### Step 4: Add APNS Certificate (for Push)

1. Go to Apple Developer Portal: https://developer.apple.com/account
2. Certificates > Create new > Apple Push Notification service SSL
3. Select your App ID (app.getbuds.Buds)
4. Upload CSR (create in Keychain Access)
5. Download .p12 certificate
6. In Firebase Console > Project Settings > Cloud Messaging
7. Upload APNs certificate (.p12)

### Step 5: Initialize Firebase in Code

**BudsApp.swift:**
```swift
import SwiftUI
import FirebaseCore

@main
struct BudsApp: App {
    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

**Test Firebase:**
```swift
import Firebase

func testFirebaseConnection() {
    print("Firebase configured: \(FirebaseApp.app() != nil)")
}
```

---

## Phase 2: Cloudflare Workers (Relay Server)

### Step 1: Create Cloudflare Account

1. Go to https://dash.cloudflare.com
2. Sign up (free tier is fine)
3. Verify email

### Step 2: Install Wrangler CLI

```bash
npm install -g wrangler

# Login
wrangler login
```

### Step 3: Create Workers Project

```bash
cd /Users/ericyarmolinsky/Developer/Buds
mkdir relay-server
cd relay-server

# Initialize project
wrangler init

# Name: buds-relay
# TypeScript: Yes
# Git: Yes
# Deploy: No (not yet)
```

### Step 4: Configure D1 Database

```bash
# Create D1 database
wrangler d1 create buds-relay-prod

# Copy the database_id from output
```

**wrangler.toml:**
```toml
name = "buds-relay"
main = "src/index.ts"
compatibility_date = "2025-01-01"

[[d1_databases]]
binding = "DB"
database_name = "buds-relay-prod"
database_id = "<paste_database_id_here>"

[vars]
ENVIRONMENT = "production"

[[triggers]]
crons = ["0 2 * * *"]  # Daily cleanup at 2am UTC
```

### Step 5: Create Database Schema

**relay-server/schema.sql:**
```sql
-- From RELAY_SERVER.md

CREATE TABLE devices (
    device_id TEXT PRIMARY KEY NOT NULL,
    owner_did TEXT NOT NULL,
    device_name TEXT NOT NULL,
    pubkey_x25519 TEXT NOT NULL,
    pubkey_ed25519 TEXT NOT NULL,
    firebase_token TEXT,
    status TEXT NOT NULL DEFAULT 'active',
    last_seen_at_ms INTEGER,
    created_at_ms INTEGER NOT NULL,
    revoked_at_ms INTEGER
);

CREATE INDEX idx_devices_did ON devices(owner_did);
CREATE INDEX idx_devices_status ON devices(status);

CREATE TABLE messages (
    message_id TEXT PRIMARY KEY NOT NULL,
    receipt_cid TEXT NOT NULL,
    encrypted_payload BLOB NOT NULL,
    wrapped_keys_json TEXT NOT NULL,
    sender_did TEXT NOT NULL,
    sender_device_id TEXT NOT NULL,
    recipient_dids_json TEXT NOT NULL,
    relay_sent_at_ms INTEGER NOT NULL,
    expires_at_ms INTEGER,
    delivered_to_json TEXT,
    created_at_ms INTEGER NOT NULL
);

CREATE INDEX idx_messages_relay_sent_at ON messages(relay_sent_at_ms DESC);
CREATE INDEX idx_messages_expires ON messages(expires_at_ms);

CREATE TABLE rate_limits (
    key TEXT PRIMARY KEY NOT NULL,
    count INTEGER NOT NULL DEFAULT 0,
    window_start_ms INTEGER NOT NULL,
    expires_at_ms INTEGER NOT NULL
);

CREATE INDEX idx_rate_limits_expires ON rate_limits(expires_at_ms);
```

### Step 6: Apply Schema

```bash
# Apply migrations
wrangler d1 execute buds-relay-prod --file=schema.sql --remote
```

### Step 7: Deploy Relay Server

```bash
# Deploy to Cloudflare
wrangler deploy

# Output will show your worker URL:
# https://buds-relay.<your-subdomain>.workers.dev
```

**Save this URL** - you'll use it in the iOS app.

---

## Phase 3: GitHub Setup

### Step 1: Create Repository

```bash
cd /Users/ericyarmolinsky/Developer/Buds

# Initialize git (if not already)
git init

# Create .gitignore
cat > .gitignore << 'EOF'
# Xcode
*.xcodeproj/xcuserdata/
*.xcworkspace/xcuserdata/
DerivedData/
*.xcarchive

# Swift Package Manager
.build/
.swiftpm/

# CocoaPods (not using, but just in case)
Pods/
*.podspec

# Secrets
GoogleService-Info.plist
.env
*.p12
*.mobileprovision

# OS
.DS_Store
*.swp

# Build
Build/
build/
EOF

# Initial commit
git add .
git commit -m "Initial commit - Buds v0.1 foundation"
```

### Step 2: Create GitHub Repo

```bash
# Create repo on GitHub (private)
# Then push:

git remote add origin https://github.com/YOUR_USERNAME/buds.git
git branch -M main
git push -u origin main
```

---

## Phase 4: Database Setup (GRDB)

### Step 1: Create Database.swift

**Core/Database/Database.swift:**
```swift
import GRDB
import Foundation

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

        do {
            dbQueue = try DatabaseQueue(path: dbPath)
            try migrator.migrate(dbQueue)
            print("✅ Database initialized at: \(dbPath)")
        } catch {
            fatalError("Database initialization failed: \(error)")
        }
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1") { db in
            // See Migration_v1.swift
            try createTables(db)
        }

        return migrator
    }

    func read<T>(_ block: (GRDB.Database) throws -> T) throws -> T {
        try dbQueue.read(block)
    }

    func write<T>(_ block: (GRDB.Database) throws -> T) throws -> T {
        try dbQueue.write(block)
    }

    // For testing
    static func makeTestDatabase() throws -> Database {
        let dbQueue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try createTables(db)
        }
        try migrator.migrate(dbQueue)
        // Return test instance...
        fatalError("Implement test database")
    }
}

private func createTables(_ db: GRDB.Database) throws {
    // From DATABASE_SCHEMA.md

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

    try db.execute(sql: """
        CREATE TABLE local_receipts (
            uuid TEXT PRIMARY KEY NOT NULL,
            header_cid TEXT NOT NULL UNIQUE,
            is_favorited INTEGER NOT NULL DEFAULT 0,
            tags_json TEXT,
            local_notes TEXT,
            image_cid TEXT,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            FOREIGN KEY (header_cid) REFERENCES ucr_headers(cid) ON DELETE CASCADE
        );

        CREATE INDEX idx_local_receipts_favorited ON local_receipts(is_favorited);
        """)

    // TODO: Add remaining tables (locations, blobs, etc.)
}
```

### Step 2: Test Database

**Create a test:**
```swift
import XCTest
@testable import Buds

final class DatabaseTests: XCTestCase {
    func testDatabaseInitialization() throws {
        let db = Database.shared
        let count = try db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ucr_headers") ?? 0
        }
        XCTAssertEqual(count, 0)
    }
}
```

Run: `Cmd+U`

---

## Phase 5: First SwiftUI View

### Step 1: Create Design Tokens

Copy from BUILD_RESOURCES.md:
- `Shared/Utilities/Colors.swift`
- `Shared/Utilities/Typography.swift`
- `Shared/Utilities/Spacing.swift`

### Step 2: Create Timeline View

**Features/Timeline/TimelineView.swift:**
```swift
import SwiftUI

struct TimelineView: View {
    @StateObject private var viewModel = TimelineViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.isLoading {
                    LoadingView(message: "Loading memories...")
                } else if viewModel.memories.isEmpty {
                    EmptyStateView(
                        icon: "🌿",
                        title: "No memories yet",
                        message: "Tap + to create your first cannabis memory",
                        actionTitle: "Create Memory",
                        action: { viewModel.showCreateSheet = true }
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: BudsSpacing.m) {
                            ForEach(viewModel.memories) { memory in
                                MemoryCard(memory: memory) {
                                    // Navigate to detail
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .navigationTitle("Timeline")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.showCreateSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.budsAccent)
                    }
                }
            }
            .sheet(isPresented: $viewModel.showCreateSheet) {
                CreateMemoryView()
            }
            .task {
                await viewModel.loadMemories()
            }
        }
    }
}

@MainActor
final class TimelineViewModel: ObservableObject {
    @Published var memories: [Memory] = []
    @Published var isLoading = false
    @Published var showCreateSheet = false

    func loadMemories() async {
        isLoading = true
        defer { isLoading = false }

        // TODO: Load from database
        // For now, show empty
        memories = []
    }
}
```

### Step 3: Update BudsApp.swift

```swift
import SwiftUI
import FirebaseCore

@main
struct BudsApp: App {
    init() {
        FirebaseApp.configure()
        _ = Database.shared  // Initialize database
    }

    var body: some Scene {
        WindowGroup {
            TimelineView()
        }
    }
}
```

### Step 4: Run App

Hit `Cmd+R` - you should see the empty state!

---

## Phase 6: TestFlight Setup

### Step 1: Configure Signing

1. Xcode > Select target "Buds"
2. Signing & Capabilities
3. Team: Select your Apple Developer team
4. Bundle Identifier: `app.getbuds.Buds`
5. ✓ Automatically manage signing

### Step 2: Create App in App Store Connect

1. Go to https://appstoreconnect.apple.com
2. My Apps > + > New App
3. Platform: iOS
4. Name: Buds
5. Primary Language: English
6. Bundle ID: app.getbuds.Buds (from dropdown)
7. SKU: `buds-ios-2025`
8. User Access: Full Access

### Step 3: Create Archive

1. Xcode > Product > Archive
2. Wait for archive to complete
3. Window > Organizer > Archives
4. Select your archive
5. Click "Distribute App"
6. Select: App Store Connect
7. Upload: ✓
8. Next > Next > Upload

### Step 4: Configure TestFlight

1. App Store Connect > Your App > TestFlight
2. Wait for processing (~10-30 minutes)
3. Once "Ready to Test":
   - Go to Internal Testing
   - Click "+" to add internal testers
   - Add yourself + friends (email addresses)
4. They'll receive TestFlight invite email

### Step 5: Install TestFlight on iPhone

1. Download "TestFlight" from App Store
2. Open invite email on iPhone
3. Tap "View in TestFlight"
4. Install Buds
5. Open and test!

---

## Quick Reference Commands

### Database
```bash
# View database (install DB Browser for SQLite)
open ~/Library/Developer/CoreSimulator/Devices/[DEVICE_ID]/data/Containers/Data/Application/[APP_ID]/Library/Application\ Support/buds.sqlite
```

### Relay Server
```bash
# Tail logs
wrangler tail

# Local dev
wrangler dev

# Deploy
wrangler deploy
```

### Git
```bash
# Commit workflow
git add .
git commit -m "feat: Add timeline view"
git push

# Create branch
git checkout -b feature/create-memory
```

### Xcode
```bash
# Clean build folder
Cmd+Shift+K

# Reset simulator
Device > Erase All Content and Settings

# Run tests
Cmd+U
```

---

## Troubleshooting

### Firebase not initializing
- Check `GoogleService-Info.plist` is in project
- Check it's added to target
- Clean build folder (Cmd+Shift+K)

### GRDB crashes
- Check database path is writable
- Check migrations ran successfully
- Enable SQL logging to debug queries

### Signing errors
- Check bundle ID matches App Store Connect
- Check certificates are valid in Apple Developer Portal
- Try manual signing if automatic fails

### TestFlight processing stuck
- Wait 30 minutes
- Check App Store Connect > Activity for errors
- Ensure Export Compliance is set (if required)

---

## Next Steps After Foundation

1. ✅ Project compiles and runs
2. ✅ Database creates on launch
3. ✅ Firebase connects
4. ✅ Relay server deployed
5. ✅ TestFlight build uploaded

**Now implement:**
- [ ] Receipt creation (CBOR + signing)
- [ ] Create memory form
- [ ] Timeline with real data
- [ ] Location capture
- [ ] E2EE sharing
- [ ] Agent integration

See DEVELOPMENT_ROADMAP.md for full sequence.

---

**Let's ship! 🚀🌿**
