# Fresh Install Testing Checklist

**Phase**: 10.1 Module 5.2
**Date**: December 29, 2025
**Purpose**: Verify first-time user experience on clean install

---

## Pre-Test Setup

- [ ] Delete app from device completely
- [ ] Reinstall from Xcode or TestFlight
- [ ] Ensure device has internet connection
- [ ] Have test phone number ready for auth

---

## Test 1: First Launch & Onboarding

### Steps:
1. Launch app for first time
2. Observe onboarding flow

### Expected Behavior:
- [ ] Onboarding shows automatically (no blank screen)
- [ ] Screen 1: "Welcome to Buds" - Clear messaging
- [ ] Screen 2: "Organize with Jars" - Explains Solo vs Shared
- [ ] Screen 3: "Your Data is Private" - E2EE explanation
- [ ] Skip button works on all screens
- [ ] "Get Started" button completes onboarding

### Pass Criteria:
- ✅ All 3 screens display correctly
- ✅ Text is readable, not cut off
- ✅ Skip and Get Started buttons both work
- ✅ Transitions smooth

### Issues Found:
_Record any issues here_

---

## Test 2: Authentication

### Steps:
1. After onboarding, enter phone number
2. Receive verification code
3. Enter code and verify

### Expected Behavior:
- [ ] Phone number input field visible
- [ ] Country code selector works (default: +1)
- [ ] "Send Code" button enabled when number valid
- [ ] Verification code sent successfully
- [ ] Code input field shows
- [ ] Verification succeeds

### Pass Criteria:
- ✅ Auth flow completes without errors
- ✅ Loading states show during network calls
- ✅ Error handling if network fails

### Issues Found:
_Record any issues here_

---

## Test 3: Default Solo Jar

### Steps:
1. After auth, navigate to Shelf
2. Check for Solo jar

### Expected Behavior:
- [ ] Shelf view loads
- [ ] Solo jar exists by default
- [ ] Solo jar shows "0 buds" initially
- [ ] Can tap into Solo jar

### Pass Criteria:
- ✅ Solo jar created automatically
- ✅ No errors or blank screens
- ✅ Jar detail view accessible

### Issues Found:
_Record any issues here_

---

## Test 4: Create First Jar

### Steps:
1. Tap "+" button in Shelf toolbar
2. Enter jar name and description
3. Save jar

### Expected Behavior:
- [ ] Create jar form shows
- [ ] Name field focused automatically
- [ ] Can type jar name
- [ ] Save button enabled when name entered
- [ ] Jar saves successfully
- [ ] Returns to Shelf with new jar visible

### Pass Criteria:
- ✅ Jar creation works first time
- ✅ New jar appears in grid
- ✅ Toast shows "Jar created"

### Issues Found:
_Record any issues here_

---

## Test 5: Create First Bud

### Steps:
1. Tap FAB (floating action button) at bottom right
2. Select jar from picker (or already in jar)
3. Enter strain name
4. Select product type
5. Save

### Expected Behavior:
- [ ] Jar picker shows if tapped from Shelf
- [ ] Create form shows with minimal fields
- [ ] Strain name field focused
- [ ] Product type picker works
- [ ] Save button enabled when name entered
- [ ] Bud saves successfully
- [ ] Enrich view shows (optional step)
- [ ] Can skip enrich or add details

### Pass Criteria:
- ✅ First bud created in <15 seconds
- ✅ Bud appears in jar detail view
- ✅ Create → Enrich flow works

### Issues Found:
_Record any issues here_

---

## Test 6: View First Bud

### Steps:
1. Navigate to jar with bud
2. Tap on bud card

### Expected Behavior:
- [ ] Bud detail view opens
- [ ] Strain name displays
- [ ] Product type and rating show
- [ ] Edit button visible
- [ ] Delete button visible
- [ ] Close button works

### Pass Criteria:
- ✅ Detail view loads correctly
- ✅ All data displays properly
- ✅ Can navigate back

### Issues Found:
_Record any issues here_

---

## Test 7: Edit/Enrich First Bud

### Steps:
1. From detail view, tap Edit
2. Add rating (tap stars)
3. Select 2-3 effects
4. Add notes
5. Save changes

### Expected Behavior:
- [ ] Edit form pre-fills existing data
- [ ] Rating selector works
- [ ] Effects checkboxes toggle
- [ ] Notes text field works
- [ ] Save button enabled
- [ ] Changes save successfully
- [ ] Toast shows "Bud updated"

### Pass Criteria:
- ✅ Enrichment works smoothly
- ✅ All fields functional
- ✅ Changes persist after save

### Issues Found:
_Record any issues here_

---

## Test 8: Empty States

### Steps:
1. Navigate to empty jar
2. Navigate to empty members list

### Expected Behavior:
- [ ] Empty jar shows icon + "No buds yet" message
- [ ] "Add Your First Bud" button visible
- [ ] Empty members shows icon + "No Members Yet" message
- [ ] "Add Member" button visible

### Pass Criteria:
- ✅ No blank screens
- ✅ Clear CTAs provided
- ✅ Helpful messaging

### Issues Found:
_Record any issues here_

---

## Test 9: Settings/Profile

### Steps:
1. Navigate to Profile tab
2. Check account info
3. Tap Privacy Policy link
4. Tap Terms of Service link

### Expected Behavior:
- [ ] Profile view loads
- [ ] Phone number displays
- [ ] Device ID shows (truncated)
- [ ] Privacy Policy opens in browser
- [ ] Terms of Service opens in browser
- [ ] Version number displays

### Pass Criteria:
- ✅ All info accurate
- ✅ Links work
- ✅ No crashes

### Issues Found:
_Record any issues here_

---

## Test 10: Sign Out & Re-Auth

### Steps:
1. Tap Sign Out button
2. Confirm sign out
3. Re-authenticate with same number
4. Check data persists

### Expected Behavior:
- [ ] Sign out confirmation shows
- [ ] Signs out successfully
- [ ] Returns to auth screen
- [ ] Can re-authenticate
- [ ] All data still there (jars, buds)

### Pass Criteria:
- ✅ Sign out works
- ✅ Re-auth works
- ✅ Data persists locally

### Issues Found:
_Record any issues here_

---

## Overall Assessment

### Performance:
- [ ] App launches quickly (<3 seconds)
- [ ] No lag or stuttering
- [ ] Scrolling smooth
- [ ] Transitions smooth

### Memory:
- [ ] Check Xcode memory graph
- [ ] Verify <40MB with 5-10 buds

### Crashes:
- [ ] No crashes during entire test
- [ ] No freezes or unresponsive UI

### UX Confusion Points:
_Record anything confusing for first-time users_

### Critical Bugs:
_Record any blocking issues_

### Nice-to-Fix Issues:
_Record minor issues_

---

## Pass/Fail

**Overall Result**: [ ] PASS / [ ] FAIL

**Tester**: _______________
**Date**: _______________
**Device**: _______________
**iOS Version**: _______________

**Notes**:
