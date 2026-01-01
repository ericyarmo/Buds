# TestFlight Beta Notes - Buds v1.0.0

## What to Test

Welcome to the Buds beta! This is our first TestFlight release. Your feedback is crucial.

### First Time Setup (5 min)

1. **Onboarding** - You'll see 3 intro screens
   - Do the screens explain the app clearly?
   - Is anything confusing?
   - Try the "Skip" button

2. **Sign In** - Google Sign-In for phone authentication
   - Does sign-in work smoothly?
   - Any errors?

### Core Flows to Test (15-20 min)

#### Creating Your First Memory ("Bud")

1. Tap the **"+" button** in bottom-right
2. Enter a strain name (e.g., "Gelato", "Blue Dream")
3. Select product type (flower, edible, etc.)
4. Add photos (optional, up to 5)
5. Tap "Create Memory"

**Test**:
- Does the simplified flow feel intuitive?
- Any crashes or errors?
- Do images upload correctly?

#### Enriching a Memory

1. Tap on a memory card to open details
2. Tap **"Edit"** button (top-right)
3. Add more info:
   - Star rating
   - Effects (relaxed, creative, etc.)
   - Flavors
   - Notes
   - Consumption method
   - Brand, THC%, etc.

**Test**:
- Is it clear how to add details?
- Do effects/flavors save correctly?
- Any UI bugs in edit view?

#### Organizing with Jars

1. Go to **"Shelf"** tab (bottom nav)
2. Tap **"+ New Jar"**
3. Name it (e.g., "Favorites", "Sativa Strains")
4. Pick a color
5. Tap **"Create"**

**Test**:
- Can you create multiple jars?
- Try moving a memory to a different jar (open memory → "Move" button)
- Try editing a jar name/color
- Try deleting a jar (memories move to Solo)

#### Reactions

1. Open a memory detail view
2. Scroll to reaction buttons at bottom
3. Tap a reaction (❤️, 🔥, 😂, 🤯, 😌)
4. Tap again to remove it

**Test**:
- Do reactions toggle on/off?
- Does the count update correctly?
- Any layout issues?

### What We're Looking For

#### Critical Issues (Report ASAP!)
- App crashes
- Data loss (memories disappearing)
- Sign-in failures
- Can't create memories
- Can't take/upload photos

#### UI/UX Feedback
- Confusing flows or labels
- Layout bugs (text cut off, overlapping elements)
- Dark mode issues
- Performance problems (slow, laggy)

#### Feature Requests
- What's missing that you expected?
- What would make this more useful?

### Known Issues

- **Single device only** - Data doesn't sync between devices yet
- **No sharing yet** - Shared jars exist but you can't invite people
- **No backup** - Data lives on your device only
- **Some spacing issues** - Minor UI polish ongoing

### How to Report Feedback

**Via TestFlight**:
1. Shake your device → "Send Feedback"
2. Include screenshots if possible
3. Describe what you were doing when issue occurred

**Via Discord/Slack** (if invited):
- Tag @eric with bugs or questions

### What's Coming Next

After we fix critical bugs from your feedback:
- Multi-device sync
- Share jars with friends (E2EE)
- Cloud backup
- Export data
- Map view
- Shop integration

---

**Thank you for testing!** 🙏

Your feedback will directly shape the app. Don't hold back - we want to know everything that feels broken, confusing, or awesome.

---

## Testing Checklist (Optional)

Feel free to go through this systematically:

- [ ] Complete onboarding (or skip it)
- [ ] Sign in with Google
- [ ] Create first memory (simplified flow)
- [ ] View memory detail screen
- [ ] Edit memory to add rating + effects
- [ ] Add images to a memory
- [ ] React to a memory (try all 5 reactions)
- [ ] Create a new jar
- [ ] Move a memory to different jar
- [ ] Edit jar name/color
- [ ] Delete a jar
- [ ] Delete a memory
- [ ] Sign out and sign back in
- [ ] Test on small iPhone (SE) and large (Pro Max) if possible
- [ ] Test in dark mode (Settings → Display → Dark)

If you complete 50%+ of this checklist, you're an MVP beta tester! 🏆
