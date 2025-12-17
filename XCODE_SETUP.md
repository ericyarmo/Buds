# Xcode Project Setup - Buds v0.1

Complete Xcode configuration for the Buds app.

---

## 1. Bundle Identifier & App Info

### Open Project Settings
1. Open `Buds.xcodeproj` in Xcode
2. Select **Buds** project in navigator
3. Select **Buds** target
4. Go to **General** tab

### Set Bundle Identifier
```
com.yourname.Buds
```
(Replace `yourname` with your actual developer name/company)

### App Display Name
- **Display Name:** `Buds`
- **Bundle Name:** `Buds`
- **Version:** `0.1.0`
- **Build:** `1`

### Deployment Info
- **iOS Deployment Target:** `17.0` (minimum)
- **iPhone only** (uncheck iPad)
- **Supports multiple windows:** OFF
- **Requires full screen:** ON

---

## 2. Info.plist Configuration

### Open Info.plist
1. Select **Buds** target
2. Go to **Info** tab
3. Add the following keys:

### Required Privacy Descriptions

#### Camera Access
```xml
<key>NSCameraUsageDescription</key>
<string>Buds needs camera access to capture photos of your cannabis memories.</string>
```

#### Photo Library Access
```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Buds needs photo library access to select and save cannabis memory photos.</string>
```

#### Photo Library Add Only
```xml
<key>NSPhotoLibraryAddUsageDescription</key>
<string>Buds needs permission to save photos to your library.</string>
```

### App Configuration
```xml
<key>UIApplicationSceneManifest</key>
<dict>
    <key>UIApplicationSupportsMultipleScenes</key>
    <false/>
</dict>

<key>UILaunchScreen</key>
<dict>
    <key>UIColorName</key>
    <string>budsPrimary</string>
</dict>
```

### Supported Orientations (iPhone only)
```xml
<key>UISupportedInterfaceOrientations</key>
<array>
    <string>UIInterfaceOrientationPortrait</string>
</array>
```

---

## 3. Capabilities

### Go to: Signing & Capabilities Tab

#### Add Capabilities:
1. **Keychain Sharing**
   - Group: `$(AppIdentifierPrefix)com.yourname.Buds`

2. **Background Modes** (for future push notifications)
   - Remote notifications

---

## 4. Build Settings

### Search for these settings:

#### Swift Language Version
- **Swift Language Version:** `Swift 6`

#### Other Swift Flags
**Debug:**
```
-DDEBUG
```

**Release:**
(leave empty)

#### Enable Testing
- **Enable Testing Search Paths:** YES (Debug only)

---

## 5. App Icon Setup

### Create App Icon Set:
1. Go to `Assets.xcassets`
2. Right-click → New App Icon
3. Name it `AppIcon`

### Icon Sizes Needed:
- 1024x1024 (App Store)
- 180x180 (iPhone @3x)
- 120x120 (iPhone @2x)
- 76x76 (iPad - if adding later)

**For now:** Use a simple green cannabis leaf icon or placeholder.

**Design notes:**
- Primary color: `#4CAF50` (budsPrimary)
- Simple, minimal design
- Cannabis leaf silhouette works well

---

## 6. Launch Screen

Xcode 15+ uses `UILaunchScreen` in Info.plist (already configured above).

**Optional:** Create custom launch screen:
1. Add `LaunchScreen.storyboard` to project
2. Set simple background color to `budsPrimary`
3. Add "Buds" text label (optional)

---

## 7. Signing

### Development Signing
1. Go to **Signing & Capabilities**
2. Check **Automatically manage signing**
3. Select your **Team** (Personal Team is fine)
4. Xcode will generate provisioning profile

### If No Team:
1. Add Apple ID: **Xcode → Settings → Accounts**
2. Click **+** → Add Apple ID
3. Select that account as Team

---

## 8. Simulator Setup

### Select Simulator
1. Click device selector (top bar)
2. Choose: **iPhone 15 Pro** (recommended)
3. Or: **iPhone 15**, **iPhone 14 Pro**

### If Simulators Missing:
1. **Xcode → Settings → Platforms**
2. Download iOS 18.0+ Simulator

---

## 9. Build & Run

### First Build
```bash
# In Xcode:
Cmd + B  # Build
Cmd + R  # Run

# Or via terminal:
cd Buds/Buds
xcodebuild -scheme Buds -destination "platform=iOS Simulator,name=iPhone 15 Pro"
```

### Expected Output:
- Build succeeds (no errors)
- Simulator launches
- App shows Timeline view
- Can tap "+" to create memory
- Can save memory (receipt creation works)

---

## 10. Troubleshooting

### Build Failed - Missing Package Dependencies
**Fix:**
1. **File → Packages → Resolve Package Versions**
2. Wait for download
3. Rebuild

### Signing Error
**Fix:**
1. Change Bundle Identifier to something unique
2. Example: `com.yourname.BudsApp2024`

### Simulator Won't Launch
**Fix:**
1. Quit Simulator app
2. **Xcode → Product → Clean Build Folder** (Cmd + Shift + K)
3. Rebuild (Cmd + B)
4. Run (Cmd + R)

### Database Locked
**Fix:**
1. Reset simulator: **Device → Erase All Content and Settings**
2. Rebuild

---

## 11. Firebase Setup (Do This Next)

Once Xcode is configured, you'll need:

1. **Create Firebase Project**
   - Go to: https://console.firebase.google.com
   - Create new project: "Buds"
   - Enable Phone Authentication
   - Download `GoogleService-Info.plist`

2. **Add to Xcode**
   - Drag `GoogleService-Info.plist` into Xcode project
   - Make sure "Copy items if needed" is checked
   - Select Buds target

3. **Add Firebase SDK** (if not already added)
   - **File → Add Packages**
   - URL: `https://github.com/firebase/firebase-ios-sdk`
   - Add: `FirebaseAuth`, `FirebaseCore`

---

## Checklist

Before proceeding to Phase 3 & 4:

- [ ] Bundle identifier set
- [ ] Info.plist camera/photos permissions added
- [ ] App builds successfully
- [ ] Can run on simulator
- [ ] Can create and save a memory
- [ ] Timeline shows saved memories
- [ ] No console errors

---

**Status:** Ready for Phase 3 (Images) + Phase 4 (Firebase Auth)! 🌿
