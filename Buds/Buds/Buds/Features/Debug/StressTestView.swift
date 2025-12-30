//
//  StressTestView.swift
//  Buds
//
//  Phase 10.1 Module 5.1: Stress testing UI
//

import SwiftUI

struct StressTestView: View {
    @State private var isGenerating = false
    @State private var isClearing = false
    @State private var progress: String = ""
    @State private var toast: Toast?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    headerSection

                    // Generate Test Data
                    generateSection

                    // Clear Test Data
                    clearSection

                    // Instructions
                    instructionsSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Stress Test")
        .navigationBarTitleDisplayMode(.inline)
        .toast($toast)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.orange)
                    .font(.largeTitle)

                Spacer()
            }

            Text("Performance Testing")
                .font(.budsTitle)
                .foregroundColor(.white)

            Text("Generate test buds to verify app performance with large datasets. Monitor memory usage and scrolling performance.")
                .font(.budsBody)
                .foregroundColor(.budsTextSecondary)
        }
    }

    // MARK: - Generate Section

    private var generateSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Generate Test Data")
                .font(.budsHeadline)
                .foregroundColor(.white)

            VStack(spacing: 12) {
                // 50 buds
                generateButton(count: 50, label: "Generate 50 Buds")

                // 100 buds
                generateButton(count: 100, label: "Generate 100 Buds")

                // 200 buds
                generateButton(count: 200, label: "Generate 200 Buds")
            }

            if !progress.isEmpty {
                HStack {
                    ProgressView()
                        .tint(.budsPrimary)
                    Text(progress)
                        .font(.budsCaption)
                        .foregroundColor(.budsTextSecondary)
                }
                .padding()
                .background(Color.budsCard)
                .cornerRadius(8)
            }
        }
    }

    private func generateButton(count: Int, label: String) -> some View {
        Button {
            generateTestBuds(count: count)
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.budsPrimary)

                Text(label)
                    .font(.budsBodyBold)
                    .foregroundColor(.budsText)

                Spacer()

                if isGenerating {
                    ProgressView()
                        .tint(.budsPrimary)
                }
            }
            .padding()
            .background(Color.budsCard)
            .cornerRadius(12)
        }
        .disabled(isGenerating || isClearing)
    }

    // MARK: - Clear Section

    private var clearSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Clear Test Data")
                .font(.budsHeadline)
                .foregroundColor(.white)

            Button {
                clearTestBuds()
            } label: {
                HStack {
                    Image(systemName: "trash.circle.fill")
                        .foregroundColor(.red)

                    Text("Clear All Test Buds")
                        .font(.budsBodyBold)
                        .foregroundColor(.red)

                    Spacer()

                    if isClearing {
                        ProgressView()
                            .tint(.red)
                    }
                }
                .padding()
                .background(Color.budsCard)
                .cornerRadius(12)
            }
            .disabled(isGenerating || isClearing)

            Text("⚠️ This will delete all buds with test CIDs (test_cid_*)")
                .font(.budsCaption)
                .foregroundColor(.orange)
        }
    }

    // MARK: - Instructions Section

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Testing Checklist")
                .font(.budsHeadline)
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 8) {
                checklistItem("Generate 100+ test buds")
                checklistItem("Navigate to Shelf → Solo jar")
                checklistItem("Scroll through list (check for lag)")
                checklistItem("Open Xcode Memory Graph (Cmd+Shift+M)")
                checklistItem("Verify memory <60MB")
                checklistItem("Test search/filter if implemented")
                checklistItem("Clear test data when done")
            }
            .padding()
            .background(Color.budsCard)
            .cornerRadius(12)

            Text("📊 Expected Results:")
                .font(.budsBodyBold)
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 4) {
                resultItem("100 buds: <60MB memory", color: .budsSuccess)
                resultItem("Smooth 60fps scrolling", color: .budsSuccess)
                resultItem("No crashes or freezes", color: .budsSuccess)
                resultItem("DB queries <100ms", color: .budsSuccess)
            }
            .padding()
            .background(Color.budsCard.opacity(0.5))
            .cornerRadius(12)
        }
    }

    private func checklistItem(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle")
                .foregroundColor(.budsPrimary)
                .font(.caption)

            Text(text)
                .font(.budsCaption)
                .foregroundColor(.budsTextSecondary)
        }
    }

    private func resultItem(_ text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundColor(color)
                .font(.caption)

            Text(text)
                .font(.budsCaption)
                .foregroundColor(.budsTextSecondary)
        }
    }

    // MARK: - Actions

    private func generateTestBuds(count: Int) {
        isGenerating = true
        progress = "Generating buds..."

        Task {
            await StressTestGenerator.shared.generateTestBuds(
                count: count,
                progress: { success, _ in
                    progress = "Created \(success)/\(count) buds..."
                },
                completion: { success, failures in
                    isGenerating = false
                    progress = ""

                    if failures == 0 {
                        toast = Toast(
                            message: "✅ Generated \(success) test buds",
                            style: .success
                        )
                    } else {
                        toast = Toast(
                            message: "⚠️ Generated \(success) buds, \(failures) failures",
                            style: .error
                        )
                    }
                }
            )
        }
    }

    private func clearTestBuds() {
        isClearing = true

        Task {
            await StressTestGenerator.shared.clearTestBuds { deletedCount in
                isClearing = false

                toast = Toast(
                    message: "🧹 Cleared \(deletedCount) test buds",
                    style: .success
                )
            }
        }
    }
}

#Preview {
    NavigationStack {
        StressTestView()
    }
}
