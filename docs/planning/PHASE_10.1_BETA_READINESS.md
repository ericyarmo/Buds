# Phase 10.1: Beta Readiness - 20-50 Real Users

**Date**: December 28, 2025
**Timeline**: 15-20 hours
**Status**: Planning
**Goal**: Ship TestFlight beta that 20-50 real users can use without frustration

---

## Overview

**Current State**: All core infrastructure works (E2EE, DB, receipts, jars, members, create flows).
**Problem**: Missing connectors, polish, and user guidance make it feel "half-broken".
**Goal**: Fill gaps so users can create, view, edit, delete buds without hitting dead ends.

**Parallel Track**: While building this, developer continues Phases 11-14 (map, shop, AI) separately.

---

## Module 1: Memory System (Bud CRUD)

**Current State**:
- ✅ Can create buds (camera, form, metadata, images)
- ✅ Can view bud list (MemoryListCard in JarDetailView)
- ❌ Can't tap into bud detail
- ❌ Can't edit existing buds
- ❌ Can't delete individual buds

### 1.1 Memory Detail View (4-5 hours)

**Build**: Full-screen view to display a single bud's data.

**Requirements**:
- Show all metadata (strain, type, rating, notes, effects, flavors)
- Display all images in scrollable gallery
- Show timestamps (created, last edited)
- Show jar name & members
- Navigation from MemoryListCard tap

**Files to Create**:
- `Features/Memory/MemoryDetailView.swift`

**Files to Modify**:
- `Features/Circle/MemoryListCard.swift` - Add navigation
- `Features/Circle/JarDetailView.swift` - Add NavigationLink

**Acceptance Criteria**:
- [ ] Tap bud card → see full detail view
- [ ] All images load (full resolution, not thumbnails)
- [ ] All metadata displays correctly
- [ ] Back button returns to jar list
- [ ] Works offline (no network calls)

---

### 1.2 Edit Memory Flow (3-4 hours)

**Build**: Reuse CreateMemoryView in edit mode.

**Requirements**:
- Pre-populate form with existing data
- Allow editing all fields except jar (use "Move" for that)
- Update receipt system (create new receipt with same UUID)
- Show "Updated" timestamp

**Files to Modify**:
- `Features/CreateMemory/CreateMemoryView.swift` - Add edit mode
- `Core/Database/Repositories/MemoryRepository.swift` - Add update method

**Acceptance Criteria**:
- [ ] Toolbar "Edit" button in MemoryDetailView
- [ ] Form pre-fills with current values
- [ ] Can change images (add/remove)
- [ ] Save creates new receipt (immutable audit trail)
- [ ] Toast shows "Bud updated"

---

### 1.3 Delete Memory (2 hours)

**Build**: Delete individual buds with confirmation.

**Requirements**:
- Confirmation dialog before delete
- Remove receipt from database
- Remove blobs (images) if not referenced elsewhere
- Update jar bud count
- Toast confirmation

**Files to Modify**:
- `Features/Memory/MemoryDetailView.swift` - Add delete button
- `Core/Database/Repositories/MemoryRepository.swift` - Add delete method

**Acceptance Criteria**:
- [ ] Swipe-to-delete on MemoryListCard
- [ ] "Delete" button in MemoryDetailView toolbar
- [ ] Confirmation alert: "Delete [Strain Name]? This cannot be undone."
- [ ] Removes from DB + cleans up blobs
- [ ] Toast: "Bud deleted"
- [ ] Returns to jar list

---

## Module 2: Jar System Polish

**Current State**:
- ✅ Can create/delete jars
- ✅ Can view jar list & detail
- ✅ Can add/remove members
- ❌ No edit jar name/color
- ❌ Delete confirmation too subtle
- ❌ No "Move bud to different jar"

### 2.1 Edit Jar (1-2 hours)

**Build**: Edit jar name and color.

**Requirements**:
- Reuse CreateJarView in edit mode
- Update jar metadata
- Refresh Shelf after edit

**Files to Modify**:
- `Features/Jar/CreateJarView.swift` - Add edit mode
- `Features/Shelf/ShelfView.swift` - Add edit navigation

**Acceptance Criteria**:
- [ ] Long-press jar card → "Edit Jar" option
- [ ] Can change name & color
- [ ] Save updates immediately
- [ ] Toast: "Jar updated"

---

### 2.2 Jar Delete Confirmation (30 min)

**Build**: More prominent delete warning.

