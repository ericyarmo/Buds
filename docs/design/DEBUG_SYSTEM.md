# Debug System

Comprehensive debugging framework for Buds with structured logging, performance monitoring, error tracking, and real-time console.

**DEBUG builds only** - Zero overhead in production.

---

## Quick Start

```swift
// Logging
BudsLogger.shared.info("User logged in", category: .auth, metadata: ["did": did])
BudsLogger.shared.error("Save failed", category: .database, error: error)

// Performance
let tracker = PerformanceMonitor.shared.start("receipt.create")
defer { tracker.end() }

// Or use convenience wrapper
let result = await PerformanceMonitor.shared.measure("db.query") {
    try await database.fetch()
}

// Error tracking
ErrorTracker.shared.track(error, context: "CreateMemory.save", metadata: ["strain": name])

// Breadcrumbs
Breadcrumbs.shared.userAction("Tapped save")
Breadcrumbs.shared.navigation("TimelineView")
Breadcrumbs.shared.database("Fetched 10 memories")
```

---

## Components

### 1. BudsLogger

Thread-safe structured logging.

**Levels:** debug 🔍, info ℹ️, warning ⚠️, error ❌, critical 🚨

**Categories:** general, receipts, database, crypto, network, ui, performance, auth

**Features:**
- Automatic timestamps, file/line tracking
- Last 1000 logs stored
- Export to string
- System log integration

### 2. PerformanceMonitor

Operation timing with statistics.

**Tracks:** Count, Mean, Min/Max, P50, P95, P99

**Auto-alerts:** Operations >100ms logged as warnings

**Export:** Console report or JSON

### 3. ErrorTracker

Error aggregation and pattern detection.

**Features:**
- Automatic breadcrumb attachment
- Signature-based grouping
- Pattern alerts (5+ repeats)
- Last 500 errors stored

### 4. Breadcrumbs

Event trail for debugging.

**Categories:** navigation 🧭, user 👆, state 🔄, network 🌐, database 💾, ui 🎨

**Storage:** Last 100 breadcrumbs

**Auto-attached** to all errors (last 10 crumbs)

### 5. DebugConsole

Real-time UI overlay (simulator only).

**Tabs:**
- Logs - Live stream with filtering
- Perf - Metrics dashboard
- Errors - Recent errors
- Trail - Breadcrumb timeline

**Location:** Bottom of screen (collapsed by default)

---

## Integration Examples

### Receipt Creation
```swift
func createReceipt() async throws {
    let tracker = PerformanceMonitor.shared.start("receipt.create")
    defer { tracker.end() }

    BudsLogger.shared.info("Creating receipt", category: .receipts)
    Breadcrumbs.shared.record("Creating receipt", category: .database)

    do {
        let cid = try await manager.create()
        BudsLogger.shared.info("Receipt created", category: .receipts, metadata: ["cid": cid])
    } catch {
        BudsLogger.shared.error("Receipt failed", category: .receipts, error: error)
        ErrorTracker.shared.track(error, context: "createReceipt")
        throw error
    }
}
```

### Database Query
```swift
func fetchMemories() async throws -> [Memory] {
    try await PerformanceMonitor.shared.measure("db.fetchMemories") {
        try await db.readAsync { /* query */ }
    }
}
```

---

## Performance Targets

From BudsKernelGolden physics tests:
- Receipt creation: **p50=0.11ms**
- CBOR encoding: **p50=0.08ms**
- Database inserts: **p50=1-5ms**

Monitor with PerformanceMonitor to catch regressions.

---

## Production Builds

All debug code stripped via `#if DEBUG`:
- Zero runtime overhead
- No console overlay
- Logs still sent to system log (crash reports)

---

## File Locations

See integration examples:
- `ReceiptManager.swift:27` - Receipt tracking
- `TimelineView.swift:49` - Navigation
- `CreateMemoryView.swift:186` - User actions
- `MemoryRepository.swift:19` - DB perf

**Source:** `Core/Debug/`

---

Built for Buds v0.1 🌿
