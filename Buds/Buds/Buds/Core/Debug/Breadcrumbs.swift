//
//  Breadcrumbs.swift
//  Buds
//
//  Record app state trail for debugging crashes and errors
//

import Foundation

/// Breadcrumb trail for debugging
/// Tracks user actions, state changes, and key events
final class Breadcrumbs {
    static let shared = Breadcrumbs()

    private let queue = DispatchQueue(label: "app.buds.breadcrumbs", qos: .utility)
    private var crumbs: [Breadcrumb] = []
    private let maxCrumbs = 100

    private init() {}

    private var isDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    // MARK: - Record

    func record(_ message: String, category: BreadcrumbCategory = .general, metadata: [String: Any]? = nil) {
        guard isDebug else { return }

        let crumb = Breadcrumb(
            timestamp: Date(),
            category: category,
            message: message,
            metadata: metadata
        )

        queue.async { [weak self] in
            guard let self = self else { return }
            self.crumbs.append(crumb)
            if self.crumbs.count > self.maxCrumbs {
                self.crumbs.removeFirst()
            }

            BudsLogger.shared.debug(
                "📍 \(message)",
                category: .general,
                metadata: metadata
            )
        }
    }

    // Convenience methods
    func navigation(_ screen: String, metadata: [String: Any]? = nil) {
        record("Navigated to \(screen)", category: .navigation, metadata: metadata)
    }

    func userAction(_ action: String, metadata: [String: Any]? = nil) {
        record("User: \(action)", category: .user, metadata: metadata)
    }

    func stateChange(_ change: String, metadata: [String: Any]? = nil) {
        record("State: \(change)", category: .state, metadata: metadata)
    }

    func network(_ event: String, metadata: [String: Any]? = nil) {
        record("Network: \(event)", category: .network, metadata: metadata)
    }

    func database(_ event: String, metadata: [String: Any]? = nil) {
        record("DB: \(event)", category: .database, metadata: metadata)
    }

    // MARK: - Query

    func getRecent(limit: Int = 50) -> [Breadcrumb] {
        queue.sync {
            Array(crumbs.suffix(limit))
        }
    }

    func getAll() -> [Breadcrumb] {
        queue.sync {
            crumbs
        }
    }

    func clear() {
        queue.async { [weak self] in
            self?.crumbs.removeAll()
        }
    }

    // MARK: - Export

    func exportTrail() -> String {
        let all = getAll()

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"

        return all.map { crumb in
            let time = formatter.string(from: crumb.timestamp)
            var line = "[\(time)] [\(crumb.category.icon)] \(crumb.message)"

            if let metadata = crumb.metadata, !metadata.isEmpty {
                let metaString = metadata.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                line += " | \(metaString)"
            }

            return line
        }.joined(separator: "\n")
    }
}

// MARK: - Breadcrumb

struct Breadcrumb {
    let timestamp: Date
    let category: BreadcrumbCategory
    let message: String
    let metadata: [String: Any]?
}

// MARK: - Breadcrumb Category

enum BreadcrumbCategory: String {
    case general
    case navigation
    case user
    case state
    case network
    case database
    case ui

    var icon: String {
        switch self {
        case .general: return "📍"
        case .navigation: return "🧭"
        case .user: return "👆"
        case .state: return "🔄"
        case .network: return "🌐"
        case .database: return "💾"
        case .ui: return "🎨"
        }
    }
}
