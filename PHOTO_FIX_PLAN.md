# Photo System Fix Plan

## Current Issues

1. **Multi-select works in logs but photos don't actually appear** - count shows correctly but selectedImages array not updating
2. **Images don't show in saved memories** - critical bug, images not displaying in timeline/detail view
3. **Need BeReal-style dual camera** - auto-capture back then front (2 photos at once)
4. **Need photo reordering** - tap to swap/reorder the 3 photo slots

---

## Root Cause Analysis

### Issue 1: Multi-select not working
**Suspected cause:**
- PhotosPicker selection binding issue
- State update timing problem
- onChange not triggering properly

**Debug approach:**
- Add more detailed logging to track selectedItems vs selectedImages
- Verify @Binding is updating parent state
- Check if loadPhotos is actually completing

### Issue 2: Images not showing in memories
**Suspected causes (in order of likelihood):**
1. Database save issue - images not being persisted with CIDs
2. Database load issue - images not being fetched from blobs
3. ImageCarousel not rendering Data properly
4. CID generation failing silently

**Debug approach:**
- Log in CreateMemoryViewModel.save() - check if images being passed
- Log in MemoryRepository.addImages() - verify CID generation & blob insertion
- Log in MemoryRepository.parseMemory() - verify blob fetching
- Check ImageCarousel receives non-empty Data array

### Issue 3 & 4: Camera features
These are new features, not bugs.

---

## Implementation Plan

### Phase 1: Fix Multi-Select (Highest Priority)
**Steps:**
1. Add detailed logging to PhotosPicker onChange
2. Verify selectedItems array is populated
3. Check if loadPhotos async is completing
4. Test with single photo first, then multi
5. Add explicit MainActor.run wrapping for state updates

**Files to modify:**
- `PhotoPicker.swift` - enhance logging, fix state updates

**Success criteria:**
- Console shows all photos loading
- selectedImages.count matches number selected
- Thumbnails appear in photo picker UI

### Phase 2: Fix Image Display in Memories (Critical)
**Steps:**
1. Add logging throughout image save pipeline:
   - CreateMemoryViewModel.save() → log selectedImages count
   - MemoryRepository.addImages() → log each CID generation
   - Database blob insertion → log success/failure
2. Add logging to image load pipeline:
   - MemoryRepository.parseMemory() → log image_cids JSON
   - Blob fetch → log each CID lookup
   - ImageCarousel → log images.count received
3. Test save → reload → verify images appear
4. Fix whichever step is failing

**Files to modify:**
- `CreateMemoryView.swift` - add logging
- `MemoryRepository.swift` - add detailed logging throughout
- `ImageCarousel.swift` - add logging
- Potentially `Database.swift` - verify migration worked

**Success criteria:**
- Images save to database (check in DB browser if needed)
- Images load from database on timeline
- ImageCarousel displays multiple images with swipe

### Phase 3: BeReal-Style Dual Camera
**Design:**
```
┌─────────────────────┐
│  Take Photo Menu    │
├─────────────────────┤
│ 📷 Single Photo     │ ← Regular camera
│ 👥 BeReal (Dual)    │ ← Auto back+front capture
│ 📚 Photo Library    │
└─────────────────────┘
```

**Flow for BeReal mode:**
1. User taps "BeReal (Dual)"
2. Camera opens, immediately captures back camera
3. Instantly flips to front camera
4. Shows countdown "3...2...1"
5. Auto-captures front camera
6. Shows both photos in preview
7. User confirms → both photos added to selectedImages

**Steps:**
1. Create `DualCameraView` component
2. Implement auto-capture sequence
3. Add to PhotoPicker menu as option
4. Handle both photos returned as array

**Files to modify:**
- `PhotoPicker.swift` - add DualCameraView option
- New file: `DualCameraView.swift`

**Success criteria:**
- Menu shows BeReal option
- Auto-captures back then front
- Both photos added (2 of 3 slots used)
- No manual shutter press needed

### Phase 4: Photo Reordering
**Design:**
```
[Photo 1] [Photo 2] [Photo 3]
    ↕️        ↕️        ↕️
  Tap to move left/right
```

**Steps:**
1. Add reorder UI below photo thumbnails
2. Tap photo → show move left/right buttons
3. Update selectedImages array order
4. Animate position change

**Files to modify:**
- `PhotoPicker.swift` - add reorder controls

**Success criteria:**
- Can tap any photo
- Move left/right buttons appear
- Photos swap positions
- Order persists to saved memory

---

## Execution Order

1. ✅ **Fix multi-select FIRST** - can't test anything else without this
2. ✅ **Fix image display** - critical for shipping
3. 🔄 **BeReal dual camera** - nice feature, can ship without it
4. 🔄 **Photo reordering** - polish, can ship without it

---

## Testing Checklist

After each phase:
- [ ] Select 1 photo → appears in picker
- [ ] Select 3 photos → all appear in picker
- [ ] Save memory with photos → shows in timeline
- [ ] Tap memory → detail view shows carousel
- [ ] Swipe carousel → see all photos
- [ ] Delete photo from picker → works
- [ ] BeReal mode → captures 2 photos
- [ ] Reorder photos → position changes

---

## Notes

- Focus on multi-select + display bugs FIRST
- BeReal feature is cool but not blocking
- Need to see actual error logs to diagnose properly
- May need to check database directly if blob storage is issue

