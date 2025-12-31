# Phase 10.3: Implementation Ready - Final Summary

**Date:** December 30, 2025
**Total Estimated Time:** 50-70 hours
**Status:** ✅ Ready to start implementing tonight

---

## What We're Building

**Convert jars from local-only to real multiplayer with proper crypto + distributed systems hardening.**

### The Problem We're Solving

**Current state (broken):**
- You create jar → exists only on your device
- You add friend → they don't see jar on their device
- You share bud → lands in friend's Solo jar with no context
- Not actually multiplayer

**After Phase 10.3 (working):**
- You create jar → send invite to friends
- Friends see invite → accept → jar appears on their shelf
- You share bud → lands in correct jar on all members' devices within 30s
- Toast notifications, unread badges, real group chat UX

---

## Three Major Fixes

### 1. Crypto Hardening (15-22 hours)

**Problems identified:**
- 🔴 Multi-device DID problem (each device = different identity)
- 🔴 Phone hash rainbow tables (trivial to reverse)
- 🔴 CBOR canonicalization dependency (library update breaks all signatures)
- 🟡 TOFU attack window (relay can MITM first key exchange)
- 🟡 Sender pubkey dependency (new devices after TOFU fail)
- ⚪ No forward secrecy (device compromise → all past messages readable)
- ⚪ Metadata leakage (relay sees social graph)

**Fixes in 10.3:**
- ✅ Phone-based identity (DID = hash(phone + salt), shared across devices)
- ✅ Deterministic phone encryption (prevents rainbow tables)
- ✅ CBOR library pinning + golden tests (prevents breaks)
- ✅ Dynamic device discovery (handles new devices)
- ✅ Safety number UI (optional TOFU verification)

**Accepted limitations (document, defer to Phase 12):**
- ⚪ No forward secrecy (complex, defer to Signal Protocol implementation)
- ⚪ Metadata leakage (fundamental tradeoff, accept for V1)

### 2. Distributed Systems Hardening (28-40 hours)

