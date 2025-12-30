# Multi-Device Testing Checklist

**Phase**: 10.1 Module 5.3
**Date**: December 29, 2025
**Purpose**: Verify app works across different devices and screen sizes

---

## Device Matrix

Test on at least 3 devices covering small, medium, and large screens:

### Required Devices:
- [ ] **Small**: iPhone SE (2nd/3rd gen) or iPhone 13 mini - 4.7" / 5.4"
- [ ] **Medium**: iPhone 14/15 - 6.1"
- [ ] **Large**: iPhone 14/15 Pro Max - 6.7"

### Bonus Devices (if available):
- [ ] iPad (different aspect ratio)
- [ ] Older iOS version (iOS 16+)

---

## Test 1: Layout - Small Screen (iPhone SE)

**Device**: iPhone SE / 13 mini
**Screen**: 4.7" - 5.4"

### Areas to Check:
- [ ] **Onboarding**: Text readable, not cut off
- [ ] **Auth**: Phone input field visible
- [ ] **Shelf Grid**: 2 columns fit properly
- [ ] **Jar Cards**: Not truncated
- [ ] **Create Form**: Fields fit without scrolling
- [ ] **Detail View**: Content not cramped
- [ ] **Edit Form**: All fields accessible
- [ ] **Profile**: Sections fit properly
- [ ] **Buttons**: Large enough to tap (44pt min)
- [ ] **Navigation**: Tab bar not cramped

### Pass Criteria:
- ✅ All content readable
- ✅ No horizontal scrolling
- ✅ Buttons tappable
- ✅ Forms usable

### Issues Found:
_Record layout issues on small screen_

---

## Test 2: Layout - Large Screen (Pro Max)

**Device**: iPhone 14/15 Pro Max
**Screen**: 6.7"

### Areas to Check:
- [ ] **Onboarding**: Content not too spread out
- [ ] **Shelf Grid**: Utilizes space well
- [ ] **Jar Cards**: Proper size
- [ ] **Detail View**: Content well-spaced
- [ ] **Edit Form**: Not too much whitespace
- [ ] **Profile**: Sections proportional
- [ ] **Empty States**: Icons appropriately sized
- [ ] **Toasts**: Positioned well

### Pass Criteria:
- ✅ Good use of space
- ✅ Not too spread out
- ✅ Consistent padding

### Issues Found:
_Record layout issues on large screen_

---

## Test 3: Tap Targets

Test across all devices:

### Elements to Test:
- [ ] **FAB Button**: Easy to reach with thumb
- [ ] **Tab Bar Icons**: Large enough
- [ ] **List Items**: Entire card tappable
- [ ] **Toolbar Buttons**: Not too small
- [ ] **Checkboxes** (effects): Easy to toggle
- [ ] **Star Rating**: Easy to tap individual stars
- [ ] **Context Menu**: Long-press works
- [ ] **Swipe Gestures**: If implemented

### Pass Criteria:
- ✅ All elements min 44pt tap target
- ✅ No accidental taps
- ✅ Comfortable one-handed use

### Issues Found:
_Record tap target issues_

---

## Test 4: Text Readability

Test across all devices:

### Text Sizes to Check:
- [ ] **Titles**: .budsTitle - Clear and readable
- [ ] **Body**: .budsBody - Comfortable reading
- [ ] **Captions**: .budsCaption - Not too small
- [ ] **Button Labels**: Easy to read
- [ ] **Form Labels**: Clear
- [ ] **Empty State Text**: Readable from distance

### Pass Criteria:
- ✅ All text readable without squinting
- ✅ Hierarchy clear
- ✅ Contrast sufficient

### Issues Found:
_Record text readability issues_

---

## Test 5: Navigation

Test navigation flow on each device:

### Flows to Test:
- [ ] **Shelf → Jar Detail**: Smooth transition
- [ ] **Jar Detail → Bud Detail**: Opens correctly
- [ ] **Detail → Edit**: Pre-fills data
- [ ] **Create Flow**: Jar picker → Create → Enrich
- [ ] **Tab Switching**: Fast, no lag
- [ ] **Back Navigation**: Works consistently
- [ ] **Modal Sheets**: Dismiss gestures work

### Pass Criteria:
- ✅ Transitions smooth
- ✅ No navigation bugs
- ✅ Back button always works

### Issues Found:
_Record navigation issues_

---

## Test 6: Performance

Test performance on each device:

### Metrics:
- [ ] **App Launch**: <3 seconds
- [ ] **Shelf Load**: <1 second
- [ ] **Jar Detail Load**: <1 second
- [ ] **Scrolling**: Smooth 60fps
- [ ] **Image Loading**: Progressive, not blocking
- [ ] **Form Input**: No lag when typing
- [ ] **Transitions**: Smooth animations

### Pass Criteria (iPhone SE - slowest):
- ✅ Launch <3s
- ✅ List loads <1s
- ✅ Scrolling smooth
- ✅ No stuttering

### Issues Found:
_Record performance issues_

---

## Test 7: Memory Usage

Use Xcode Instruments on each device:

### Test Scenario:
1. Generate 50 test buds
2. Navigate through app
3. Monitor memory in Instruments

### Targets:
- [ ] **iPhone SE**: <50MB with 50 buds
- [ ] **iPhone 15**: <60MB with 50 buds
- [ ] **Pro Max**: <60MB with 50 buds

### Pass Criteria:
- ✅ No memory leaks
- ✅ Memory stable
- ✅ Within targets

### Measurements:
- iPhone SE: _____ MB
- iPhone 15: _____ MB
- Pro Max: _____ MB

### Issues Found:
_Record memory issues_

---

## Test 8: iOS Version Compatibility

If testing on different iOS versions:

### Features to Verify:
- [ ] **SwiftUI Components**: Render correctly
- [ ] **Navigation Stack**: Works on iOS 16+
- [ ] **PhotosPicker**: Works correctly
- [ ] **Sheets**: Dismiss properly
- [ ] **Alerts**: Display correctly
- [ ] **Toast**: Animations smooth

### Pass Criteria:
- ✅ No version-specific bugs
- ✅ Consistent behavior

### Issues Found:
_Record iOS version issues_

---

## Test 9: Orientation (if iPad)

iPad only:

### Areas to Test:
- [ ] **Landscape**: Layout adapts
- [ ] **Portrait**: Works correctly
- [ ] **Split View**: If supported
- [ ] **Keyboard**: Doesn't block content

### Pass Criteria:
- ✅ Both orientations work
- ✅ Content reflows properly

### Issues Found:
_Record orientation issues_

---

## Test 10: Edge Cases

Test unusual scenarios:

### Scenarios:
- [ ] **Long Strain Names**: "Super Ultra Mega Long Strain Name That Goes On Forever"
- [ ] **Many Effects**: Select all 12 effects
- [ ] **Long Notes**: 500+ character note
- [ ] **Many Jars**: Create 20+ jars
- [ ] **Full Members**: 12 members in jar
- [ ] **Special Characters**: Emojis in names (🌿 Blue Dream 🔥)

### Pass Criteria:
- ✅ No UI breaks
- ✅ Text truncates gracefully
- ✅ Limits enforced

### Issues Found:
_Record edge case issues_

---

## Device-Specific Issues

### iPhone SE:
_Issues specific to small screen_

### iPhone 15:
_Issues specific to medium screen_

### Pro Max:
_Issues specific to large screen_

### iPad (if tested):
_Issues specific to iPad_

---

## Critical Issues Found

**P0 (Blocking)**:
_Issues that prevent app use_

**P1 (High)**:
_Major UX problems_

**P2 (Medium)**:
_Minor issues_

**P3 (Low)**:
_Polish/nice-to-have_

---

## Overall Assessment

### Layouts:
- [ ] All devices: PASS / FAIL

### Performance:
- [ ] All devices: PASS / FAIL

### Memory:
- [ ] All devices: PASS / FAIL

### Usability:
- [ ] All devices: PASS / FAIL

---

## Pass/Fail

**Overall Result**: [ ] PASS / [ ] FAIL

**Tester**: _______________
**Date**: _______________
**Devices Tested**: _______________

**Notes**:
