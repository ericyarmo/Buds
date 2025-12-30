# Multi-Device & Cloud Storage Architecture

**Status**: Planning / Future Implementation
**Priority**: High (R2 or beyond)
**Created**: December 26, 2025
**Last Reviewed**: December 30, 2025

## Current State (R1)

### Local-First Architecture
- **Primary Storage**: SQLite database on device
- **Blob Storage**: Images stored in `blobs` table (local SQLite)
- **Backup**: None (data only exists on device)
- **Sync**: None (single device only)

### What Happens When...

#### User Deletes App
- ✅ **Expected Behavior**: All local data is lost
- ❌ **Current State**: Data is gone forever, no backup
- ⚠️ **Impact**: User loses all memories, receipts, and images

#### User Gets New Device
- ✅ **Expected Behavior**: Should be able to access previous data
- ❌ **Current State**: Starts fresh, no data from old device
- ⚠️ **Impact**: User loses continuity, appears as new user

#### User Logs in on Web
- ✅ **Expected Behavior**: Should see all memories from all devices
- ❌ **Current State**: Web not implemented, but would start fresh
- ⚠️ **Impact**: No cross-platform access

## Critical Issues to Address

### 1. Device Pinning (TOFU) + Multi-Device
**Problem**: TOFU (Trust On First Use) pins specific device keys. If user gets new device:
- Old device keys are not accessible
- Cannot decrypt messages sent to old device
- Jar members who pinned old device can't send to new device

**Solution Options**:
1. **Device Registry** - User's DID maps to multiple device IDs
2. **Key Migration** - Export/import device keys (security risk)
3. **Cloud Key Backup** - Store encrypted keys in cloud (iCloud Keychain, etc.)

### 2. Data Continuity Across Devices
**Problem**: User expects same data on all devices

**Solution Options**:
1. **Multi-Device Sync** (like Signal)
   - Primary device syncs to secondary devices
   - Requires secure device-to-device sync protocol
2. **Cloud Backup + Restore** (like WhatsApp)
   - Backup to iCloud/Google Drive
   - Restore on new device
3. **Hybrid**: Local-first + cloud backup for disaster recovery

### 3. Image Storage at Scale
**Problem**: Storing images in SQLite doesn't scale

**Current Approach**:
- Images stored as BLOBs in `blobs` table
- Works for <100 images
- Becomes slow at >1000 images

**Solution**:
- **Phase 1** (R1): Keep in SQLite (acceptable for MVP)
- **Phase 2** (R2): Migrate to file system
  - Images stored in app's Documents directory
  - Database stores file paths, not BLOBs
- **Phase 3** (R3+): Cloud storage
  - R2 for images
  - CloudKit/iCloud Photos for iOS
  - CDN for web access

## Proposed Architecture (Future)

### Multi-Device Sync (R2)

```
User's Devices:
  iPhone (Primary) ←→ Relay ←→ iPad (Secondary)
                   ←→ Relay ←→ Web Client
```

**Flow**:
1. User creates memory on iPhone
2. Memory synced to relay with receipt CID
3. Other devices poll relay, download new receipts
4. Decrypt using shared account key (not device-specific)

**Changes Required**:
- Add device registry to relay
- Store account-level encryption key (in addition to device keys)
- Implement device-to-device sync protocol

### Cloud Backup Strategy (R2)

#### Option A: Encrypted Backups (Privacy-First)
```
Device → Encrypt with user password → iCloud/R2 → Restore
```

**Pros**:
- User controls encryption key
- Zero-knowledge architecture
- No cloud provider can read data

**Cons**:
- User must remember password
- Lost password = lost data

#### Option B: Platform-Native Backups
```
iOS → iCloud Backup (automatic)
Android → Google Drive Backup
Web → R2 storage
```

**Pros**:
- Seamless user experience
- No password to remember
- Platform handles encryption

**Cons**:
- Cloud provider has access (Apple/Google)
- Not truly zero-knowledge

### Tiered Storage (R3+)

See `/docs/features/TIERED_STORAGE_PLAN.md` for full plan.

**Summary**:
- **Hot**: Recent memories (last 30 days) - SQLite + local images
- **Warm**: Older memories (31-365 days) - SQLite + R2 images
- **Cold**: Archive (>1 year) - R2 for everything, local index only

## Network Implications

### Current (R1)
- **Relay Usage**: Only for sharing messages
- **Bandwidth**: Low (only receipts, <1KB each)
- **Storage**: All local

