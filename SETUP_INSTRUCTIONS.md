# Buds - Xcode Setup Instructions

**Ready to run!** All code is wired. Follow these steps to create the Xcode project and run on simulator.

---

## Step 1: Create Xcode Project

```bash
# Open Xcode
# File > New > Project
# Select: iOS > App
```

**Project Settings:**
- **Product Name:** Buds
- **Team:** Your Apple Developer team (or Personal Team for simulator testing)
- **Organization Identifier:** `app.getbuds` (or your domain)
- **Bundle Identifier:** Will be `app.getbuds.Buds`
- **Interface:** SwiftUI
- **Language:** Swift
- **Include Tests:** ✓ Yes

**Save Location:**
```
/Users/ericyarmolinsky/Developer/Buds/
```

**Important:** This will create `/Users/ericyarmolinsky/Developer/Buds/Buds.xcodeproj` in the same folder as this README.

---

## Step 2: Replace Default Files

Xcode created some default files. We'll replace them:

1. **Delete these default files** (select in Xcode, right-click > Delete > Move to Trash):
   - `ContentView.swift`
   - `BudsApp.swift` (we have our own version)

2. **Add our files to the project:**
   - In Finder, drag the entire `Buds/` folder into Xcode sidebar
   - **IMPORTANT:** When prompted, select:
     - ✓ Copy items if needed
     - ✓ Create groups (not folder references)
     - ✓ Add to targets: Buds

Your project should now have this structure:
```
Buds (project)
├── Buds (group)
│   ├── App/
│   ├── Core/
│   ├── Features/
│   ├── Shared/
│   └── Resources/
└── BudsTests/
```

---

## Step 3: Add Dependencies via Swift Package Manager

In Xcode:

### 1. Add GRDB
- File > Add Package Dependencies
- Search: `https://github.com/groue/GRDB.swift`
- Version: Up to Next Major (6.24.0 or latest)
- Click **Add Package**
- Select **GRDB** library
- Click **Add Package**

### 2. Add Firebase
- File > Add Package Dependencies
- Search: `https://github.com/firebase/firebase-ios-sdk`
- Version: Up to Next Major (10.20.0 or latest)
- Click **Add Package**
- Select these libraries:
  - **FirebaseAuth**
  - **FirebaseMessaging**
- Click **Add Package**

### 3. Add SwiftCBOR (for canonical encoding)
- File > Add Package Dependencies
- Search: `https://github.com/unrelenting-technology/SwiftCBOR`
- Version: Up to Next Major (0.4.5 or latest)
- Click **Add Package**
- Select **SwiftCBOR** library
- Click **Add Package**

**Wait for packages to resolve** (check bottom of Xcode window for progress).

---

## Step 4: Configure Build Settings

### A. Set Minimum iOS Version

1. Click project name in sidebar (blue icon)
2. Select **Buds** target (under TARGETS)
3. General tab
4. Set **Minimum Deployments** to: **iOS 17.0**

### B. Enable Strict Concurrency (Swift 6)

1. Still in target settings
2. Go to **Build Settings** tab
3. Search for "strict concurrency"
4. Set **Strict Concurrency Checking** to: **Complete**

### C. Add Info.plist Entries

The `Info-Template.plist` has all the keys you need. Add them to your target:

1. Select **Buds** target
2. Go to **Info** tab
3. Add these custom keys (click +):

```
NSPhotoLibraryUsageDescription = "To add photos to your cannabis memories"
NSCameraUsageDescription = "To capture photos of your experiences"
NSLocationWhenInUseUsageDescription = "To remember where you had your experiences (optional, off by default)"
```

Or just copy the entire `Info-Template.plist` content into your project's `Info.plist`.

---

## Step 5: Firebase Setup (Optional for First Run)

**You can skip this for now** to test locally without Firebase. The app will print a warning but still work.

When ready to add Firebase:

1. Go to https://console.firebase.google.com
2. Create new project: "Buds Dev"
3. Add iOS app:
   - Bundle ID: `app.getbuds.Buds`
   - Download `GoogleService-Info.plist`
   - Drag into Xcode under `Resources/` folder
   - ✓ Ensure "Copy items if needed"
   - ✓ Add to target: Buds

---

## Step 6: Build & Run!

1. Select **iPhone 15 Pro** simulator (or any iOS 17+ device)
2. Click **▶️ Run** button (or `Cmd+R`)

**Expected result:**
- App launches
- You see "🌿 No memories yet" empty state
- Tap **+** button → Create memory form opens
- Fill in strain name, rating, etc.
- Tap **Save** → Memory appears in timeline!

---

## Troubleshooting

### Build fails: "Cannot find 'Database' in scope"

**Fix:** Clean build folder and rebuild
```bash
Cmd+Shift+K (clean)
Cmd+B (build)
```

### Build fails: "Missing import for GRDB"

**Fix:** Package dependencies didn't resolve
- File > Packages > Resolve Package Versions
- Wait for completion, then build again

### Firebase warnings in console

**Expected if you haven't added GoogleService-Info.plist yet.**
```
⚠️ Firebase not configured (expected for local testing)
```

This is fine! The app works without Firebase for local-only testing.

### "No memories appear after saving"

**Check console for:**
```
✅ Created receipt: bafyrei...
✅ Memory created successfully
```

If you see errors, check:
- Database initialized? Look for: `✅ Database initialized at: ...`
- Receipt signed? Look for: `✅ Generated new Ed25519 signing keypair`

### Keychain errors in simulator

**Fix:** Reset simulator
```bash
Device > Erase All Content and Settings
```

Then rebuild and run.

---

## What's Working Now

✅ **Database:** GRDB with all 7 tables
✅ **Receipts:** Canonical CBOR encoding + Ed25519 signing
✅ **Identity:** Ed25519/X25519 keypairs + DID generation
✅ **UI:** Timeline, Create Memory form, Memory cards
✅ **Core Flow:** Create memory → Sign receipt → Store in DB → Display in timeline

---

## Next Steps (After First Run)

1. **Test creating 3-5 memories** to see timeline populate
2. **Add Firebase** (for phone auth in future)
3. **Test on real device** (sign with your Apple Developer account)
4. **Continue building:**
   - Map view
   - Location capture
   - Circle sharing (E2EE)
   - Agent integration

See [DEVELOPMENT_ROADMAP.md](./docs/DEVELOPMENT_ROADMAP.md) for full build plan.

---

**Ready? Let's ship! 🚀🌿**
