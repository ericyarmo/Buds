# App Store Connect Setup - Exact Steps

## Step 1: Create App in App Store Connect

1. **Go to:** https://appstoreconnect.apple.com
2. **Sign in** with your Apple Developer account
3. Click **"My Apps"** (or "Apps" in left sidebar)
4. Click **"+" button** (top-left corner)
5. Select **"New App"**

## Step 2: Fill Out New App Form

**Platform:** iOS

**Name:** Buds
- This is the public app name users see
- Must be unique in the App Store
- Can change later

**Primary Language:** English (U.S.)

**Bundle ID:** Select from dropdown
- Should see the bundle ID you configured in Xcode
- Likely something like: `com.yourteam.Buds`
- **Can't change this later!**

**SKU:** `buds-ios-001`
- Internal identifier (users never see this)
- Can be anything unique to you
- Letters, numbers, hyphens, dots only

**User Access:** Full Access
- Leave as default

Click **"Create"**

## Step 3: Required App Information

After creating, you'll see the app dashboard. Fill these sections:

### A. App Information (Left sidebar → App Information)

**Subtitle** (optional): "Track your cannabis journey"
- Max 30 characters
- Appears under app name

**Category:**
- **Primary:** Health & Fitness (or Lifestyle)
- **Secondary:** (optional) Social Networking

**Content Rights:**
- ☑️ Contains third-party content (if using any stock photos)
- Or leave unchecked if all original

**Age Rating:**
Click "Edit" → Answer questionnaire:
- Likely 17+ due to cannabis content
- App Store will determine rating based on answers

### B. Pricing and Availability

**Price:** Free
**Availability:** All countries (or select specific)

### C. App Privacy

Click "Get Started" and answer:
- **Do you collect data?** Yes (if using Firebase Auth/Analytics)
- Add data types you collect:
  - User IDs
  - Usage Data
  - etc.
- Can fill this out later before submission

## Step 4: Version Information

Click **"1.0 Prepare for Submission"** (left sidebar under iOS App)

Fill out:

**Screenshots** (REQUIRED before submission):
- iPhone 6.7" display (required): 1290 x 2796 pixels
- Can use Xcode simulator screenshots
- Need at least 3 screenshots
- **For TestFlight:** Can upload later, NOT required for internal testing

**Promotional Text** (optional):
"Track, remember, and share your cannabis experiences with friends."

**Description** (REQUIRED):
```
Buds helps you remember and share your cannabis journey with your circle.

Features:
• Track strain details, effects, and ratings
• Add photos to your memories (up to 3 per session)
• Share experiences with your trusted circle
• Browse your timeline of past sessions
• Private by default, share when you want

Built for the modern cannabis enthusiast who wants to remember what works.
```

**Keywords** (optional):
cannabis,weed,marijuana,tracker,journal,dispensary

**Support URL:** https://yourwebsite.com (can be GitHub repo for now)

**Marketing URL** (optional): Leave blank

**Version:** 1.0

**Copyright:** 2025 Your Name / Company

**Contact Information:**
- First Name, Last Name, Email, Phone

## Step 5: Build Information

**Build:** (This will appear AFTER you upload from Xcode)
- Wait for your archive upload to process
- Then select it from the dropdown

**App Review Information:**
- **Sign-in required?** No (or Yes if you add auth)
- **Demo account:** (if needed for reviewers)

**Notes for Review:**
```
This is a personal journal app for tracking cannabis consumption.
All data is stored locally on device. App follows all App Store guidelines.
```

## Step 6: Skip For Now (Not Needed for TestFlight)

These are only for full App Store submission:
- ❌ Screenshots (can add later)
- ❌ App Privacy details (can complete later)
- ❌ Age rating questionnaire (can do later)

## Step 7: TestFlight Internal Testing

1. Click **"TestFlight"** tab (top of page)
2. Wait for your build to appear (after Xcode upload)
3. Build will show "Processing" for 10-30 minutes
4. Once processed, it appears under "iOS Builds"
5. Click **"Internal Testing"** (left sidebar)
6. Click **"+" next to App Store Connect Users**
7. Add your cofounder's email (must be added as user in Users & Access first)

### Adding Users First:

1. Click your **name (top-right)** → "Users and Access"
2. Click **"+" button**
3. Add cofounder:
   - Email address
   - Role: **Admin** or **Developer** (for internal testing access)
   - Send invite
4. They accept email invite
5. Now they'll appear in TestFlight internal testers list

## What You DON'T Need for TestFlight

- ✅ App Store screenshots
- ✅ Full privacy policy
- ✅ Marketing materials
- ✅ App Store review

## What You DO Need for TestFlight

- ✅ App created in App Store Connect (above steps)
- ✅ Bundle ID matches Xcode
- ✅ Build uploaded from Xcode (next step after this)
- ✅ Basic app info filled out
- ✅ Internal tester added

---

## Quick Checklist

Before uploading from Xcode, make sure you completed:

- [ ] Created app in App Store Connect
- [ ] Chose bundle ID (matches Xcode)
- [ ] Added app name: "Buds"
- [ ] Set category (Health & Fitness or Lifestyle)
- [ ] Added your cofounder as App Store Connect user
- [ ] Have TestFlight tab open and ready

**Next step:** Archive in Xcode → Upload to App Store Connect

The build will appear in TestFlight after processing (10-30 min).
