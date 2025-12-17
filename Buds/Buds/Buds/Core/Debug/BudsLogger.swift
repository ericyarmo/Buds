//
//  BudsLogger.swift
//  Buds
//
//  Structured logging system with categories, levels, and formatting
//  Available in all builds, but only logs in DEBUG
//

import Foundation
import os.log

/// Centralized logging for Buds app
/// Usage: BudsLogger.shared.info("User created memory", category: .receipts, metadata: ["cid": cid])
final class BudsLogger {
    static let shared = BudsLogger()

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    // Thread-safe log storage
    private let queue = DispatchQueue(label: "app.buds.logger", qos: .utility)
    private var logEntries: [LogEntry] = []
    private let maxEntries = 1000 // Keep last 1000 logs

    private init() {}

    private var isDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    // MARK: - Public API

    func debug(_ message: String, category: LogCategory = .general, metadata: [String: Any]? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .debug, message: message, category: category, metadata: metadata, file: file, function: function, line: line)
    }

    func info(_ message: String, category: LogCategory = .general, metadata: [String: Any]? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .info, message: message, category: category, metadata: metadata, file: file, function: function, line: line)
    }

    func warning(_ message: String, category: LogCategory = .general, metadata: [String: Any]? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .warning, message: message, category: category, metadata: metadata, file: file, function: function, line: line)
    }

    func error(_ message: String, category: LogCategory = .general, error: Error? = nil, metadata: [String: Any]? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        var fullMetadata = metadata ?? [:]
        if let error = error {
            fullMetadata["error"] = error.localizedDescription
            fullMetadata["errorType"] = String(describing: type(of: error))
        }
        log(level: .error, message: message, category: category, metadata: fullMetadata, file: file, function: function, line: line)
    }

    func critical(_ message: String, category: LogCategory = .general, error: Error? = nil, metadata: [String: Any]? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        var fullMetadata = metadata ?? [:]
        if let error = error {
            fullMetadata["error"] = error.localizedDescription
            fullMetadata["errorType"] = String(describing: type(of: error))
        }
        log(level: .critical, message: message, category: category, metadata: fullMetadata, file: file, function: function, line: line)
    }

    // MARK: - Core Logging

    private func log(level: LogLevel, message: String, category: LogCategory, metadata: [String: Any]?, file: String, function: String, line: Int) {
        // Skip logging in release builds
        guard isDebug else { return }

        let timestamp = Date()
        let fileName = (file as NSString).lastPathComponent

        let entry = LogEntry(
            timestamp: timestamp,
            level: level,
            category: category,
            message: message,
            metadata: metadata,
            file: fileName,
            function: function,
            line: line
        )

        // Store entry
        queue.async { [weak self] in
            guard let self = self else { return }
            self.logEntries.append(entry)
            if self.logEntries.count > self.maxEntries {
                self.logEntries.removeFirst()
            }
        }

        // Print to console
        printEntry(entry)

        // Send to system log
        logToSystem(entry)

        // Notify observers (for debug console)
        NotificationCenter.default.post(name: .budsLogDidChange, object: entry)
    }

    private func printEntry(_ entry: LogEntry) {
        let time = dateFormatter.string(from: entry.timestamp)
        let icon = entry.level.icon
        let category = entry.category.rawValue.uppercased()
        let location = "\(entry.file):\(entry.line)"

        var output = "\(icon) [\(time)] [\(category)] \(entry.message)"

        if let metadata = entry.metadata, !metadata.isEmpty {
            let metaString = metadata.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            output += " | \(metaString)"
        }

        output += " @ \(location)"

        print(output)
    }

    private func logToSystem(_ entry: LogEntry) {
        let osLog = OSLog(subsystem: "app.buds", category: entry.category.rawValue)
        let type: OSLogType = entry.level.osLogType
        os_log("%{public}@", log: osLog, type: type, entry.message)
    }

    // MARK: - Query Logs

    func getRecentLogs(limit: Int = 100) -> [LogEntry] {
        queue.sync {
            Array(logEntries.suffix(limit))
        }
    }

    func getLogs(category: LogCategory? = nil, level: LogLevel? = nil, since: Date? = nil) -> [LogEntry] {
        queue.sync {
            logEntries.filter { entry in
                if let category = category, entry.category != category { return false }
                if let level = level, entry.level != level { return false }
                if let since = since, entry.timestamp < since { return false }
                return true
            }
        }
    }

    func clearLogs() {
        queue.async { [weak self] in
            self?.logEntries.removeAll()
        }
    }

    // MARK: - Export

    func exportLogs() -> String {
        queue.sync {
            logEntries.map { entry in
                let time = dateFormatter.string(from: entry.timestamp)
                var line = "[\(time)] [\(entry.level.rawValue.uppercased())] [\(entry.category.rawValue)] \(entry.message)"

                if let metadata = entry.metadata, !metadata.isEmpty {
                    let metaString = metadata.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                    line += " | \(metaString)"
                }

                line += " @ \(entry.file):\(entry.line) in \(entry.function)"
                return line
            }.joined(separator: "\n")
        }
    }
}

// MARK: - Log Entry

struct LogEntry {
    let timestamp: Date
    let level: LogLevel
    let category: LogCategory
    let message: String
    let metadata: [String: Any]?
    let file: String
    let function: String
    let line: Int
}

// MARK: - Log Level

enum LogLevel: String {
    case debug
    case info
    case warning
    case error
    case critical

    var icon: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .critical: return "🚨"
        }
    }

    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        case .critical: return .fault
        }
    }
}

// MARK: - Log Category

enum LogCategory: String {
    case general
    case receipts
    case database
    case crypto
    case network
    case ui
    case performance
    case auth

    var color: String {
        switch self {
        case .general: return "#999999"
        case .receipts: return "#4CAF50"
        case .database: return "#2196F3"
        case .crypto: return "#9C27B0"
        case .network: return "#FF9800"
        case .ui: return "#E91E63"
        case .performance: return "#00BCD4"
        case .auth: return "#F44336"
        }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let budsLogDidChange = Notification.Name("BudsLogDidChange")
}
