# Next Phase Plan - Post v0.1 Foundation

## ✅ Current Status (v0.1)
- Core receipt signing (CBOR + Ed25519) - **0.11ms p50**
- Database (GRDB with 7 tables)
- Timeline + Create Memory UI
- Star rating + effects selection **FIXED**
- Timeline auto-refresh **FIXED**

## 🐛 Known Issues to Address
1. ~~Star rating only selects 5~~ → **FIXED** (added `.buttonStyle(.plain)`)
2. ~~Effects selecting all~~ → **FIXED** (added `.buttonStyle(.plain)`)
3. ~~Timeline not refreshing after save~~ → **FIXED** (added `.onDismiss`)
4. **Emojis** → Replace with custom iconography (design phase)
5. **Product type/method** → Better specification needed

---

## 🎯 Priority Features (In Order)

### **Phase 3: Images + Memory Enhancement** (3-4 days)
**Goal:** Full-featured memory creation with photos

#### Tasks:
1. **Photo Capture/Selection**
   - [ ] Add PhotosPicker to CreateMemoryView
   - [ ] Camera capture option (using UIImagePickerController)
   - [ ] Image compression (max 2MB per photo)
   - [ ] Store in `blobs` table with CID
   - [ ] Link to memory via `local_receipts.image_cid`

2. **Image Display**
   - [ ] Show full-size image in MemoryCard
   - [ ] Tap to view full screen
   - [ ] Delete image option

3. **Memory Detail View**
   - [ ] Full-screen memory view (tap on card)
   - [ ] All fields displayed
   - [ ] Edit/Delete buttons
   - [ ] Share preview (for future Circle sharing)

**Acceptance Criteria:**
- ✅ Can take photo or select from library
- ✅ Photo appears in timeline card
- ✅ Can view full-size photo
- ✅ Photos persist in database

**Files to Create/Update:**
- `Buds/Features/CreateMemory/PhotoPicker.swift` (new)
- `Buds/Features/Timeline/MemoryDetailView.swift` (new)
- `CreateMemoryView.swift` (update with photo picker)
- `MemoryCard.swift` (already has image display)
- `MemoryRepository.swift` (add image handling)

---

### **Phase 4: Firebase Authentication** (2-3 days)
**Goal:** Phone number verification for Circle sharing

#### Tasks:
1. **Firebase Project Setup**
   - [ ] Create Firebase project at console.firebase.google.com
   - [ ] Enable Phone Authentication
   - [ ] Download `GoogleService-Info.plist`
   - [ ] Add to Xcode project
   - [ ] Enable test phone numbers for development

2. **Phone Auth Flow**
   - [ ] Onboarding screen (first launch only)
   - [ ] Phone number input view
   - [ ] SMS verification code input
   - [ ] Store verified phone in Keychain (encrypted)
   - [ ] Link Firebase UID to local DID

3. **Profile Setup**
   - [ ] Display name input (local only, NOT shared)
   - [ ] Profile preferences (location ON/OFF, default share mode)
   - [ ] Create `profile.created/v1` receipt

**Acceptance Criteria:**
- ✅ New users can verify phone number
- ✅ Phone stored securely in Keychain
- ✅ Profile created with local display name
- ✅ Existing users skip onboarding

**Files to Create:**
- `Buds/Features/Onboarding/PhoneAuthView.swift`
- `Buds/Features/Onboarding/VerificationCodeView.swift`
- `Buds/Features/Profile/ProfileSetupView.swift`
- `Buds/Core/Auth/PhoneAuthManager.swift`

**Security Notes:**
- Phone number NEVER goes in receipts
- Firebase UID → local DID mapping stored locally
- Display name is local-only (not shared)

---

### **Phase 5: Cloudflare Relay Server** (3-4 days)
**Goal:** E2EE message relay for Circle sharing

#### Tasks:
1. **Cloudflare Workers Setup**
   - [ ] Create Cloudflare account
   - [ ] Deploy relay worker (see `RELAY_SERVER.md`)
   - [ ] Set up Durable Objects for message queues
   - [ ] Add authentication (Firebase ID tokens)

