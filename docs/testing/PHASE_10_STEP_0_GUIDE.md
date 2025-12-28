# Phase 10 Step 0: Critical Pre-Flight Testing Guide

**Status**: Ready to execute
**Time**: 1.5 hours
**CRITICAL**: If any test fails, ABORT TestFlight

---

## Overview

Step 0 verifies that:
1. E2EE doesn't break after jar deletion (RELEASE BLOCKER)
2. Build can be archived and validated (catch signing issues early)
3. Memory usage is acceptable with 100+ buds (performance baseline)

---

## Step 0.1: E2EE Verification Invariance Test

### What This Tests

Verifies that moving buds to Solo jar (by updating `jar_id` in `local_receipts`) doesn't change the cryptographic verification bytes.

**If this fails**: jar_id is somehow part of signed content → ABORT TestFlight, fix crypto first.

### Files Created

- `/Tests/E2EEVerificationTest.swift` - Core test logic
- `/Features/Debug/E2EETestView.swift` - UI to run test
- Updated `/Features/Profile/ProfileView.swift` - Added debug section

### How to Run

1. **Add files to Xcode** (if not already added):
   - Right-click on `Tests` folder → Add Files
   - Select `E2EEVerificationTest.swift`
   - Right-click on `Features/Debug` folder → Add Files
   - Select `E2EETestView.swift`
   - Ensure both have target membership: Buds ✓

2. **Build and run app** (CMD+R)

3. **Navigate to Profile tab**

4. **Scroll down to "Debug & Testing" section**

5. **Tap "E2EE Verification Test"**

6. **Tap "Run Test"**

7. **Wait for test to complete** (~10-15 seconds)

### Expected Output

The test will:
1. Create jar "Crypto Test"
2. Add bud to jar
3. Log verification bytes BEFORE jar deletion
4. Delete jar (buds move to Solo)
5. Log verification bytes AFTER jar deletion
6. Compare the bytes

### Pass Criteria ✅

```
✅ ✅ ✅ PASS: Verification bytes UNCHANGED
Receipt CID: bafyrei...
Bytes (hex): a1b2c3...

✅ Jar deletion is SAFE for E2EE
✅ OK TO PROCEED WITH TESTFLIGHT
```

**If you see this**: Continue to Step 0.2

### Fail Criteria ❌

```
❌ ❌ ❌ FAIL: Verification bytes CHANGED
BEFORE: a1b2c3...
AFTER:  d4e5f6...

🚨 ABORT TESTFLIGHT - CRYPTO IS BROKEN
🚨 jar_id update is changing signed content
🚨 Fix before shipping!
```

**If you see this**:
1. **STOP immediately**
2. **Do NOT proceed to Step 0.2**
3. Share console logs with Claude
4. We need to investigate why jar_id is affecting verification

### Debugging

If test crashes or fails unexpectedly:

**Check Xcode console** for detailed logs:
- Look for print statements starting with "🔍", "📝", "✅", or "❌"
- Share full console output

**Common issues**:
- No Solo jar exists → Test should auto-create it
- Database error → Check Database.swift schema
- Signature data missing → Check UCR receipt creation

---

## Step 0.2: Archive + Validate Early

### Why This Matters

Catch signing, entitlements, and privacy manifest issues BEFORE writing more code. Export compliance prompts happen here too.

### How to Run

1. **Clean build folder**:
   ```
   CMD+SHIFT+K (Clean Build Folder)
   ```

2. **Build for release**:
   ```
   CMD+B (Build)
   ```
   - Verify 0 errors, 0 warnings
   - If warnings exist, note them (acceptable for now, but should fix later)

3. **Archive**:
   ```
   Product → Archive
   ```
   - Wait for archive to complete (~2-5 minutes)
   - Xcode Organizer will open automatically

4. **Validate**:
   - In Organizer, select the new archive
   - Click "Validate App"
   - Choose distribution method: **App Store Connect**
   - Follow prompts

### Expected Prompts

