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

            CircleView()  // Keep for safer rollback (Phase 9b)
                .tabItem {
                    Label("Circle", systemImage: "person.2.fill")
                }
                .tag(1)

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
                .tag(2)
        }
        .tint(.budsPrimary)
    }
}

#Preview {
    MainTabView()
}