**Problems identified:**
- 🔴 Receipt reordering (network doesn't deliver in order)
- 🔴 Deleted jar resurrection (late receipts recreate deleted jar)
- 🔴 Removed member sends receipts (security issue)
- 🔴 Receipt replay attacks
- 🟡 Missing receipt detection
- 🟡 Offline operation conflicts
- 🟡 Partial member lists

**Fixes in 10.3:**
- ✅ Causal ordering (parent_cid chains)
- ✅ Sequence numbers (gap detection + backfill)
- ✅ Tombstones (deletion safety)
- ✅ Replay protection (track processed CIDs)
- ✅ Server-side validation (relay enforces membership)
- ✅ Offline conflict detection (validate before sending)
- ✅ Dependency resolution (queue receipts, process in order)

### 3. Jar Sync Flows (Already Planned)

**What works after 10.3:**
- Create jar → invite members → members accept → jar synced
- Share bud → jar_id in payload → lands in correct jar
- Rename jar → all members see new name
- Add/remove members → syncs to everyone
- Delete jar → all members see deletion, buds move to Solo
- Real-time notifications (toasts, badges)

---

## Implementation Plan

### Week 1: Crypto + Relay Foundation (22-30 hours)

**Days 1-2 (8-12 hours):**
- Module 0.1: CBOR pinning + golden tests (2-3h)
- Module 0.2: Phone-based identity (4-6h)
- Module 0.3: Deterministic phone encryption (3-4h)

**Days 3-4 (8-12 hours):**
- Module 0.4: Dynamic device discovery (2-3h)
- Module 0.5: Safety number UI (1-2h)
- Module 0.6: Relay infrastructure (3-4h)
- Module 1: Receipt types + sequencing (3-4h)

**Day 5 (6-8 hours):**
- Module 2: Database migration v8 (2-3h)
- Module 3: Tombstones + replay protection (2-3h)
- Testing: Crypto + sequencing tests (2h)

### Week 2: Sync Flows (20-28 hours)

**Days 1-2 (10-14 hours):**
- Module 4: Dependency resolution (4-5h)
- Module 5: Jar creation sync (2-3h)
- Module 6: Member invite flow (4-5h)

**Days 3-4 (8-12 hours):**
- Module 7: Bud jar_id sync (2-3h)
- Module 8: Offline hardening (3-4h)
- Module 9: UI components (3-4h)

**Day 5 (2-3 hours):**
- Module 10: Notifications + polish (2-3h)

### Week 3: Integration & Testing (7-10 hours)

**Days 1-3 (7-10 hours):**
- Two-device testing (jar creation, invites, buds)
- Edge case testing (offline, conflicts, deletions)
- Three-device testing (group chat scenarios)
- Bug fixes + polish

---

## Key Decisions Made

### Crypto Architecture

1. **Identity Model:** Phone-based DIDs (not per-device)
   - DID = did:phone:SHA256(phone + account_salt)
   - All devices with same phone = same DID
   - Tradeoff: Phone required (not crypto-pure), but matches UX

2. **Phone Storage:** Deterministic encryption on relay
   - Prevents rainbow tables
   - Enables lookups
   - Requires both DB leak AND secrets leak to expose phones

3. **CBOR Stability:** Pin exact version, golden tests
   - Lock SwiftCBOR to 0.4.5 forever
   - Test fails if encoding changes
   - Any upgrade requires migration

4. **Forward Secrecy:** Defer to Phase 12
   - Current limitation documented clearly
   - Signal Protocol is 20-30 hours of work
   - Out of scope for V1

### Distributed Systems

1. **Sequencing:** Per-jar monotonic sequences
   - Simpler than global sequencing
   - Gap detection + backfill

2. **Conflict Resolution:** First-to-relay wins
   - Relay assigns final sequence numbers
   - Deterministic, no clock skew issues

3. **Offline Window:** 7 days max
   - Balance UX vs complexity
   - >7 days = full resync, discard queue

4. **Tombstones:** Never expire
   - Disk is cheap
   - Safety is valuable
   - Prevent deleted jar resurrection

### UX

1. **Jar Invites:** Accept/decline flow (like WhatsApp groups)
2. **Safety Numbers:** Optional verification (power users)
3. **Notifications:** Toast + badges (not push yet)
4. **Sync Status:** "Syncing..." / "Up to date" indicators

---

## Success Metrics

**Technical:**
- [ ] 95%+ receipt delivery rate
- [ ] Sequence gaps detected and recovered
- [ ] Zero tombstone violations
- [ ] Zero replay attacks
- [ ] Multi-device identity works (same phone = same DID)
- [ ] CBOR encoding stable (golden tests pass)

**UX:**
- [ ] Jar invites clear and intuitive
- [ ] Shared buds land in correct jar >99%
- [ ] Toasts helpful, not spammy
- [ ] Sync state visible

**Security:**
- [ ] No phone number leaks from DB dump
- [ ] TOFU attacks detectable (safety numbers)
- [ ] Removed members can't send receipts
- [ ] Forward secrecy limitation documented

---

## What's NOT in Scope (Deferred)

**Phase 12: Signal Protocol**
- Forward secrecy (Double Ratchet)
- Future secrecy (key rotation)
- Deniability

**Phase 13: Metadata Resistance**
- Message padding (hide sizes)
- Mixing networks (hide timing)
- Tor integration (hide IP)

**Phase 15: CBOR Migration**
- Only if library update required
- Re-sign all receipts
- Dual verification support

---

## Files to Review Before Starting

**Must read (in order):**
1. `PHASE_10.3_EDGE_CASE_AUDIT.md` - All distributed systems edge cases
2. `PHASE_10.3_CRYPTO_ADDENDUM.md` - All crypto blind spots & fixes
3. `PHASE_10.3_JAR_SYNC_HARDENED.md` - Full implementation plan (this is the master doc)

**Supporting docs:**
- `CANONICALIZATION_SPEC.md` - Receipt signing (existing)
- `E2EE_DESIGN.md` - Encryption design (existing)
- `DATABASE_SCHEMA.md` - Current schema (existing)

---

## Start Here

**Module 0.1: CBOR Library Pinning (2-3 hours)**

1. Open `Package.swift`
2. Change SwiftCBOR dependency to exact version 0.4.5
3. Create `Tests/ReceiptTests/CBORCanonicalityTests.swift`
4. Add golden file test for SessionPayload
5. Run test, capture expected hex bytes
6. Document in `docs/CBOR_POLICY.md`

**This is the foundation. Do NOT skip. MUST be done first.**

---

## Ready to Start?

**Estimated total: 50-70 hours over 2-3 weeks**

**You said you're not scared of 50-100 hours. This is it.**

**Philosophy:**
- Coherent, not perfect
- Fix critical issues, document limitations
- Learn distributed systems + crypto properly
- Build something defensible

**Let's build this right. 🚀**

---

**Next step:** Start Module 0.1 (CBOR pinning) tonight.
