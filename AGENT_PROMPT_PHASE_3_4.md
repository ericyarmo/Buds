# Agent Task: Phase 3 + 4 - Images & Firebase Auth

Complete Phase 3 (Images + Memory Enhancement) and Phase 4 (Firebase Authentication) for the Buds app.

---

## Context

**Project:** Buds v0.1 - Private cannabis memory sharing app
**Location:** `/Users/ericyarmolinsky/Developer/Buds`
**Current State:** v0.1 foundation complete - receipts, database, basic UI working

**Read these first:**
- `NEXT_PHASE_PLAN.md` - Detailed phase breakdown
- `docs/ARCHITECTURE.md` - System architecture
- `docs/DATABASE_SCHEMA.md` - Database tables

---

## Your Mission

Implement **Phase 3** (Images) and **Phase 4** (Firebase Auth) from NEXT_PHASE_PLAN.md with these **critical changes**:

### Phase 3 Modifications (from plan):
- **Support 3 images per memory** (not 1)
- Users can select/capture up to 3 photos
- Swipe through images in MemoryCard
- Swipe through in MemoryDetailView
- Store all 3 image CIDs in database (update schema if needed)

### Phase 4 Requirements (from plan):
- Firebase phone authentication
- Onboarding flow (first launch only)
- Profile setup with display name
- Store phone in Keychain (encrypted)
- Link Firebase UID to local DID

---

## Phase 3: Images + Memory Enhancement

### Tasks:

#### 1. Photo Capture/Selection (3 images max)
- [ ] Add PhotosPicker to CreateMemoryView (allow selecting up to 3)
- [ ] Camera capture option (UIImagePickerController) 
- [ ] Image compression (max 2MB per photo)
- [ ] Store in `blobs` table with CID for each image
- [ ] Update schema: `local_receipts` should support multiple image CIDs (JSON array or separate table)

#### 2. Image Display
- [ ] MemoryCard: Show image carousel (swipe through 3 images)
- [ ] Use TabView or custom swipe view
- [ ] Page indicator dots
- [ ] Tap card to open MemoryDetailView

#### 3. Memory Detail View (NEW)
- [ ] Full-screen view when tapping a memory card
- [ ] Show all fields: strain, rating, notes, effects, product details, method
- [ ] Image carousel at top (swipe through 3 images)
- [ ] Full-size image tap to expand
- [ ] Edit button (navigate to edit view - can be placeholder)
- [ ] Delete button with confirmation
- [ ] Share button (placeholder for Circle sharing)

#### 4. Database Schema Update
Current schema has `local_receipts.image_cid TEXT` for one image.

**Options:**
A. Change to `image_cids TEXT` storing JSON array: `["cid1", "cid2", "cid3"]`
B. Create junction table `memory_images` with `(receipt_id, image_cid, display_order)`

**Choose Option A** (simpler for v0.1)

#### Files to Create:
- `Buds/Features/CreateMemory/PhotoPicker.swift` - Photo selection component
- `Buds/Features/Timeline/MemoryDetailView.swift` - Full memory view
- `Buds/Shared/Views/ImageCarousel.swift` - Swipeable image carousel

#### Files to Update:
- `CreateMemoryView.swift` - Add photo picker (3 images)
- `MemoryCard.swift` - Show image carousel
- `Memory.swift` - Update model for 3 images
- `MemoryRepository.swift` - Handle multiple images
- `Database.swift` - Migration for schema change

---

## Phase 4: Firebase Authentication

### Prerequisites:
User must complete Firebase setup:
1. Create project at console.firebase.google.com
2. Enable Phone Authentication
3. Download `GoogleService-Info.plist` to project
4. Add Firebase SDK packages (FirebaseAuth, FirebaseCore)

**Assume user has done this before running this agent.**

### Tasks:

#### 1. Firebase Integration
- [ ] Verify `GoogleService-Info.plist` exists
- [ ] Update `BudsApp.swift` to initialize Firebase properly
- [ ] Create `FirebaseManager.swift` singleton

#### 2. Phone Auth Flow
- [ ] Create `PhoneAuthView.swift` - Phone number input
- [ ] Create `VerificationCodeView.swift` - SMS code input
- [ ] Implement Firebase phone auth
- [ ] Store verified phone in Keychain (encrypted, separate from DID keys)
- [ ] Link Firebase UID to local DID in new table or UserDefaults

#### 3. Onboarding Flow
- [ ] Create `OnboardingCoordinator.swift` - Checks if first launch
- [ ] If first launch → show PhoneAuthView
- [ ] After auth → show ProfileSetupView
- [ ] After profile → navigate to MainTabView
- [ ] Store "onboarded" flag in UserDefaults

#### 4. Profile Setup
- [ ] Create `ProfileSetupView.swift`
- [ ] Display name input (local only, NOT shared)
- [ ] Location toggle (ON/OFF, default OFF)
- [ ] Create `profile.created/v1` receipt with display name
- [ ] Store profile in `profiles` table (or UserDefaults)

#### 5. App Launch Logic
Update `BudsApp.swift`:
```swift
var body: some Scene {
    WindowGroup {
        if !hasCompletedOnboarding {
            PhoneAuthView()
        } else {
            MainTabView()
        }
    }
}
```

#### Files to Create:
- `Core/Auth/FirebaseManager.swift`
- `Features/Onboarding/PhoneAuthView.swift`
- `Features/Onboarding/VerificationCodeView.swift`
- `Features/Onboarding/ProfileSetupView.swift`
- `Features/Onboarding/OnboardingCoordinator.swift`