2. **Device Registration**
   - [ ] POST `/devices/register` - Register device with FCM token
   - [ ] Store in `devices` table locally
   - [ ] Track device status (active/inactive)

3. **Message Sending**
   - [ ] POST `/messages/send` - Send E2EE message to relay
   - [ ] Server stores in recipient's queue (Durable Object)
   - [ ] FCM push notification sent

4. **Message Receiving**
   - [ ] GET `/messages/poll` - Poll for new messages
   - [ ] Decrypt messages using local private key
   - [ ] Store in `ucr_headers` table
   - [ ] Update UI

5. **E2EE Implementation**
   - [ ] Port `Envelope.swift` from BudsKernelGolden (seal/open)
   - [ ] Port `KeyWrap.swift` (X25519 key agreement)
   - [ ] Implement multi-recipient key wrapping
   - [ ] AAD binding to CID (already tested)

**Acceptance Criteria:**
- ✅ Device can register with relay server
- ✅ Can send E2EE message to another device
- ✅ Recipient receives and decrypts message
- ✅ Server sees only ciphertext (zero knowledge)

**Files to Create:**
- `worker/relay-server.js` (Cloudflare Worker)
- `Buds/Core/Network/RelayClient.swift`
- `Buds/Core/Crypto/Envelope.swift` (port from BudsKernelGolden)
- `Buds/Core/Crypto/KeyWrap.swift` (port from BudsKernelGolden)

**Infrastructure:**
- Cloudflare Workers (free tier: 100k requests/day)
- Durable Objects for message queues
- Firebase Cloud Messaging for push notifications

---

### **Phase 6: Circle Mechanics** (4-5 days)
**Goal:** Share memories with up to 12 friends

#### Tasks:
1. **Circle Management**
   - [ ] Create circle (local-only for now)
   - [ ] Invite friends (generate invite code)
   - [ ] Accept invite (via link or code)
   - [ ] View circle members (local nicknames)
   - [ ] Max 12 members enforced

2. **Memory Sharing**
   - [ ] "Share to Circle" button on memory
   - [ ] Select which members to share with
   - [ ] Create `shared_memories` entry
   - [ ] Wrap content key for each recipient
   - [ ] Send E2EE messages via relay

3. **Shared Timeline**
   - [ ] Circle tab shows shared memories
   - [ ] Filter by member (optional)
   - [ ] Fuzzy location display (if enabled)

**Acceptance Criteria:**
- ✅ Can create circle and invite friends
- ✅ Can share memory with circle members
- ✅ Recipients see shared memory in Circle tab
- ✅ All data E2EE (relay sees only ciphertext)

**Files to Create:**
- `Buds/Features/Circle/CircleView.swift`
- `Buds/Features/Circle/InviteView.swift`
- `Buds/Features/Circle/MemberListView.swift`
- `Buds/Core/Database/Repositories/CircleRepository.swift`

---

## 📊 Timeline Estimate

| Phase | Duration | Depends On |
|-------|----------|------------|
| Phase 3: Images | 3-4 days | - |
| Phase 4: Firebase Auth | 2-3 days | Phase 3 |
| Phase 5: Cloudflare Relay | 3-4 days | Phase 4 |
| Phase 6: Circle Mechanics | 4-5 days | Phase 5 |
| **Total** | **12-16 days** | Sequential |

**Target:** TestFlight v0.2 in 2-3 weeks

---

## 🎨 Design Notes (Future)

### Custom Iconography
- Replace emoji with custom SVG icons
- Product types: flower, edible, concentrate, vape, etc.
- Effects: relaxed, creative, energized, etc.
- Consistent style (line art? filled? gradient?)
- Use SF Symbols where possible, custom only when needed

### Product Type Improvements
- Add THC/CBD range indicators
- Add strain type (indica/sativa/hybrid)
- Add terpene profiles (later)

---

## 🚀 Next Steps

1. **Fix remaining UI bugs** ✅ DONE
2. **User feedback on current flow** → Get your thoughts!
3. **Start Phase 3: Images** → Clear scope, implement, test
4. **One phase at a time** → Ship incrementally

**Ready to start Phase 3?** Let me know if you want to adjust priorities or scope!
