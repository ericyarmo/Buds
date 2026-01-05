# Module 4 Distributed Systems Review - Expert Planning Required

**Purpose:** Review gap detection, backfill, and queueing architecture for distributed jar sync. Identify flaws, edge cases, and propose rock-solid solution.

**Requirement:** NO CODE IMPLEMENTATION. Planning and architecture review ONLY.

---

## Context

**System:** Distributed jar (shared folder) sync using relay envelope architecture

**How it works:**
1. Client creates jar receipt (e.g., "jar.created", "bud.shared") WITHOUT sequence number
2. Client sends receipt to relay (Cloudflare Workers)
3. Relay assigns authoritative sequence number (1, 2, 3, ...)
4. Relay broadcasts envelope to all jar members: `{sequenceNumber, receiptCID, receiptData, signature, senderDID}`
5. Clients process receipts in relay sequence order

**Module 3 (Complete):** Simple in-order processing
- Replay protection (skip duplicates)
- Tombstone checking (skip deleted jars)
- Signature verification
- Apply receipt to local state
- Mark as processed

**Module 4 (Current):** Handle imperfect networks
- Out-of-order delivery (receive seq 1,4,2,3)
- Packet loss (receive seq 1,2,4 - missing 3)
- Incomplete backfills (request 3-10, get only 3-5)

---

## Network Realities We Must Handle

**Arrival Patterns:**
- **Happy path:** 1 → 2 → 3 → 4 (sequential, no gaps)
- **Out-of-order:** 1 → 4 → 2 → 3
- **Single gap:** 1 → 2 → 4 (missing 3)
- **Multiple gaps:** 1 → 5 → 9 (missing 2-4 and 6-8)
- **Duplicate:** 1 → 2 → 2 → 3 (replay protection handles this)
- **Late arrival:** Process 1-5, then receive 3 again (seq < expected)

