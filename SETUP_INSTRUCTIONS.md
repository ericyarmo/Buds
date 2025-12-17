# Buds v0.1 - Setup Instructions

This guide walks you through setting up the Buds project on your Mac and running it in the iOS Simulator.

**Estimated time:** 10-15 minutes

---

## Prerequisites

- **macOS 13+** (Sonoma or later recommended)
- **Xcode 15+** (download from [App Store](https://apps.apple.com/us/app/xcode/id497799835))
- **Git** (check with `git --version` in Terminal)
- **Apple Developer Account** (free - not required for simulator testing)

---

## Step 1: Clone the Repository

```bash
# Clone the Buds repo (update URL based on your GitHub setup)
git clone https://github.com/YOUR_USERNAME/Buds.git
cd Buds
```

---

## Step 2: Open the Xcode Project

The Xcode project is located in the `Buds/Buds/` directory.

```bash
# Navigate to the project directory
cd Buds/Buds

# Open in Xcode
open Buds.xcodeproj
```

Xcode should open and show the project structure.

---

## Step 3: Install Swift Package Dependencies

Xcode should automatically resolve dependencies from `Package.swift`. If not:

1. In Xcode menu: **File → Add Packages**
2. Add the following SPM packages (if not already added):

### Required Dependencies

#### GRDB (Database)
- **Package URL:** `https://github.com/groue/GRDB.swift`
- **Version:** 6.20+ (latest)
- **Products:** Select `GRDB`

#### Firebase iOS SDK (Optional for local testing)
- **Package URL:** `https://github.com/firebase/firebase-ios-sdk`
- **Version:** 10.20+ (latest)
- **Products:** Select `FirebaseCore`
- **Note:** Firebase is optional for local simulator testing. You can skip this for now and enable it later when adding phone authentication.

#### SwiftCBOR (CBOR Encoding)
- **Package URL:** `https://github.com/myaut/SwiftCBOR`
- **Version:** Latest
- **Products:** Select `SwiftCBOR`

### How to Add Packages in Xcode

1. **File → Add Packages**
2. Paste the URL in the search box
3. Select the correct version
4. Click **Add Package**
5. Select the target `Buds` when prompted
6. Click **Add Package** again to confirm

---

## Step 4: Select Build Target

Ensure you're building for the correct target:

1. In Xcode, select the **Buds** project (left sidebar)
2. Select the **Buds** target
3. Go to **Build Settings** tab
4. Search for "iOS Deployment Target" and ensure it's set to **14.0+**

---

## Step 5: Select Simulator

1. At the top of Xcode, click the device selector (next to the play button)
2. Choose a simulator: **iPhone 15** or **iPhone 15 Pro** (recommended)
3. If no simulators are available:
   - **Xcode → Settings → Locations → Runtimes**
   - Download iOS 18+ runtime

---

## Step 6: Build and Run

### Option 1: Using Xcode UI
1. Press **Cmd + R** to build and run
2. Wait for the simulator to launch (first build takes 2-3 minutes)
3. The Buds app should open in the simulator

### Option 2: Using Terminal
```bash
# Build for simulator
xcodebuild build -scheme Buds -destination "generic/platform=iOS Simulator"

# Run the app (if you have the app set up)
xcodebuild test -scheme Buds -destination "platform=iOS Simulator,name=iPhone 15"
```

---

## Step 7: Test the App

Once running, you should see:

1. **Timeline View** (default tab)
   - Shows "No memories yet" message
   - Tap the **+** button to create a new memory

2. **Create Memory Flow**
   - Fill in the strain name (required)
   - Select product type (flower, edible, etc.)
   - Set a rating (1-5 stars)
   - Add optional notes
   - Select effects (relaxed, creative, etc.)
   - Add optional product details (brand, THC%, CBD%)
   - Select consumption method (joint, bong, etc.)
   - Tap **Save**

3. **Verify Creation**
   - Return to Timeline
   - Your memory should appear as a card
   - Pull down to refresh if needed

---

## Step 8: Check Database

Memories are stored in SQLite locally. To verify:

### Using Command Line
```bash
# Find the database file (if running on simulator)
find ~/Library/Developer/CoreSimulator/Devices -name "*.db" | grep -i buds
```

### Using TablePlus (GUI)
1. Download [TablePlus](https://tableplus.com/) (free)
2. **File → Open**
3. Navigate to the database file
4. View tables: `local_receipts`, `ucr_headers`, etc.

---

## Troubleshooting

### Build Fails with "Cannot find GRDB in scope"
**Solution:**
1. Delete derived data: **Xcode → Settings → Locations → Derived Data** (click arrow)
2. Delete the folder
3. Rebuild with **Cmd + Shift + K** then **Cmd + B**

### Simulator Won't Launch
**Solution:**
1. Kill Xcode completely
2. Quit Simulator: **Simulator → Device → Reset or → Erase All Content and Settings**
3. Restart Xcode and try again

### "App Installation Failed"
**Solution:**
1. Delete the app from the simulator: Long-press the Buds app → Remove App
2. Clean build folder: **Cmd + Shift + K**
3. Rebuild: **Cmd + B**

### Database Locked Error
**Solution:**
1. The database is used by the app. If you see "database is locked" errors:
2. Restart the simulator
3. Or reset the app: Simulator → Device → Reset

### Firebase Not Found
**Solution:**
- Firebase is optional for local testing
- If you see Firebase errors, disable it in `BudsApp.swift` (already handled)
- The app works perfectly without Firebase on the simulator

---

## Next Steps

Once you've verified the app runs:

1. **Create a few test memories** to populate the timeline
2. **Read [ARCHITECTURE.md](./docs/ARCHITECTURE.md)** to understand the system design
3. **Read [CANONICALIZATION_SPEC.md](./docs/CANONICALIZATION_SPEC.md)** to understand receipt signing
4. **Check [NEXT_PHASE_PLAN.md](./NEXT_PHASE_PLAN.md)** for the roadmap

---

## Key Project Structure

```
Buds/
├── Buds/                           # iOS app
│   ├── Buds/
│   │   ├── App/
│   │   │   └── BudsApp.swift       # App entry point
│   │   ├── Core/
│   │   │   ├── ChaingeKernel/      # Receipt signing + CBOR
│   │   │   ├── Database/           # GRDB setup + migrations
│   │   │   └── Models/             # UCRHeader, Memory, etc.
│   │   ├── Features/
│   │   │   ├── Timeline/           # Main feed
│   │   │   ├── CreateMemory/       # Form to create memories
│   │   │   └── MainTabView.swift   # Tab navigation
│   │   └── Shared/
│   │       ├── Utilities/          # Colors, Typography, Spacing
│   │       └── Views/              # MemoryCard, EffectTag, etc.
│   └── BudsTests/                  # Unit tests
├── docs/                           # Architecture documentation
├── BudsKernelGolden/               # Physics-tested crypto kernel
└── README.md                       # Project overview
```

---

## Performance Notes

**Receipt Creation Performance:**
- Encode + CID + Sign: **0.11ms p50** (from BudsKernelGolden tests)
- Operations are non-blocking (async/await)
- UI stays responsive

**Database Performance:**
- GRDB is production-grade SQLite wrapper
- Migrations run automatically on app launch
- Supports up to millions of memories on-device

---

## Need Help?

If you encounter issues:

1. Check the **troubleshooting section** above
2. Review logs in **Xcode Console** (Cmd + Shift + C)
3. Try a clean build: **Cmd + Shift + K** then **Cmd + B**
4. Check GitHub issues: https://github.com/YOUR_USERNAME/Buds/issues

---

## What's Next?

See [NEXT_PHASE_PLAN.md](./NEXT_PHASE_PLAN.md) for:
- Phase 3: Images + Memory Enhancement
- Phase 4: Firebase Authentication
- Phase 5: Cloudflare Relay Server
- Phase 6: Circle Mechanics

Enjoy building! 🌿
