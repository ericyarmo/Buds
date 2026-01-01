//
//  MainTabView.swift
//  Buds
//
//  Main tab navigation
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var toast: Toast?  // Phase 10.3 Module 0.4: Toast notifications

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
        // Phase 10.3 Module 0.4: Listen for new device detection
        .onReceive(NotificationCenter.default.publisher(for: .newDeviceDetected)) { notification in
            if let did = notification.userInfo?["did"] as? String,
               let deviceId = notification.userInfo?["deviceId"] as? String {
                print("⚠️  [MainTabView] New device detected: \(deviceId) (DID: \(did))")

                toast = Toast(
                    message: "New device detected. Verify safety number if this wasn't you.",
                    style: .info,
                    duration: 5.0  // Longer duration for security warning
                )
            }
        }
        .toast($toast)  // Add toast modifier
    }
}

#Preview {
    MainTabView()
}
