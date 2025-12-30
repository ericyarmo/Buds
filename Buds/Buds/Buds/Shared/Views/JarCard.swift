//
//  JarCard.swift
//  Buds
//
//  Summary card for jar list in CircleView
//

import SwiftUI

struct JarCard: View {
    let jar: Jar

    @State private var memberCount: Int = 0
    @State private var budCount: Int = 0

    var body: some View {
        HStack(spacing: 16) {
            // Mason jar icon (Phase 10.1 Module 2)
            jarIcon

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(jar.name)
                    .font(.budsBodyBold)
                    .foregroundColor(.budsTextPrimary)

                HStack(spacing: 12) {
                    Label("\(memberCount)", systemImage: "person.2")
                    Label("\(budCount)", systemImage: "leaf")
                }
                .font(.budsCaption)
                .foregroundColor(.budsTextSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.budsTextSecondary)
        }
        .padding()
        .background(Color.budsCard)
        .cornerRadius(12)
        .task {
            await loadCounts()
        }
    }

    // MARK: - Jar Icon (Phase 10.1 Module 2)

    private var jarIcon: some View {
        ZStack {
            // Mason jar body
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.budsPrimary.opacity(0.15))
                .frame(width: 50, height: 50)

            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.budsPrimary, lineWidth: 2)
                .frame(width: 50, height: 50)

            // Lid (horizontal line at top)
            Rectangle()
                .fill(Color.budsPrimary)
                .frame(width: 40, height: 3)
                .offset(y: -18)

            // Buds inside (leaf icon)
            Image(systemName: "leaf.fill")
                .font(.system(size: 20))
                .foregroundColor(.budsPrimary.opacity(0.6))
                .offset(y: 4)

            // Solo vs Shared indicator (small badge)
            if !jar.isSolo {
                Circle()
                    .fill(Color.budsSuccess)
                    .frame(width: 16, height: 16)
                    .overlay(
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.white)
                    )
                    .offset(x: 18, y: -18)
            }
        }
        .frame(width: 50, height: 50)
    }

    private func loadCounts() async {
        do {
            let members = try await JarRepository.shared.getMembers(jarID: jar.id)
            let buds = try await MemoryRepository().fetchByJar(jarID: jar.id)

            await MainActor.run {
                memberCount = members.count
                budCount = buds.count
            }
        } catch {
            print("❌ Failed to load jar counts: \(error)")
        }
    }
}
