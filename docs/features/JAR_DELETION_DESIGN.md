# Jar Deletion System Design

**Date**: December 26, 2025
**Status**: ✅ Implemented (Phase 9b)

---

## Overview

Safe jar deletion with zero data loss. Memories are preserved by moving them to Solo jar before deletion.

---

## What Gets Deleted

### 1. Jar Record
- Entry removed from `jars` table
- Jar ID becomes invalid

### 2. Jar Members (Associations Only)
- All entries in `jar_members` table for this jar
- **Device keys remain** in `devices` table (TOFU protection preserved)
- Members can be re-added to other jars

---

## What Gets PRESERVED

### 1. Memories (Zero Data Loss!)
- **All memories moved to Solo jar** before deletion
- `local_receipts.jar_id` updated: `deleted_jar_id` → `solo_jar_id`
- No receipts deleted from `ucr_headers` (permanent chain)

### 2. Receipt Chain Integrity
- UCR receipts remain in `ucr_headers` table
- Receipt CIDs unchanged
- Parent/root CID links preserved
- Signatures intact

### 3. Images
- All blobs remain in `blobs` table
- Image CIDs still referenced by memories
- No orphaned images created

### 4. Device Keys (TOFU)
- All pinned Ed25519 keys in `devices` table remain
- TOFU trust relationships preserved
- Members can be re-added to other jars with same keys

---

## Solo Jar Protection

### Cannot Delete Solo Jar
**Reason**: System jar, default destination for orphaned memories

**UI Protection**:
- Solo jar has **no context menu** (long press does nothing)
- Delete option not shown

**Backend Protection** (lines 79-83 in JarRepository.swift):
```swift
let isSolo = jar.name.trimmingCharacters(in: .whitespaces).lowercased() == "solo"
guard !isSolo else {
    throw JarError.cannotDeleteSoloJar
}
```

**Error Message**: "Cannot delete Solo jar (system jar)"

---

## Deletion Flow (Step-by-Step)

### User Action
1. Long press jar card on Shelf
2. Context menu appears: "Delete Jar" (red, trash icon)
3. Tap "Delete Jar"

### Confirmation Alert
**Title**: "Delete {Jar Name}?"

**Message (if jar has buds)**:
> "All X buds in this jar will be moved to Solo. Members will be removed."

**Message (if jar is empty)**:
> "This jar is empty. Members will be removed."

**Buttons**:
- "Cancel" (dismisses alert, no changes)
- "Delete" (red, destructive action)

### Backend Process (JarRepository.deleteJar)

#### Step 1: Verify Jar Exists (lines 75-77)
```swift
guard let jar = try await getJar(id: id) else {
    throw JarError.jarNotFound
}
```

#### Step 2: Check if Solo (lines 80-83)
```swift
let isSolo = jar.name.trimmingCharacters(in: .whitespaces).lowercased() == "solo"
guard !isSolo else {
    throw JarError.cannotDeleteSoloJar
}
```

#### Step 3: Find Solo Jar (lines 86-91)
```swift
guard let soloJar = allJars.first(where: {
    $0.name.trimmingCharacters(in: .whitespaces).lowercased() == "solo"
}) else {
    throw JarError.soloJarNotFound  // Critical error, shouldn't happen
}
```

#### Step 4: Move Memories to Solo (lines 94-100)
```sql
UPDATE local_receipts SET jar_id = ? WHERE jar_id = ?
-- Arguments: [soloJar.id, deletedJar.id]
```

**Console Log**:
```
📦 Moved 5 memories from Friends to Solo
```

#### Step 5: Delete Jar Members (lines 103-109)
```sql
DELETE FROM jar_members WHERE jar_id = ?
```

**Console Log**:
```
👥 Deleted 3 member associations
```

#### Step 6: Delete Jar (lines 112-114)
```swift
try Jar.deleteOne(db, key: id)
```

**Console Log**:
```
✅ Deleted jar 'Friends' (id: abc-123)
```

### UI Update (ShelfView.deleteJar)
1. Reload jar list: `await jarManager.loadJars()`
2. Stats refresh automatically (parallel fetch)
3. Grid reflows, deleted jar disappears
4. Solo jar shows updated bud count

**Console Log**:
```
✅ Loaded 6 jars with stats
✅ Jar deleted and UI updated
```

---

## Data Integrity Guarantees

### 1. No Orphaned Memories
- Memories **always** belong to a jar
- If jar deleted → memories move to Solo
- No `jar_id = NULL` allowed

### 2. Receipt Chain Preserved
- UCR receipts never deleted
- Parent/root CID links intact
- Can reconstruct full history

### 3. TOFU Keys Protected
- Device keys remain in `devices` table
- Trust relationships preserved
- Members can be re-invited

### 4. Images Safe
- Blobs table unchanged
- CIDs still referenced by memories
- No garbage collection needed (yet)

---

## Error Handling

### Error 1: Solo Jar Deletion Attempt
**Error**: `JarError.cannotDeleteSoloJar`
**Message**: "Cannot delete Solo jar (system jar)"
**UI**: Alert shown, no changes made

### Error 2: Jar Not Found
**Error**: `JarError.jarNotFound`
**Message**: "Jar not found"
**Cause**: Jar already deleted or never existed

### Error 3: Solo Jar Missing
**Error**: `JarError.soloJarNotFound`
**Message**: "Solo jar not found. Please reinstall the app."
**Cause**: Database corruption or fresh install without jar creation
**Impact**: Critical - cannot delete jars safely

---

## Receipt Type (Future)

### Current (R1): Local-Only Deletion
- No receipt created for jar deletion
- Deletion is purely local operation
- Other devices won't know jar was deleted

