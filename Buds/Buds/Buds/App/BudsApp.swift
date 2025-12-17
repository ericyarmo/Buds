//
//  BudsApp.swift
//  Buds
//
//  Created on 12/16/25.
//

import SwiftUI
import FirebaseCore

@main
struct BudsApp: App {

    init() {
        // Initialize Firebase
        FirebaseApp.configure()

        // Initialize database (ensures migrations run)
        _ = Database.shared

        print("🌿 Buds initialized")
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}