#### Files to Update:
- `BudsApp.swift` - Conditional rendering based on onboarding
- `Database.swift` - Add profiles table if needed
- `IdentityManager.swift` - Link Firebase UID to DID

---

## Critical Requirements

### Images (Phase 3):
1. **3 images maximum** per memory
2. Swipe through images in card AND detail view
3. First image is "cover" image shown in timeline
4. All images stored in `blobs` table
5. Image CIDs stored as JSON array in `local_receipts.image_cids`

### Authentication (Phase 4):
1. Phone number **NEVER** stored in receipts (Keychain only)
2. Firebase UID → local DID mapping
3. Display name is local-only (NOT shared via receipts)
4. Onboarding only on first launch
5. Skip onboarding if already completed

---

## Acceptance Criteria

### Phase 3:
- ✅ Can select up to 3 photos from library
- ✅ Can capture up to 3 photos with camera
- ✅ Photos appear in MemoryCard (swipeable)
- ✅ Tap card opens MemoryDetailView
- ✅ Can swipe through 3 images in detail view
- ✅ Can delete memory from detail view
- ✅ All images persist in database
- ✅ Timeline loads memories with all images

### Phase 4:
- ✅ New users see phone auth screen
- ✅ Can enter phone number + verify SMS code
- ✅ Phone stored securely in Keychain
- ✅ Can set display name in profile setup
- ✅ After onboarding, goes to main app
- ✅ Returning users skip onboarding
- ✅ Firebase UID linked to local DID

---

## Testing Steps

### Phase 3:
1. Create memory with 3 photos
2. Verify all 3 appear in timeline card (swipe)
3. Tap card → verify detail view shows all 3 (swipe)
4. Create memory with 1 photo → still works
5. Delete memory → verify images removed from blobs table
6. Restart app → verify images persist

### Phase 4:
1. Delete app from simulator
2. Reinstall → should show phone auth
3. Enter test phone number (set up in Firebase Console)
4. Verify SMS code → should go to profile setup
5. Enter display name → should go to main app
6. Restart app → should go directly to main app (skip onboarding)
7. Verify phone number in Keychain (not in receipts)

---

## Database Migrations

### Phase 3 Migration:
```swift
// In Database.swift, add migration "v2":
migrator.registerMigration("v2") { db in
    // Rename image_cid to image_cids
    try db.execute(sql: """
        ALTER TABLE local_receipts 
        RENAME COLUMN image_cid TO image_cids
    """)
    
    // Update existing records (empty array)
    try db.execute(sql: """
        UPDATE local_receipts 
        SET image_cids = '[]' 
        WHERE image_cids IS NULL
    """)
}
```

### Phase 4: No schema changes needed (use Keychain + UserDefaults)

---

## Code Style Notes

1. **Follow existing patterns** in CreateMemoryView.swift and TimelineView.swift
2. **Use async/await** for all async operations
3. **Error handling:** Always catch and display user-friendly errors
4. **Clean, minimal UI** - Match existing Buds design system
5. **No emojis** in production code (user removed them)
6. **Comments:** Only where logic isn't self-evident

---

## Firebase Test Phone Numbers

Set these up in Firebase Console → Authentication → Phone:

- `+1 555 123 4567` → Code: `123456`
- `+1 555 999 8888` → Code: `999999`

Use these for testing without real SMS.

---

## File Structure After Completion

```
Buds/
├── Core/
│   ├── Auth/
│   │   └── FirebaseManager.swift          (new)
│   ├── ChaingeKernel/
│   └── Database/
│       └── Database.swift                  (updated - migration v2)
├── Features/
│   ├── CreateMemory/
│   │   ├── CreateMemoryView.swift          (updated - 3 photos)
│   │   └── PhotoPicker.swift               (new)
│   ├── Timeline/
│   │   ├── TimelineView.swift
│   │   └── MemoryDetailView.swift          (new)
│   ├── Onboarding/
│   │   ├── PhoneAuthView.swift             (new)
│   │   ├── VerificationCodeView.swift      (new)
│   │   ├── ProfileSetupView.swift          (new)
│   │   └── OnboardingCoordinator.swift     (new)
│   └── MainTabView.swift
├── Shared/
│   ├── Views/
│   │   ├── MemoryCard.swift                (updated - carousel)
│   │   └── ImageCarousel.swift             (new)
│   └── Utilities/
└── App/
    └── BudsApp.swift                       (updated - onboarding check)
```

---

## Stretch Goal (Optional)

**Image Analysis Agent:**
- Use Vision framework to analyze image
- Detect text (strain name, THC%, brand)
- Auto-fill CreateMemoryView fields
- "Scan & Fill" button in CreateMemoryView

**Only implement if time permits.** Not required for Phase 3/4 completion.

---

## Questions to Ask User

Before starting:
1. "Do you have `GoogleService-Info.plist` in the project?"
2. "Have you set up test phone numbers in Firebase Console?"
3. "Should I implement the image analysis agent (stretch goal) or skip it?"

---

## Final Deliverables

1. **All Phase 3 tasks complete** (3 images, carousel, detail view)
2. **All Phase 4 tasks complete** (Firebase auth, onboarding, profile)
3. **App builds and runs** without errors
4. **Test flows work** (create memory with photos, onboarding flow)
5. **Code is clean** and follows existing patterns

---

**Ready to ship Phase 3 + 4!** 🚀🌿

Let me know when you're ready to start, and I'll proceed systematically through each task.
