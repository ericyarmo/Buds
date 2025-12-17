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
        // Initialize Firebase (optional for local testing)
        configureFirebaseIfAvailable()

        // Initialize database (ensures migrations run)
        _ = Database.shared

        print("🌿 Buds initialized")
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }

    // MARK: - Firebase Setup

    private func configureFirebaseIfAvailable() {
        // Check if GoogleService-Info.plist exists
        guard let _ = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") else {
            print("⚠️ Firebase not configured (GoogleService-Info.plist not found)")
            print("ℹ️ App will work without Firebase for local testing")
            return
        }

        do {
            FirebaseApp.configure()
            print("✅ Firebase configured")
        } catch {
            print("⚠️ Firebase configuration failed: \(error)")
            print("ℹ️ App will work without Firebase for local testing")
        }
    }
}
