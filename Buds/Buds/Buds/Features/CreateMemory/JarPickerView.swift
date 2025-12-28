//
//  JarPickerView.swift
//  Buds
//
//  Phase 10 Step 1: Jar selection before creating memory (no nested sheets)
//

import SwiftUI

struct JarPickerView: View {
    @ObservedObject var jarManager = JarManager.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        List {
            ForEach(jarManager.jars) { jar in
                NavigationLink(destination: CreateMemoryView(jarID: jar.id)) {
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
                    }
                }
            }
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
        JarPickerView()
    }
}
