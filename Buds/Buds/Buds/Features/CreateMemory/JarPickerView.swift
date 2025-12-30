//
//  JarPickerView.swift
//  Buds
//
//  Phase 10 Step 1: Jar selection before creating memory (no nested sheets)
//  Phase 10.1 Module 1.0: Uses callback pattern for create → enrich flow
//

import SwiftUI

struct JarPickerView: View {
    let onJarSelected: (String) -> Void  // Callback with jarID

    @ObservedObject var jarManager = JarManager.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            List {
                ForEach(jarManager.jars) { jar in
                    Button {
                        // Trigger create flow for selected jar (parent will handle dismiss)
                        onJarSelected(jar.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(jar.name)
                                    .font(.budsBody)
                                    .foregroundColor(.budsText)

                                if let description = jar.description {
                                    Text(description)
                                        .font(.budsCaption)
                                        .foregroundColor(.budsTextSecondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            Text("\(jarManager.jarStats[jar.id]?.totalBuds ?? 0) buds")
                                .font(.budsCaption)
                                .foregroundColor(.secondary)

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .listRowBackground(Color.budsCard)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Choose Jar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .task {
            // Ensure jars are loaded
            if jarManager.jars.isEmpty {
                await jarManager.loadJars()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        JarPickerView { jarID in
            print("Selected jar: \(jarID)")
        }
    }
}