### Future (R2+): Multi-Device Sync
Will need new receipt type:

```typescript
interface JarDeletedReceipt {
  receiptType: "jar.deleted"
  payload: {
    jarID: string
    deletedAt: number  // timestamp
    reassignedToJarID: string  // Usually "solo"
    memoryCount: number  // How many memories moved
  }
}
```

**Sync Behavior**:
1. Device A deletes jar → creates `jar.deleted` receipt
2. Receipt synced to relay
3. Device B receives receipt → marks jar as deleted locally
4. Device B moves memories to Solo jar
5. Both devices in sync

---

## Testing Strategy

### Critical Tests (Suite 1D)
1. ✅ Context menu appears (non-Solo jars)
2. ✅ Solo jar protected (no delete option)
3. ✅ Delete empty jar (no memories to move)
4. ✅ Delete jar with buds (memory reassignment verified)
5. ✅ Cancel deletion (no changes)
6. ✅ Delete jar with members (associations removed, keys preserved)
7. ✅ Solo jar backend protection (throws error)
8. ✅ Stats refresh after delete

### Data Integrity Verification
```sql
-- Check memories moved to Solo
SELECT jar_id, COUNT(*) FROM local_receipts GROUP BY jar_id;

-- Verify jar members deleted
SELECT * FROM jar_members WHERE jar_id = 'DELETED_JAR_ID';
-- Should return 0 rows

-- Verify device keys preserved
SELECT * FROM devices WHERE owner_did IN (
  -- DIDs of deleted jar members
);
-- Should still return device records
```

---

## UI/UX Decisions

### Long Press (Context Menu)
**Why**: Standard iOS pattern for item actions
**Alternative Considered**: Swipe-to-delete (rejected - too easy to accidentally trigger)

### Confirmation Alert
**Why**: Destructive action requires confirmation
**Message Customization**: Shows bud count to inform user of impact

### No Undo
**Why**: Memories aren't deleted, just moved (low risk)
**Future**: Could add "undo" that moves memories back to recreated jar

### Solo Jar No Menu
**Why**: Solo jar cannot be deleted, so no need to show empty menu
**Implementation**: Context menu only added if `!isSolo`

---

## Database Schema Impact

### Tables Modified
1. `local_receipts` - `jar_id` updated for moved memories
2. `jar_members` - rows deleted
3. `jars` - row deleted

### Tables Unchanged
1. `ucr_headers` - receipts preserved
2. `blobs` - images preserved
3. `devices` - TOFU keys preserved
4. `received_memories` - shared memory records preserved

---

## Performance Considerations

### Deletion Time
- **Empty jar**: ~10ms (2 DELETE queries)
- **Jar with 100 buds**: ~50ms (1 UPDATE + 2 DELETEs)
- **Jar with members**: Add ~5ms per member

### Stats Refresh
- After deletion: Full stats reload (~30-50ms for 10 jars)
- Could optimize to only update affected jars (Solo + deleted)

### UI Reflow
- Grid reflow is instant (SwiftUI LazyVGrid)
- No flicker or jump

---

## Security Implications

### TOFU Preservation
**Good**: Device keys remain pinned after jar deletion
**Reason**: Member might be added to another jar - want same TOFU verification

### Receipt Chain
**Good**: No receipt deletion = audit trail intact
**Reason**: Can always prove when memories were created, even if jar deleted

### No Sync Yet
**Current Risk**: User deletes jar on Phone, still exists on iPad
**Future Fix**: `jar.deleted` receipt in R2

---

## Migration Path (R1 → R2)

### No Migration Needed!
**Reason**: Deletion is already safe (memories preserved)

**R2 Changes**:
1. Add `jar.deleted` receipt type
2. Sync deletion across devices
3. Optional: Tombstone table for deleted jars (for audit)

---

## Known Limitations

### 1. No Undo
- Once deleted, jar name/description lost
- Memories moved to Solo (can't auto-recreate jar)
- **Future**: Add jar deletion history with undo

### 2. No Multi-Device Sync
- Deletion only affects current device
- Other devices still show jar until manual delete
- **Fix in R2**: Receipt-based sync

### 3. No Confirmation of Memory Move
- Alert says "will be moved" but doesn't show success
- **Future**: Show toast: "5 buds moved to Solo"

---

## Console Logs (Expected Output)

### Successful Deletion
```
📦 Moved 5 memories from Friends to Solo
👥 Deleted 2 member associations
✅ Deleted jar 'Friends' (id: abc-123)
✅ Loaded 6 jars with stats
✅ Jar deleted and UI updated
```

### Solo Jar Protection
```
❌ Cannot delete Solo jar (system jar)
```

### Error Case
```
❌ Jar not found
```

---

## Related Files

**Backend**:
- `/Core/Database/Repositories/JarRepository.swift` (lines 69-117)
- `/Core/JarManager.swift` (errors: lines 220-222)

**Frontend**:
- `/Features/Shelf/ShelfView.swift` (lines 13-16, 97-108, 155-170)

**Testing**:
- `/docs/testing/PHASE_9B_TESTING_FLOW.md` (Test Suite 1D)

---

## Summary

Jar deletion is **safe by design**:
- ✅ Zero data loss (memories preserved)
- ✅ Solo jar protected
- ✅ TOFU keys preserved
- ✅ Receipt chain intact
- ✅ UI feedback clear
- ✅ Error handling robust

**Worst case**: User accidentally deletes jar → All memories moved to Solo (annoying but not catastrophic)

**No critical failure modes**. System remains consistent.

---

**Ready for production!** 🚀
