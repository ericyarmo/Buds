//
//  ErrorTracker.swift
//  Buds
//
//  Track errors and patterns for debugging
//

import Foundation

/// Track errors and aggregate patterns
final class ErrorTracker {
    static let shared = ErrorTracker()

    private let queue = DispatchQueue(label: "app.buds.errortracker", qos: .utility)
    private var errors: [TrackedError] = []
    private var errorCounts: [String: Int] = [:]
    private let maxErrors = 500

    private init() {}

    private var isDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    // MARK: - Track Errors

    func track(_ error: Error, context: String? = nil, metadata: [String: Any]? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        guard isDebug else { return }

        let tracked = TrackedError(
            error: error,
            context: context,
            metadata: metadata,
            timestamp: Date(),
            file: (file as NSString).lastPathComponent,
            function: function,
            line: line,
            breadcrumbs: Breadcrumbs.shared.getRecent(limit: 10)
        )

        queue.async { [weak self] in
            guard let self = self else { return }

            self.errors.append(tracked)
            if self.errors.count > self.maxErrors {
                self.errors.removeFirst()
            }

            // Track error counts
            let key = tracked.signature
            self.errorCounts[key, default: 0] += 1

            // Log error
            BudsLogger.shared.error(
                tracked.displayMessage,
                category: .general,
                error: error,
                metadata: [
                    "context": context ?? "none",
                    "count": self.errorCounts[key] ?? 1,
                    "file": tracked.file,
                    "line": tracked.line
                ]
            )

            // Alert on repeated errors
            if let count = self.errorCounts[key], count > 5 {
                BudsLogger.shared.warning(
                    "Repeated error detected: \(tracked.signature)",
                    category: .general,
                    metadata: ["count": count]
                )
            }
        }
    }

    // MARK: - Query

    func getRecentErrors(limit: Int = 50) -> [TrackedError] {
        queue.sync {
            Array(errors.suffix(limit))
        }
    }

    func getErrors(since: Date) -> [TrackedError] {
        queue.sync {
            errors.filter { $0.timestamp >= since }
        }
    }

    func getErrorPatterns() -> [(signature: String, count: Int)] {
        queue.sync {
            errorCounts
                .map { (signature: $0.key, count: $0.value) }
                .sorted { $0.count > $1.count }
        }
    }

    func clear() {
        queue.async { [weak self] in
            self?.errors.removeAll()
            self?.errorCounts.removeAll()
        }
    }

    // MARK: - Export

    func exportReport() -> String {
        let recentErrors = getRecentErrors(limit: 100)
        let patterns = getErrorPatterns()

        var report = """
        ERROR TRACKER REPORT
        ====================
        Total Errors: \(errors.count)
        Unique Patterns: \(patterns.count)


        TOP ERROR PATTERNS:
        """

        for (index, pattern) in patterns.prefix(10).enumerated() {
            report += "\n\(index + 1). [\(pattern.count)x] \(pattern.signature)"
        }

        report += "\n\n\nRECENT ERRORS:\n"

        for (index, error) in recentErrors.enumerated() {
            report += """

            ---
            [\(index + 1)] \(error.displayMessage)
            Context: \(error.context ?? "none")
            Location: \(error.file):\(error.line) in \(error.function)
            Time: \(error.timestamp)
            """

            if let metadata = error.metadata, !metadata.isEmpty {
                report += "\nMetadata: \(metadata)"
            }

            if !error.breadcrumbs.isEmpty {
                report += "\nBreadcrumbs:"
                for crumb in error.breadcrumbs.suffix(5) {
                    report += "\n  - [\(crumb.category.rawValue)] \(crumb.message)"
                }
            }
        }

        return report
    }
}

// MARK: - Tracked Error

struct TrackedError {
    let error: Error
    let context: String?
    let metadata: [String: Any]?
    let timestamp: Date
    let file: String
    let function: String
    let line: Int
    let breadcrumbs: [Breadcrumb]

    var displayMessage: String {
        if let context = context {
            return "\(context): \(error.localizedDescription)"
        }
        return error.localizedDescription
    }

    var signature: String {
        "\(type(of: error)).\(error.localizedDescription)"
    }
}
