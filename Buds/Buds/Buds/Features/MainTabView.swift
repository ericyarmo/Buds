//
//  MainTabView.swift
//  Buds
//
//  Main tab navigation
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ShelfView()
                .tabItem {
                    Label("Shelf", systemImage: "square.stack.3d.up.fill")
                }
                .tag(0)

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
                .tag(1)
        }
        .tint(.budsPrimary)
        .task {
            // Phase 10.2: Start foreground polling for shared buds
            await InboxManager.shared.startForegroundPolling()
            print("📬 Started inbox polling (30s interval)")
        }
        .onDisappear {
            // Stop polling when user logs out
            Task {
                await InboxManager.shared.stopForegroundPolling()
                print("📭 Stopped inbox polling")
            }
        }
    }
}

#Preview {
    MainTabView()
}
