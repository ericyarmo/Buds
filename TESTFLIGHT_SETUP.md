# TestFlight Setup Guide

Quick guide to get Buds on TestFlight and share with your cofounder.

## Prerequisites

- **Apple Developer Account** ($99/year)
- **App Store Connect** access
- **Bundle ID** registered

## Step 1: Configure App in Xcode

1. Open `Buds.xcodeproj` in Xcode
2. Select **Buds** target → **Signing & Capabilities**
3. Set **Team** to your Apple Developer team
4. Ensure **Bundle Identifier** matches: `com.yourteam.buds` (or your chosen ID)
5. Set **Version** to `1.0` and **Build** to `1`

## Step 2: Archive the App

1. In Xcode menu: **Product → Destination → Any iOS Device** (not simulator)
2. **Product → Archive**
3. Wait for archive to complete (2-5 minutes)
4. Xcode **Organizer** window will open automatically

## Step 3: Upload to App Store Connect

1. In Organizer, select your archive
2. Click **Distribute App**
3. Choose **App Store Connect**
4. Click **Upload**
5. Leave defaults checked:
   - ✅ Include bitcode
   - ✅ Upload your app's symbols
   - ✅ Manage Version and Build Number
6. Click **Next** → **Upload**
7. Wait for upload (5-10 minutes)

## Step 4: Set Up TestFlight in App Store Connect

1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Navigate to **My Apps** → **Buds** (or create new app if first time)
3. Go to **TestFlight** tab
4. Wait for build to process (10-30 minutes) - you'll get an email
5. Once processed, the build appears under **iOS Builds**

## Step 5: Add Your Cofounder as Tester

### Option A: Internal Testing (Fastest - No Review)

1. In TestFlight tab, click **Internal Testing** (left sidebar)
2. Click **+** next to "Testers"
3. Add your cofounder's Apple ID email
4. They'll receive an email invite
5. They download **TestFlight app** from App Store
6. Open invite email → Install Buds

**Limits:** Up to 100 internal testers, no app review needed

### Option B: External Testing (More testers, requires review)

1. In TestFlight tab, click **External Testing**
2. Create a test group
3. Add testers by email
4. Submit for TestFlight review (1-2 days)
5. Once approved, testers receive invite

**Limits:** Up to 10,000 external testers

## Step 6: Share with Cofounder

**Internal Testing** (recommended for now):
1. Send cofounder invite from App Store Connect
2. They install TestFlight app
3. They accept invite and install Buds
4. Done!

## Quick Troubleshooting

**Archive button grayed out?**
- Make sure destination is "Any iOS Device" not a simulator

**Upload failed - missing entitlements?**
- Check Signing & Capabilities tab in Xcode
- Ensure automatic signing is enabled

**Build stuck in "Processing"?**
- Normal! Can take up to 30 minutes
- Check email for processing complete notification

**Cofounder can't install?**
- Verify they have TestFlight app installed
- Check their email matches the one invited
- Try removing and re-adding them

## Next Steps After TestFlight

Once you're both testing:

1. **Iterate based on feedback**
2. **Upload new builds** (increment build number each time)
3. **When ready for App Store**: Switch from TestFlight to full App Store submission

## Build Update Workflow (For Future Updates)

1. Make changes in Xcode
2. Increment **Build number** (General tab): `1` → `2` → `3`, etc.
3. **Product → Archive**
4. **Distribute → App Store Connect**
5. New build appears in TestFlight automatically
6. Testers get notified of update

## Camera & Photos Permissions

**IMPORTANT**: Before submitting, add these to `Info.plist`:

Already done in this build:
- ✅ `NSCameraUsageDescription`: "Take photos of your cannabis products"
- ✅ `NSPhotoLibraryUsageDescription`: "Select photos from your library"

## Notes

- **First build** takes longest (30-60 min processing)
- **Subsequent builds** process faster (10-20 min)
- **Internal testers** can install immediately after processing
- **TestFlight builds expire after 90 days** - just upload a new one

## Questions?

- [TestFlight Overview](https://developer.apple.com/testflight/)
- [App Store Connect Guide](https://help.apple.com/app-store-connect/)

---

**Status:** Ready to archive and upload! 🚀
