//
//  MoveMemoryView.swift
//  Buds
//
//  Created by Eric Yarmolinsky on 12/28/25.
//
//  Phase 10.1 Module 2.3: Move memory to different jar
//

import SwiftUI

struct MoveMemoryView: View {
    let memoryID: UUID
    let currentJarID: String
    let onMove: (String) -> Void  // Callback with new jar ID

    @Environment(\.dismiss) var dismiss
    @StateObject private var jarManager = JarManager.shared
    @State private var isMoving = false

    private var availableJars: [Jar] {
        jarManager.jars.filter { $0.id != currentJarID }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                if availableJars.isEmpty {
                    emptyState
                } else {
                    jarList
                }
            }
            .navigationTitle("Move Bud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.budsTextSecondary)
                }
            }
        }
    }

    // MARK: - Jar List

    private var jarList: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(availableJars) { jar in
                    Button {
                        moveToJar(jar)
                    } label: {
                        HStack(spacing: 16) {
                            // Jar icon (simplified from JarCard)
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.budsPrimary.opacity(0.15))
                                    .frame(width: 40, height: 40)

                                Image(systemName: "leaf.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.budsPrimary.opacity(0.6))
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(jar.name)
                                    .font(.budsBodyBold)
                                    .foregroundColor(.budsTextPrimary)

                                if let budCount = jarManager.jarStats[jar.id]?.totalBuds {
                                    Text("\(budCount) buds")
                                        .font(.budsCaption)
                                        .foregroundColor(.budsTextSecondary)
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .foregroundColor(.budsTextSecondary)
                        }
                        .padding()
                        .background(Color.budsCard)
                        .cornerRadius(12)
                    }
                    .disabled(isMoving)
                }
            }
            .padding()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 60))
                .foregroundColor(.budsTextSecondary.opacity(0.5))

            Text("No other jars")
                .font(.budsBody)
                .foregroundColor(.budsTextSecondary)

            Text("Create more jars to move buds between them")
                .font(.budsCaption)
                .foregroundColor(.budsTextSecondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding()
    }

    // MARK: - Move

    private func moveToJar(_ jar: Jar) {
        isMoving = true

        Task {
            onMove(jar.id)
            dismiss()
        }
    }
}
