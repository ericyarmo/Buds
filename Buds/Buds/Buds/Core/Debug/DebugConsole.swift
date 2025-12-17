//
//  DebugConsole.swift
//  Buds
//
//  In-app debug console with logs, performance, errors, and breadcrumbs
//  Only available in DEBUG builds
//

import SwiftUI

#if DEBUG

// MARK: - Debug Console View

struct DebugConsole: View {
    @StateObject private var viewModel = DebugConsoleViewModel()
    @State private var selectedTab: DebugTab = .logs
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                expandedView
            } else {
                collapsedView
            }
        }
        .background(Color.black.opacity(0.95))
        .cornerRadius(12)
        .shadow(radius: 10)
        .onAppear {
            viewModel.startListening()
        }
    }

    // MARK: - Collapsed View

    private var collapsedView: some View {
        HStack {
            Image(systemName: "ladybug.fill")
                .foregroundColor(.green)
            Text("Debug Console")
                .font(.caption)
                .foregroundColor(.white)
            Spacer()
            Button {
                withAnimation(.spring()) {
                    isExpanded = true
                }
            } label: {
                Image(systemName: "chevron.up")
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring()) {
                isExpanded = true
            }
        }
    }

    // MARK: - Expanded View

    private var expandedView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "ladybug.fill")
                    .foregroundColor(.green)
                Text("Debug Console")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button {
                    viewModel.clearAll()
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.white)
                }
                Button {
                    withAnimation(.spring()) {
                        isExpanded = false
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .foregroundColor(.white)
                }
            }
            .padding()
            .background(Color.black)

            // Tabs
            Picker("Tab", selection: $selectedTab) {
                ForEach(DebugTab.allCases, id: \.self) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            // Content
            switch selectedTab {
            case .logs:
                LogsView(logs: viewModel.logs)
            case .performance:
                PerformanceView(metrics: viewModel.metrics)
            case .errors:
                ErrorsView(errors: viewModel.errors)
            case .breadcrumbs:
                BreadcrumbsView(breadcrumbs: viewModel.breadcrumbs)
            }
        }
        .frame(height: 400)
    }
}

// MARK: - View Model

@MainActor
class DebugConsoleViewModel: ObservableObject {
    @Published var logs: [LogEntry] = []
    @Published var metrics: [OperationMetrics] = []
    @Published var errors: [TrackedError] = []
    @Published var breadcrumbs: [Breadcrumb] = []

    private var logObserver: NSObjectProtocol?

    func startListening() {
        // Listen for log updates
        logObserver = NotificationCenter.default.addObserver(
            forName: .budsLogDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshLogs()
        }

        // Initial load
        refreshAll()

        // Refresh periodically
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshAll()
        }
    }

    func refreshAll() {
        refreshLogs()
        refreshMetrics()
        refreshErrors()
        refreshBreadcrumbs()
    }

    func refreshLogs() {
        logs = BudsLogger.shared.getRecentLogs(limit: 100)
    }

    func refreshMetrics() {
        metrics = PerformanceMonitor.shared.getAllMetrics()
    }

    func refreshErrors() {
        errors = ErrorTracker.shared.getRecentErrors(limit: 50)
    }

    func refreshBreadcrumbs() {
        breadcrumbs = Breadcrumbs.shared.getRecent(limit: 50)
    }

    func clearAll() {
        BudsLogger.shared.clearLogs()
        PerformanceMonitor.shared.reset()
        ErrorTracker.shared.clear()
        Breadcrumbs.shared.clear()
        refreshAll()
    }

    deinit {
        if let observer = logObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

// MARK: - Tabs

enum DebugTab: CaseIterable {
    case logs, performance, errors, breadcrumbs

    var title: String {
        switch self {
        case .logs: return "Logs"
        case .performance: return "Perf"
        case .errors: return "Errors"
        case .breadcrumbs: return "Trail"
        }
    }
}

// MARK: - Logs View

struct LogsView: View {
    let logs: [LogEntry]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(logs.enumerated()), id: \.offset) { index, log in
                        LogRow(log: log)
                            .id(index)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .onChange(of: logs.count) { _ in
                if let lastIndex = logs.indices.last {
                    withAnimation {
                        proxy.scrollTo(lastIndex, anchor: .bottom)
                    }
                }
            }
        }
    }
}

struct LogRow: View {
    let log: LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(log.level.icon)
                    .font(.caption2)
                Text("[\(log.category.rawValue.uppercased())]")
                    .font(.caption2)
                    .foregroundColor(categoryColor(log.category))
                Text(log.message)
                    .font(.caption2)
                    .foregroundColor(.white)
            }
            if let metadata = log.metadata, !metadata.isEmpty {
                Text(formatMetadata(metadata))
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 2)
    }

    private func categoryColor(_ category: LogCategory) -> Color {
        Color(hex: category.color) ?? .gray
    }

    private func formatMetadata(_ metadata: [String: Any]) -> String {
        metadata.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
    }
}

// MARK: - Performance View

struct PerformanceView: View {
    let metrics: [OperationMetrics]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(metrics, id: \.operation) { metric in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(metric.operation)
                            .font(.caption.bold())
                            .foregroundColor(.white)
                        HStack {
                            metricPill("Count", "\(metric.count)")
                            metricPill("P50", String(format: "%.1fms", metric.p50 * 1000))
                            metricPill("P95", String(format: "%.1fms", metric.p95 * 1000))
                        }
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(6)
                }
            }
            .padding()
        }
    }

    private func metricPill(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
            Text(value)
                .font(.caption2.bold())
                .foregroundColor(.white)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.1))
        .cornerRadius(4)
    }
}

// MARK: - Errors View

struct ErrorsView: View {
    let errors: [TrackedError]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if errors.isEmpty {
                    Text("No errors")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    ForEach(Array(errors.enumerated()), id: \.offset) { _, error in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(error.displayMessage)
                                .font(.caption.bold())
                                .foregroundColor(.red)
                            if let context = error.context {
                                Text("Context: \(context)")
                                    .font(.caption2)
                                    .foregroundColor(.white)
                            }
                            Text("\(error.file):\(error.line)")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        .padding(8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Breadcrumbs View

struct BreadcrumbsView: View {
    let breadcrumbs: [Breadcrumb]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(Array(breadcrumbs.enumerated()), id: \.offset) { _, crumb in
                    HStack(spacing: 4) {
                        Text(crumb.category.icon)
                            .font(.caption2)
                        Text(crumb.message)
                            .font(.caption2)
                            .foregroundColor(.white)
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding()
        }
    }
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: // RGB
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Debug Overlay Modifier

struct DebugOverlay: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            content

            VStack {
                Spacer()
                DebugConsole()
                    .padding()
            }
        }
    }
}

#endif

// MARK: - View Extension (always available)

extension View {
    func debugConsole() -> some View {
        #if DEBUG
        modifier(DebugOverlay())
        #else
        self
        #endif
    }
}