**Backfill Scenarios:**
- Request 3-10, get 3-10 (complete)
- Request 3-10, get 3-5 (incomplete - relay doesn't have 6-10 yet)
- Request 3-10, get nothing (relay error or receipts deleted)
- Request 3-10, get 3-10, but 8 is corrupt (verification fails)

**Race Conditions:**
- Request backfill 3-5, while processing, receive 6 from normal sync
- Multiple gaps trigger overlapping backfill requests
- Queue processing while new receipts arrive

---

## Current Plan (See MODULE_4_REWRITE.md)

### State Machine

```
HAPPY PATH (seq == expected):
  → Verify → Apply → Mark Processed → Try Queue

GAP DETECTED (seq > expected):
  → Verify → Queue → Request Backfill → Wait

LATE/DUPLICATE (seq < expected):
  → Skip
```

### Key Functions

**processEnvelope(envelope, skipGapDetection = false):**
- Replay protection
- Tombstone check
- Gap detection (if !skipGapDetection)
  - If seq > expected: verify, queue, backfill, return
  - If seq < expected: skip
  - If seq == expected: verify, apply, mark, try queue
- Try queue processing

**requestBackfill(jarID, from, to):**
- Call relay API: GET /jars/{jarID}/receipts?from=X&to=Y
- Process results with `skipGapDetection=true`
- Warn on incomplete backfills

**processQueuedReceipts(jarID):**
- Get all queued receipts for jar
- Sort by sequence
- Process contiguous receipts from expectedSeq
- Stop when gap detected
- Each processed: call `processEnvelope(..., skipGapDetection=true)`

---

## Red Flags I've Identified

**1. Recursion Concern:**
- `processEnvelope()` calls `processQueuedReceipts()`
- `processQueuedReceipts()` calls `processEnvelope()`
- Prevented by `skipGapDetection` flag, but is this bulletproof?

**2. Backfill Triggering New Gaps:**
- Request 3-10, get 3-5
- Process 3,4,5 with `skipGapDetection=true`
- Receipt 6 arrives later → gap detected (expect 6, got 6) → no gap?
- But what if we queued 7 earlier? Do we detect gap from 5→7?

**3. Queue Processing During Backfill:**
- Backfill arrives for seq 3-5
- While processing, normal sync delivers seq 6
- processEnvelope(6) calls processQueuedReceipts()
- Race: Are we processing queue twice?

**4. Incomplete Backfill Recovery:**
- Request 3-10, get 3-5
- Now we have processed 1,2,3,4,5
- Queue has [7, 9] (arrived out-of-order)
- How do we request 6, 8, 10?
- Current plan: Next gap will trigger it... but when?

**5. Verification Before Queue:**
- Plan says verify BEFORE queueing
- Why? If receipt is invalid, we skip it
- But we requested backfill for it... do we retry?

**6. Jar Creation Edge Case:**
- First receipt is jar.created (seq=1)
- `getLastSequence()` returns 0 (jar doesn't exist)
- Expected = 1, actual = 1 → happy path ✓
- But jar table insert happens in applyReceipt()
- If applyReceipt() fails, next receipt expects seq=2 but jar still doesn't exist
- Do we end up in inconsistent state?

---

## Your Task

**Analyze the plan and answer:**

1. **Recursion Safety:** Is the `skipGapDetection` flag sufficient? Can you prove no infinite loops?

2. **Gap Detection After Incomplete Backfill:** Walk through scenario:
   - Receive: 1, 2, 10
   - Process 1, 2. Detect gap. Queue 10. Request 3-9.
   - Backfill returns: 3, 4, 5 (incomplete)
   - Process 3, 4, 5 with skipGapDetection=true
   - Try queue → can't process 10 (expect 6)
   - **Question:** How does system request 6-9? When does it detect this gap?

3. **Queue Processing Race:** Can `processQueuedReceipts()` be called concurrently?
   - Thread safety?
   - Optimistic locking?
   - Should we add a mutex?

4. **Backfill Overlap:** What if:
   - Request backfill 3-10 (in flight)
   - Receive 4 from normal sync
   - Backfill arrives with 3-10
   - Do we process 4 twice?
   - Replay protection prevents this... right?

5. **Verification Failure in Queue:** Scenario:
   - Receive seq 5 (out of order)
   - Verify ✓, queue it
   - Request backfill 2-4
   - Backfill arrives, process 2-4 ✓
   - Try queue → processEnvelope(5) → verify AGAIN → fails this time (corrupted?)
   - **Question:** Do we delete from queue? Retry? Skip?

6. **Jar Creation Failure Recovery:** Scenario:
   - Receive jar.created (seq=1)
   - Process: verify ✓, apply → DB error (disk full?)
   - Receipt NOT marked processed (failed)
   - Next receipt: jar.member_added (seq=2)
   - Expected = 0 (jar still doesn't exist), actual = 2
   - Gap detected, queue 2, request backfill 1
   - Backfill gets jar.created again
   - **Question:** Does this work? Or do we end up with weird state?

7. **Edge Cases:** List any other edge cases I'm missing.

---

## Required Output

Please provide:

**1. Correctness Analysis:**
- For each red flag above, answer: "SAFE" or "BUG" with explanation
- If BUG, propose fix

**2. Rewritten State Machine:**
- If current plan has flaws, rewrite state transitions
- Prove correctness (informal proof fine)

**3. Pseudocode for Critical Functions:**
- `processEnvelope()` - complete logic with ALL edge cases
- `requestBackfill()` - handle incomplete backfills
- `processQueuedReceipts()` - handle races

**4. Database Invariants:**
- What invariants MUST hold for correctness?
- How do we verify/enforce them?

**5. Testing Strategy:**
- Specific test cases that would break current plan
- How to test race conditions?

---

## Constraints

- **Relay is authoritative:** Sequences cannot be changed by client
- **Relay is eventually consistent:** Backfill might be incomplete now, complete later
- **Network is unreliable:** Out-of-order delivery, packet loss
- **Client is single-threaded:** Swift async/await (no real concurrency within one client)
- **Multiple clients:** Different devices can process same jar concurrently

---

## Success Criteria

**Your plan is correct if:**
1. All receipts eventually processed in relay sequence order
2. No receipt processed twice (idempotency)
3. No infinite loops (termination)
4. No deadlocks (queue eventually drains)
5. Handles all network failure modes gracefully
6. Handles all backfill scenarios correctly
7. No race conditions (even with concurrent clients)

**Focus on proving these properties.**

---

**Expected time:** 2-3 hours of deep thinking. This is the hard part. Get it right.
