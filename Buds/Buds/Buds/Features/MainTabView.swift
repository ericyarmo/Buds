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
            TimelineView()
                .tabItem {
                    Label("Timeline", systemImage: "book.fill")
                }
                .tag(0)

            Text("Map (Coming Soon)")
                .font(.budsHeadline)
                .tabItem {
                    Label("Map", systemImage: "map.fill")
                }
                .tag(1)

            Text("Circle (Coming Soon)")
                .font(.budsHeadline)
                .tabItem {
                    Label("Circle", systemImage: "person.2.fill")
                }
                .tag(2)

            Text("Profile (Coming Soon)")
                .font(.budsHeadline)
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
                .tag(3)
        }
        .tint(.budsPrimary)
    }
}

#Preview {
    MainTabView()
}
