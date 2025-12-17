//
//  PerformanceMonitor.swift
//  Buds
//
//  Track operation timings and performance metrics
//

import Foundation

/// Performance monitoring for Buds operations
/// Usage: let tracker = PerformanceMonitor.shared.start("receipt.create")
///        // ... do work ...
///        tracker.end()
final class PerformanceMonitor {
    static let shared = PerformanceMonitor()

    private let queue = DispatchQueue(label: "app.buds.performance", qos: .utility)
    private var metrics: [String: OperationMetrics] = [:]
    private var activeTrackers: [UUID: PerformanceTracker] = [:]

    // Percentile tracking
    private let maxSamples = 1000 // Keep last 1000 samples per operation

    private init() {}

    private var isDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    // MARK: - Track Operations

    /// Start tracking an operation
    func start(_ operation: String, metadata: [String: Any]? = nil) -> PerformanceTracker {
        let tracker = PerformanceTracker(
            id: UUID(),
            operation: operation,
            startTime: Date(),
            metadata: metadata
        )

        queue.async { [weak self] in
            self?.activeTrackers[tracker.id] = tracker
        }

        return tracker
    }

    /// End tracking (called by tracker)
    func end(_ tracker: PerformanceTracker) {
        guard isDebug else { return }

        let endTime = Date()
        let duration = endTime.timeIntervalSince(tracker.startTime)

        queue.async { [weak self] in
            guard let self = self else { return }

            // Remove from active
            self.activeTrackers.removeValue(forKey: tracker.id)

            // Record metric
            var metrics = self.metrics[tracker.operation] ?? OperationMetrics(operation: tracker.operation)
            metrics.record(duration: duration)
            self.metrics[tracker.operation] = metrics

            // Log slow operations
            if duration > 0.1 { // > 100ms
                BudsLogger.shared.warning(
                    "Slow operation: \(tracker.operation)",
                    category: .performance,
                    metadata: [
                        "duration_ms": String(format: "%.2f", duration * 1000),
                        "metadata": tracker.metadata ?? [:]
                    ]
                )
            }

            BudsLogger.shared.debug(
                "\(tracker.operation) completed",
                category: .performance,
                metadata: [
                    "duration_ms": String(format: "%.2f", duration * 1000)
                ]
            )
        }
    }

    // MARK: - Query Metrics

    func getMetrics(for operation: String) -> OperationMetrics? {
        queue.sync {
            metrics[operation]
        }
    }

    func getAllMetrics() -> [OperationMetrics] {
        queue.sync {
            Array(metrics.values).sorted { $0.operation < $1.operation }
        }
    }

    func getActiveOperations() -> [PerformanceTracker] {
        queue.sync {
            Array(activeTrackers.values)
        }
    }

    func reset() {
        queue.async { [weak self] in
            self?.metrics.removeAll()
            self?.activeTrackers.removeAll()
        }
    }

    // MARK: - Report

    func printReport() {
        let allMetrics = getAllMetrics()

        print("\n" + String(repeating: "=", count: 80))
        print("PERFORMANCE REPORT")
        print(String(repeating: "=", count: 80))

        for metric in allMetrics {
            print("""

            Operation: \(metric.operation)
              Count:   \(metric.count)
              Mean:    \(String(format: "%.2f", metric.mean * 1000))ms
              P50:     \(String(format: "%.2f", metric.p50 * 1000))ms
              P95:     \(String(format: "%.2f", metric.p95 * 1000))ms
              P99:     \(String(format: "%.2f", metric.p99 * 1000))ms
              Min:     \(String(format: "%.2f", metric.min * 1000))ms
              Max:     \(String(format: "%.2f", metric.max * 1000))ms
            """)
        }

        let active = getActiveOperations()
        if !active.isEmpty {
            print("\nActive Operations:")
            for tracker in active {
                let elapsed = Date().timeIntervalSince(tracker.startTime)
                print("  - \(tracker.operation): \(String(format: "%.2f", elapsed * 1000))ms (running)")
            }
        }

        print(String(repeating: "=", count: 80) + "\n")
    }

    func exportJSON() -> String {
        let allMetrics = getAllMetrics()

        let data: [[String: Any]] = allMetrics.map { metric in
            [
                "operation": metric.operation,
                "count": metric.count,
                "mean_ms": metric.mean * 1000,
                "p50_ms": metric.p50 * 1000,
                "p95_ms": metric.p95 * 1000,
                "p99_ms": metric.p99 * 1000,
                "min_ms": metric.min * 1000,
                "max_ms": metric.max * 1000
            ]
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }

        return "[]"
    }
}

// MARK: - Performance Tracker

class PerformanceTracker {
    let id: UUID
    let operation: String
    let startTime: Date
    let metadata: [String: Any]?

    init(id: UUID, operation: String, startTime: Date, metadata: [String: Any]?) {
        self.id = id
        self.operation = operation
        self.startTime = startTime
        self.metadata = metadata
    }

    func end() {
        PerformanceMonitor.shared.end(self)
    }

    deinit {
        // Auto-end if not manually ended
        if PerformanceMonitor.shared.getActiveOperations().contains(where: { $0.id == id }) {
            end()
        }
    }
}

// MARK: - Operation Metrics

struct OperationMetrics {
    let operation: String
    private(set) var count: Int = 0
    private(set) var samples: [TimeInterval] = []

    private(set) var mean: TimeInterval = 0
    private(set) var min: TimeInterval = .infinity
    private(set) var max: TimeInterval = 0
    private(set) var p50: TimeInterval = 0
    private(set) var p95: TimeInterval = 0
    private(set) var p99: TimeInterval = 0

    init(operation: String) {
        self.operation = operation
    }

    mutating func record(duration: TimeInterval) {
        count += 1
        samples.append(duration)

        // Keep only last N samples
        if samples.count > 1000 {
            samples.removeFirst()
        }

        // Update statistics
        min = Swift.min(min, duration)
        max = Swift.max(max, duration)

        // Recompute percentiles
        let sorted = samples.sorted()
        mean = samples.reduce(0, +) / Double(samples.count)
        p50 = percentile(sorted, 0.50)
        p95 = percentile(sorted, 0.95)
        p99 = percentile(sorted, 0.99)
    }

    private func percentile(_ sorted: [TimeInterval], _ p: Double) -> TimeInterval {
        guard !sorted.isEmpty else { return 0 }
        let index = Int(Double(sorted.count) * p)
        return sorted[min(index, sorted.count - 1)]
    }
}

// MARK: - Convenience Extensions

extension PerformanceMonitor {
    /// Measure a synchronous operation
    func measure<T>(_ operation: String, metadata: [String: Any]? = nil, block: () throws -> T) rethrows -> T {
        let tracker = start(operation, metadata: metadata)
        defer { tracker.end() }
        return try block()
    }

    /// Measure an async operation
    func measure<T>(_ operation: String, metadata: [String: Any]? = nil, block: () async throws -> T) async rethrows -> T {
        let tracker = start(operation, metadata: metadata)
        defer { tracker.end() }
        return try await block()
    }
}