**1. Export Compliance**:
```
Does your app use encryption?
```
**Answer**: YES (we use E2EE with Apple's CryptoKit)

```
Is your app exempt from export compliance requirements?
```
**Answer**: YES (using standard encryption APIs, no custom crypto)

**Note**: This might vary based on Apple's current requirements. Read carefully.

**2. Provisioning Profile**:
- Should auto-select or prompt you to choose
- Use "Automatic" if available

**3. Privacy Manifest**:
- Should validate automatically
- If errors appear, note them

### Pass Criteria ✅

```
Validation successful
App is ready for distribution
```

**Action**: Take screenshot, continue to Step 0.3

### Fail Criteria ❌

**Common failures**:

1. **Signing errors**:
   ```
   No signing certificate found
   Provisioning profile invalid
   ```
   **Fix**: Configure signing in Xcode project settings
   - Target → Signing & Capabilities
   - Enable "Automatically manage signing"
   - Select your team

2. **Privacy manifest errors**:
   ```
   Missing required privacy manifest
   ```
   **Fix**: Add PrivacyInfo.xcprivacy file
   - Right-click project → New File → App Privacy File
   - Configure required permissions

3. **Entitlements errors**:
   ```
   Invalid entitlements
   ```
   **Fix**: Check Buds.entitlements file
   - Ensure all capabilities are correctly configured
   - Remove any unused entitlements

**If validation fails**:
1. **Copy full error message**
2. **Share with Claude**
3. **Fix issues before continuing**
4. **Re-validate until it passes**

---

## Step 0.3: Memory Baseline Test

### What This Tests

Ensures that displaying 100+ buds in a jar doesn't cause memory explosion or crashes.

**Target**: <100MB memory usage with 100 buds

### How to Run

#### Option A: Manual Test (Recommended)

1. **Build and run with Instruments**:
   ```
   Product → Profile
   Choose "Allocations" template
   ```

2. **Create test jar**:
   - Open app
   - Create jar "Memory Test"

3. **Add 100 buds** (automated):
   - Navigate to Profile → Debug & Testing
   - Tap "Create 100 Test Buds" (we'll add this button)
   - Wait for completion (~30 seconds)

4. **Navigate to jar**:
   - Go to Shelf
   - Tap "Memory Test" jar
   - Wait for list to load

5. **Scroll rapidly**:
   - Scroll up and down quickly for 30 seconds
   - Monitor Allocations in Instruments

6. **Check metrics**:
   - Peak memory usage
   - Scroll performance (should be 60fps)

#### Option B: Xcode Memory Debugger

1. **Build and run** (CMD+R)

2. **Create jar with 100 buds** (same as above)

3. **Open Memory Debugger**:
   ```
   Debug → Debug Workflow → View Memory Graph
   ```

4. **Check total memory**:
   - Look at bottom of Xcode: "Memory: X MB"
   - Should be <100MB

### Pass Criteria ✅

- **Memory usage**: <100MB with 100 buds
- **Scroll performance**: Smooth 60fps
- **No crashes**
- **No jank or stuttering**

**If you see this**: All Step 0 tests passed → Continue to Step 1

### Fail Criteria ❌

**Memory >100MB**:
- Likely cause: Images not downscaled before storage
- Fix: Implement thumbnail downscaling in addImages()

**Scroll stutters**:
- Likely cause: Decoding images on main thread
- Fix: Use CachedAsyncImage with background decoding

**App crashes**:
- Likely cause: Out of memory
- Fix: Reduce number of buds loaded, add pagination

**If memory test fails**:
1. **Note exact memory usage**
2. **Take screenshot of Instruments**
3. **Share with Claude**
4. **Do NOT proceed until fixed**

---

## Helper: Create 100 Test Buds

Add this to E2EETestView.swift for convenience:

```swift
// Add to E2EETestView
Button {
    createTestBuds()
} label: {
    Text("Create 100 Test Buds")
}

func createTestBuds() {
    Task {
        let jarID = "test_jar_id"  // Replace with actual jar ID
        let repository = MemoryRepository()

        for i in 1...100 {
            _ = try? await repository.create(
                strainName: "Test Strain \(i)",
                productType: .flower,
                rating: (i % 5) + 1,
                notes: "Test bud #\(i) for memory baseline testing",
                brand: "Test Brand",
                thcPercent: Double.random(in: 15...30),
                cbdPercent: Double.random(in: 0...2),
                amountGrams: 3.5,
                effects: ["relaxed", "happy"],
                consumptionMethod: .joint,
                locationCID: nil,
                jarID: jarID
            )
        }
        print("✅ Created 100 test buds")
    }
}
```

---

## Step 0 Checklist

Before proceeding to Step 1, verify:

- [ ] **0.1 PASSED**: E2EE verification bytes unchanged
- [ ] **0.2 PASSED**: Archive validates successfully
- [ ] **0.3 PASSED**: Memory usage <100MB with 100 buds
- [ ] All console logs saved
- [ ] Screenshots taken of test results
- [ ] No critical errors or warnings

**If all 3 passed**: 🎉 **Proceed to Step 1**

**If ANY failed**: 🛑 **STOP - Fix before continuing**

---

## Time Breakdown

| Step | Task | Time |
|------|------|------|
| 0.1 | Run E2EE test | 5 min |
| 0.2 | Archive + Validate | 30 min |
| 0.3 | Memory baseline test | 30 min |
| Buffer | Issues/debugging | 30 min |
| **Total** | | **1.5 hours** |

---

## Next Steps

After Step 0 passes:
1. Mark Step 0 as complete in PHASE_10_FINAL.md
2. Proceed to Step 1: Single-sheet create flow
3. Continue with Phase 10 implementation

---

**Step 0 is CRITICAL. Do not skip. Do not rush.** 🛡️