**Requirements**:
- Clear alert dialog
- Show bud count in warning
- Red destructive button

**Files to Modify**:
- `Features/Shelf/ShelfView.swift` - Update alert

**Acceptance Criteria**:
- [ ] Alert shows: "Delete '[Jar Name]'? This jar has X buds. They will move to Solo."
- [ ] Destructive button styled red
- [ ] Works as expected

---

### 2.3 Move Bud Between Jars (2-3 hours)

**Build**: Move a bud from one jar to another.

**Requirements**:
- "Move to..." option in MemoryDetailView
- Picker sheet with jar list
- Update jar_id in local_receipts
- Refresh both source & destination jars

**Files to Create**:
- `Features/Memory/MoveMemoryView.swift`

**Files to Modify**:
- `Features/Memory/MemoryDetailView.swift` - Add "Move" button
- `Core/Database/Repositories/MemoryRepository.swift` - Add move method

**Acceptance Criteria**:
- [ ] "Move" button in MemoryDetailView toolbar
- [ ] Sheet shows all jars except current
- [ ] Tap jar → moves bud
- [ ] Toast: "Moved to [Jar Name]"
- [ ] Returns to new jar's detail view

---

## Module 3: User Guidance

**Current State**:
- ❌ No onboarding (fresh install is confusing)
- ❌ No help text anywhere
- ❌ No settings screen
- ❌ No "About" info

### 3.1 Simple Onboarding (2-3 hours)

**Build**: 2-3 screen intro explaining the app.

**Requirements**:
- Show on first launch only
- Explain: What is a jar? What is a bud? Why E2EE?
- Skip button on all screens
- Store "onboarding_completed" flag

**Files to Create**:
- `Features/Onboarding/OnboardingView.swift`
- `Features/Onboarding/OnboardingStep.swift`

**Files to Modify**:
- `ContentView.swift` - Check onboarding flag

**Screens**:
1. "Welcome to Buds" - Track your cannabis journey
2. "Organize with Jars" - Solo vs shared jars
3. "Your Data is Private" - E2EE explanation

**Acceptance Criteria**:
- [ ] Shows on first launch
- [ ] Never shows again after completion
- [ ] Skip button works
- [ ] Clean, minimal design

---

### 3.2 Settings Screen (2-3 hours)

**Build**: Basic app settings.

**Requirements**:
- Account info (phone number, device ID)
- Privacy policy link
- Terms of service link
- App version
- "Clear local data" (dev tool)
- "Log out" button

**Files to Create**:
- `Features/Settings/SettingsView.swift`

**Files to Modify**:
- `ContentView.swift` - Add settings tab/button

**Acceptance Criteria**:
- [ ] Accessible from main navigation
- [ ] Shows phone number (read-only)
- [ ] "Clear local data" with confirmation
- [ ] "Log out" returns to auth screen
- [ ] Version number displayed

---

### 3.3 Empty State Improvements (1 hour)

**Build**: Better empty states throughout app.

**Requirements**:
- Empty jars list (Shelf)
- Empty members list (JarDetailView)
- Empty buds list (JarDetailView) - already done!
- Consistent design

**Files to Modify**:
- `Features/Shelf/ShelfView.swift` - Better empty state
- Various other views

**Acceptance Criteria**:
- [ ] All empty states have icon + text + CTA
- [ ] Consistent visual style
- [ ] Clear guidance on what to do

---

## Module 4: Error Handling & Feedback

**Current State**:
- ❌ Errors only print to console
- ❌ No user-facing error messages
- ❌ Loading states incomplete
- ❌ No confirmation toasts for most actions

### 4.1 Error Toast System (2 hours)

**Build**: Show errors to users, not just console.

**Requirements**:
- Red error toasts (vs green success)
- Common error messages (DB failure, no network, etc.)
- Auto-dismiss after 5 seconds
- Dismiss on tap

**Files to Modify**:
- `Shared/Toast.swift` - Add error variant
- All repositories - Show error toasts

**Acceptance Criteria**:
- [ ] DB errors show toast: "Something went wrong. Please try again."
- [ ] Network errors (future) show: "No connection. Changes saved locally."
- [ ] Red background for errors
- [ ] User can tap to dismiss

---

### 4.2 Loading States Audit (1-2 hours)

**Build**: Ensure all data loads show spinners.

**Requirements**:
- Shelf loading jars
- JarDetailView loading buds
- MemoryDetailView loading images
- Consistent spinner design

**Files to Modify**:
- Various views