### Multi-Device (R2)
- **Relay Usage**: Device sync + message sharing
- **Bandwidth**: Medium (receipts + images for sync)
- **Storage**: Local + cloud backup

### Full Cloud (R3+)
- **Relay Usage**: Real-time sync, message queue
- **Bandwidth**: High (streaming images from R2)
- **Storage**: Hybrid (local cache + cloud primary)

## Implementation Phases

### Phase 0 (R1 - Current)
- ✅ Local SQLite database
- ✅ Device-specific TOFU keys
- ✅ Single device only
- ✅ No backup

### Phase 1 (R1.1 - Q1 2026)
- [ ] Add device registry to relay
- [ ] Store multiple devices per DID
- [ ] Implement device list API
- [ ] No sync yet, just registry

### Phase 2 (R2 - Q2 2026)
- [ ] iCloud Backup integration (iOS)
- [ ] Export/import database feature
- [ ] Account-level encryption key
- [ ] Basic device-to-device sync

### Phase 3 (R2.1 - Q3 2026)
- [ ] R2 integration for images
- [ ] Move images from SQLite to R2
- [ ] CDN for web access
- [ ] Tiered storage (hot/warm/cold)

### Phase 4 (R3 - Q4 2026)
- [ ] Real-time sync across devices
- [ ] Web client with full feature parity
- [ ] Android support with Google Drive backup
- [ ] Platform-agnostic cloud storage

## Technical Challenges

### 1. Key Management
**Question**: How do we handle encryption keys across devices?

**Options**:
- **Device-Specific Keys** (current): Secure, but breaks on device loss
- **Account Key + Device Keys**: Hybrid approach, better UX
- **Key Derivation from Password**: User-controlled, but password required

**Recommendation**: Hybrid approach
- Account key stored in iCloud Keychain (iOS) / KeyStore (Android)
- Device keys for TOFU verification
- Password-based key derivation as fallback

### 2. Conflict Resolution
**Question**: What if user creates memory on Device A while offline, then creates different memory on Device B?

**Options**:
- **Last-Write-Wins**: Simple, but can lose data
- **CRDTs**: Complex, but mathematically correct
- **Receipt Chains**: Use UCR parent/root CIDs for ordering

**Recommendation**: Receipt chains (already have this!)
- Receipts have parentCID → natural ordering
- Conflicts resolved by receipt timestamp
- No additional complexity needed

### 3. Offline Support
**Question**: Should app work fully offline?

**Answer**: YES (local-first)
- All operations work offline
- Sync happens in background when online
- Network only needed for sharing and sync

## Security Considerations

### E2EE Across Devices
- Account key encrypted with device key
- Device key stored in secure enclave
- Cloud backup encrypted with user-controlled key

### TOFU + Multi-Device
- Each device has its own Ed25519 keypair
- Relay stores all device public keys for a DID
- Sender encrypts for all recipient devices
- First device to decrypt verifies signature (TOFU)

### Zero-Knowledge Cloud Backup
- Backup encrypted locally before upload
- Cloud provider (iCloud/R2) cannot decrypt
- Encryption key derived from user password or stored in Keychain

## Open Questions

1. **Should we support web without device registration?**
   - Pro: Lower barrier to entry
   - Con: Web device can't receive E2EE messages without key

2. **How do we handle device limits?**
   - Signal: 5 devices max
   - WhatsApp: 1 phone + 4 linked devices
   - Buds: TBD (suggest 3 devices initially)

3. **What's the backup strategy for images?**
   - All images to cloud? (expensive)
   - Only favorites/recent? (confusing UX)
   - User-controlled setting? (best, but complex)

4. **How do we charge for cloud storage?**
   - Free tier: 100MB (estimate 200 memories with images)
   - Paid tier: Unlimited (or 10GB, 50GB tiers)
   - R2 costs: ~$0.015/GB/month

## Next Steps (To Unblock Phase 9b)

For now, **document these limitations clearly**:
1. Add to onboarding: "Data stored locally on this device"
2. Add to settings: "Backup your data" (export feature)
3. Consider adding manual export/import as interim solution

**Decision**: Defer multi-device to R2. Focus on R1 completion first.

## Related Documents

- `/docs/architecture/E2EE_DESIGN.md` - Current E2EE implementation
- `/docs/features/TIERED_STORAGE_PLAN.md` - Future storage architecture
- `/docs/architecture/PRIVACY_ARCHITECTURE.md` - Privacy principles
- `/docs/planning/R1_MASTER_PLAN.md` - R1 scope and timeline

---

**Note**: This is a planning document. Implementation details will evolve as we build.
