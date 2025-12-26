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
            // Icon
            Image(systemName: jar.isSolo ? "person.fill" : "person.2.fill")
                .font(.title2)
                .foregroundColor(.budsPrimary)
                .frame(width: 50, height: 50)
                .background(Color.budsPrimary.opacity(0.2))
                .clipShape(Circle())

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
