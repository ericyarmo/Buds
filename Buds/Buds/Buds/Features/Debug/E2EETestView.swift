//
//  E2EETestView.swift
//  Buds
//
//  Phase 10 Step 0.1: UI to run E2EE verification test
//

import SwiftUI

struct E2EETestView: View {
    @State private var testRunning = false
    @State private var testPassed: Bool?
    @State private var testOutput: String = ""
    @State private var showOutput = false

    // Memory baseline test
    @State private var creatingBuds = false
    @State private var budsCreated = 0
    @State private var showJarPicker = false
    @ObservedObject var jarManager = JarManager.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Warning header
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.orange)

                    Text("CRITICAL TEST")
                        .font(.budsTitle)

                    Text("This test verifies that jar deletion doesn't break E2EE signature verification.")
                        .font(.budsBody)
                        .foregroundColor(.budsTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Text("If this test fails, DO NOT ship to TestFlight.")
                        .font(.budsBodyBold)
                        .foregroundColor(.red)
                }
                .padding(.top, 40)

                Spacer()

                // Test status
                if let passed = testPassed {
                    VStack(spacing: 16) {
                        Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(passed ? .green : .red)

                        Text(passed ? "TEST PASSED ✅" : "TEST FAILED ❌")
                            .font(.budsTitle)
                            .foregroundColor(passed ? .green : .red)

                        if passed {
                            Text("Jar deletion is safe for E2EE")
                                .font(.budsBody)
                                .foregroundColor(.green)

                            Text("OK to proceed with TestFlight")
                                .font(.budsBodyBold)
                                .foregroundColor(.green)
                        } else {
                            Text("ABORT TESTFLIGHT")
                                .font(.budsBodyBold)
                                .foregroundColor(.red)

                            Text("Signature verification breaks after jar deletion")
                                .font(.budsBody)
                                .foregroundColor(.red)
                        }

                        Button {
                            showOutput = true
                        } label: {
                            Text("View Detailed Output")
                                .font(.budsBody)
                                .foregroundColor(.budsPrimary)
                        }
                    }
                } else if testRunning {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)

                        Text("Running E2EE verification test...")
                            .font(.budsBody)
                            .foregroundColor(.budsTextSecondary)
                    }
                }

                Spacer()

                Divider()
                    .padding(.vertical)

                // Memory baseline test section
                VStack(spacing: 16) {
                    Text("Memory Baseline Test")
                        .font(.budsHeadline)

                    Text("Create 100 test buds to verify memory usage")
                        .font(.budsBody)
                        .foregroundColor(.budsTextSecondary)
                        .multilineTextAlignment(.center)

                    if creatingBuds {
                        VStack(spacing: 12) {
                            ProgressView(value: Double(budsCreated), total: 100.0)
                                .tint(.budsPrimary)
                            Text("Creating buds: \(budsCreated)/100")
                                .font(.budsCaption)
                        }
                        .padding(.horizontal, 40)
                    } else {
                        Button {
                            showJarPicker = true
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Create 100 Test Buds")
                            }
                            .font(.budsBodyBold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.budsPrimary)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal, 32)
                    }
                }

                Spacer()

                // Run button
                if !testRunning {
                    Button {
                        runTest()
                    } label: {
                        HStack {
                            Image(systemName: "play.circle.fill")
                            Text(testPassed == nil ? "Run Test" : "Run Again")
                        }
                        .font(.budsBodyBold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.budsPrimary)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("E2EE Verification Test")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showOutput) {
                NavigationStack {
                    ScrollView {
                        Text(testOutput)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                    }
                    .navigationTitle("Test Output")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showOutput = false }
                        }
                    }
                }
            }
            .sheet(isPresented: $showJarPicker) {
                NavigationStack {
                    List {
                        ForEach(jarManager.jars) { jar in
                            Button {
                                showJarPicker = false
                                create100Buds(in: jar.id)
                            } label: {
                                HStack {
                                    Text(jar.name)
                                        .font(.budsBody)
                                    Spacer()
                                    Text("\(jarManager.jarStats[jar.id]?.totalBuds ?? 0) buds")
                                        .font(.budsCaption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .navigationTitle("Choose Jar")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showJarPicker = false }
                        }
                    }
                }
            }
        }
    }

    private func runTest() {
        testRunning = true
        testPassed = nil
        testOutput = ""

        Task {
            // Redirect print output to capture it
            let test = E2EEVerificationTest()

            do {
                await test.runTest()
                // If we get here, test passed
                await MainActor.run {
                    testPassed = true
                    testRunning = false
                }
            } catch {
                // Test failed
                await MainActor.run {
                    testPassed = false
                    testRunning = false
                    testOutput = "Test failed with error: \(error)"
                }
            }
        }
    }

    private func create100Buds(in jarID: String) {
        creatingBuds = true
        budsCreated = 0

        Task {
            let repository = MemoryRepository()

            print("🧪 Creating 100 test buds for memory baseline test...")

            for i in 1...100 {
                do {
                    _ = try await repository.create(
                        strainName: "Test Strain \(i)",
                        productType: [.flower, .concentrate, .edible, .vape].randomElement() ?? .flower,
                        rating: Int.random(in: 1...5),
                        notes: "Memory baseline test bud #\(i). This is a test bud created to verify memory usage with 100+ buds in a jar.",
                        brand: ["Test Brand A", "Test Brand B", "Test Brand C"].randomElement(),
                        thcPercent: Double.random(in: 15...30),
                        cbdPercent: Double.random(in: 0...2),
                        amountGrams: Double.random(in: 1...3.5),
                        effects: ["relaxed", "happy", "focused", "creative", "energized"].shuffled().prefix(Int.random(in: 2...4)).map { $0 },
                        consumptionMethod: [.joint, .pipe, .bong, .vape, .edible].randomElement(),
                        locationCID: nil,
                        jarID: jarID
                    )

                    await MainActor.run {
                        budsCreated = i
                    }

                    // Small delay to avoid overwhelming DB
                    try await Task.sleep(nanoseconds: 10_000_000)  // 0.01 seconds
                } catch {
                    print("❌ Failed to create bud \(i): \(error)")
                }
            }

            print("✅ Created 100 test buds")

            // Refresh jar stats
            await jarManager.loadJars()

            await MainActor.run {
                creatingBuds = false
            }
        }
    }
}

// MARK: - Preview

struct E2EETestView_Previews: PreviewProvider {
    static var previews: some View {
        E2EETestView()
    }
}