**Acceptance Criteria**:
- [ ] No blank screens during load
- [ ] Spinner uses .budsPrimary color
- [ ] Text: "Loading..." where appropriate

---

### 4.3 Confirmation Dialogs (1 hour)

**Build**: Confirm destructive actions.

**Requirements**:
- Delete jar (already exists, improve)
- Delete bud (new)
- Remove member (new)
- Clear local data (new)

**Files to Modify**:
- Various views

**Acceptance Criteria**:
- [ ] All destructive actions ask for confirmation
- [ ] Red destructive buttons
- [ ] Clear warning text

---

## Module 5: Performance & Testing

**Current State**:
- ✅ Memory <40MB (downsampled thumbnails)
- ❌ No stress testing with 100+ buds
- ❌ No fresh install testing
- ❌ No device compatibility testing

### 5.1 Stress Testing (1-2 hours)

**Test**: App with 100+ buds across multiple jars.

**Requirements**:
- Create test script to generate buds
- Test scrolling performance
- Test memory usage
- Test search (when built)

**Acceptance Criteria**:
- [ ] 100 buds: Memory <60MB
- [ ] Smooth 60fps scrolling
- [ ] No crashes
- [ ] DB queries <100ms

---

### 5.2 Fresh Install Testing (1 hour)

**Test**: Delete app, reinstall, go through onboarding.

**Requirements**:
- Test on physical device
- Document any confusing UX
- Fix critical issues

**Acceptance Criteria**:
- [ ] Onboarding shows correctly
- [ ] Can create first jar
- [ ] Can create first bud
- [ ] Solo jar exists by default

---

### 5.3 Multi-Device Testing (2 hours)

**Test**: Install on 2-3 different devices.

**Requirements**:
- iPhone SE (small screen)
- iPhone Pro Max (large screen)
- Different iOS versions if possible

**Acceptance Criteria**:
- [ ] UI works on small screens
- [ ] UI works on large screens
- [ ] No layout bugs
- [ ] Performance acceptable

---

## Module 6: TestFlight Prep

### 6.1 Version & Changelog (30 min)

**Requirements**:
- Bump version to 1.0.0 (build 1)
- Create CHANGELOG.md
- Add "What's New" for TestFlight

**Acceptance Criteria**:
- [ ] Version updated in Xcode
- [ ] CHANGELOG created
- [ ] "What to Test" notes for testers

---

### 6.2 Archive & Upload (1 hour)

**Requirements**:
- Archive build
- Upload to TestFlight
- Add external tester notes
- Invite first testers

**Acceptance Criteria**:
- [ ] Build uploaded successfully
- [ ] Beta info complete
- [ ] First 5-10 testers invited
- [ ] Feedback channel set up (Discord/Slack)

---

## Priority Order (Recommended)

**Week 1 (10-12 hours)**: Core Functionality
1. Memory Detail View (4-5h)
2. Edit Memory (3-4h)
3. Delete Memory (2h)
4. Error Toasts (2h)

**Week 2 (8-10 hours)**: Polish & Guidance
5. Onboarding (2-3h)
6. Settings (2-3h)
7. Move Bud Between Jars (2-3h)
8. Edit Jar (1-2h)
9. Loading States Audit (1-2h)

**Week 3 (3-4 hours)**: Testing & Ship
10. Stress Testing (1-2h)
11. Fresh Install Test (1h)
12. TestFlight Upload (1h)

---

## Success Metrics for Beta

**Minimum Viable Beta**:
- [ ] Users can create, view, edit, delete buds
- [ ] Users can manage jars
- [ ] Onboarding explains the app
- [ ] Errors show helpful messages
- [ ] No crashes on common flows
- [ ] Memory <60MB with 20 buds

**Nice to Have**:
- [ ] Search/filter buds
- [ ] Export data (CSV/JSON)
- [ ] Dark/light mode toggle
- [ ] Animations on transitions

---

## Out of Scope (Phases 11-14)

**Not in this phase**:
- Map view
- Shop integration
- AI recommendations
- Social features
- Analytics
- Push notifications

These come AFTER beta feedback from 20-50 users.

---

## Notes

- **Parallel development**: Developer builds map/shop/AI while this gets polished
- **User feedback**: After TestFlight ships, gather feedback before more features
- **Iterative**: Ship beta → test with users → fix critical issues → ship again
- **No scope creep**: Stick to making existing features work well

**Remember**: The goal is not perfection. The goal is 20-50 people can use the app without frustration.
