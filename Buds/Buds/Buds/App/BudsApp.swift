//
//  BudsApp.swift
//  Buds
//
//  Created on 12/16/25.
//

import SwiftUI
import FirebaseCore
import FirebaseAuth
import BackgroundTasks

// Configure Firebase BEFORE anything else (including @StateObject initialization)
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        print("🔧 [DEBUG] AppDelegate didFinishLaunchingWithOptions called")
        FirebaseConfiguration.configureFirebase()

        // Register for remote notifications (required for Phone Auth + silent push)
        print("🔧 [DEBUG] Registering for remote notifications...")
        application.registerForRemoteNotifications()

        // Register background tasks for inbox polling
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "app.getbuds.buds.inbox-poll",
            using: nil
        ) { task in
            self.handleInboxPoll(task: task as! BGAppRefreshTask)
        }

        // Schedule initial background poll
        scheduleBackgroundPoll()

        return true
    }

    // MARK: - APNs Token Handling (Required for Phone Auth + Push Notifications)

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("📲 APNs token: \(token)")

        // Forward to Firebase Auth (required for phone verification)
        Auth.auth().setAPNSToken(deviceToken, type: .unknown)

        // Upload to relay server for push notifications
        Task {
            do {
                try await DeviceManager.shared.updateAPNsToken(token)
                print("✅ APNs token uploaded to relay")
            } catch {
                print("❌ Failed to upload APNs token: \(error)")
            }
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ [ERROR] Failed to register for remote notifications: \(error)")
        print("⚠️ Phone Auth may not work without APNs")
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification notification: [AnyHashable : Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        print("📲 Silent push received")

        // Forward to Firebase Auth for phone verification
        if Auth.auth().canHandleNotification(notification) {
            print("🔧 [DEBUG] Notification handled by Firebase Auth")
            completionHandler(.noData)
            return
        }

        // Check if this is an inbox notification
        if notification["inbox"] != nil {
            print("📬 Inbox notification received, triggering poll")

            // Trigger immediate inbox poll
            Task {
                do {
                    try await InboxManager.shared.pollInbox()
                    completionHandler(.newData)
                } catch {
                    print("❌ Inbox poll after push failed: \(error)")
                    completionHandler(.failed)
                }
            }
            return
        }

        print("🔧 [DEBUG] Notification not handled")
        completionHandler(.noData)
    }

    // MARK: - Background Task Handling

    func handleInboxPoll(task: BGAppRefreshTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        Task {
            do {
                try await InboxManager.shared.pollInbox()
                task.setTaskCompleted(success: true)
            } catch {
                print("❌ Background inbox poll failed: \(error)")
                task.setTaskCompleted(success: false)
            }

            // Schedule next background poll
            scheduleBackgroundPoll()
        }
    }

    func scheduleBackgroundPoll() {
        let request = BGAppRefreshTaskRequest(identifier: "app.getbuds.buds.inbox-poll")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes

        do {
            try BGTaskScheduler.shared.submit(request)
            print("✅ Background poll scheduled")
        } catch {
            print("❌ Failed to schedule background poll: \(error)")
        }
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Re-schedule background poll when app backgrounds
        scheduleBackgroundPoll()
    }
}

@main
struct BudsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authManager = AuthManager.shared
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "onboarding_completed")  // Phase 10.1 Module 3.1

    init() {
        print("🔧 [DEBUG] BudsApp init started")

        // Initialize database (ensures migrations run)
        _ = Database.shared

        print("🌿 Buds initialized")
        print("🔧 [DEBUG] BudsApp init completed")
    }

    var body: some Scene {
        WindowGroup {
            if authManager.isAuthenticated {
                ZStack {
                    MainTabView()
                        .task {
                            // Register device on first authenticated launch
                            if !DeviceManager.shared.isRegistered {
                                do {
                                    try await DeviceManager.shared.registerDevice()
                                } catch {
                                    print("❌ Device registration failed: \(error)")
                                }
                            }

                            // Ensure Solo jar exists (critical for fresh installs)
                            do {
                                try await JarManager.shared.ensureSoloJarExists()
                            } catch {
                                print("❌ Failed to ensure Solo jar: \(error)")
                            }
                        }

                    // Phase 10.1 Module 3.1: Onboarding overlay
                    if showOnboarding {
                        OnboardingView(isPresented: $showOnboarding)
                            .transition(.opacity)
                    }
                }
            } else {
                PhoneAuthView()
            }
        }
    }

}

// MARK: - Firebase Configuration
struct FirebaseConfiguration {
    static func configureFirebase() {
        print("🔧 [DEBUG] FirebaseConfiguration.configureFirebase() called")

        // Check if GoogleService-Info.plist exists
        let plistPath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist")
        print("🔧 [DEBUG] GoogleService-Info.plist path: \(plistPath ?? "nil")")

        guard let path = plistPath else {
            print("⚠️ Firebase not configured (GoogleService-Info.plist not found)")
            print("ℹ️ App will work without Firebase for local testing")
            return
        }

        // Read and verify plist contents
        if let plistDict = NSDictionary(contentsOfFile: path) as? [String: Any] {
            print("🔧 [DEBUG] GoogleService-Info.plist contents:")
            print("🔧 [DEBUG]   - BUNDLE_ID: \(plistDict["BUNDLE_ID"] ?? "nil")")
            print("🔧 [DEBUG]   - CLIENT_ID: \(plistDict["CLIENT_ID"] ?? "nil")")
            print("🔧 [DEBUG]   - REVERSED_CLIENT_ID: \(plistDict["REVERSED_CLIENT_ID"] ?? "nil")")
            print("🔧 [DEBUG]   - API_KEY: \(plistDict["API_KEY"] ?? "nil")")
            print("🔧 [DEBUG]   - PROJECT_ID: \(plistDict["PROJECT_ID"] ?? "nil")")
            print("🔧 [DEBUG]   - GOOGLE_APP_ID: \(plistDict["GOOGLE_APP_ID"] ?? "nil")")
        }

        // Check Info.plist for URL schemes
        if let urlTypes = Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] {
            print("🔧 [DEBUG] Info.plist URL schemes found: \(urlTypes.count)")
            for (index, urlType) in urlTypes.enumerated() {
                if let schemes = urlType["CFBundleURLSchemes"] as? [String] {
                    print("🔧 [DEBUG]   URL Type \(index): \(schemes)")
                }
            }
        } else {
            print("⚠️ [WARNING] No URL schemes found in Info.plist - Phone Auth may fail!")
        }

        // Check if Firebase is already configured
        let existingApp = FirebaseApp.app()
        print("🔧 [DEBUG] Existing FirebaseApp: \(existingApp != nil ? "exists" : "nil")")

        if existingApp == nil {
            print("🔧 [DEBUG] Calling FirebaseApp.configure()...")
            FirebaseApp.configure()
            print("🔧 [DEBUG] FirebaseApp.configure() completed")

            // Verify configuration
            let configuredApp = FirebaseApp.app()
            print("🔧 [DEBUG] FirebaseApp after configure: \(configuredApp != nil ? "configured ✅" : "still nil ❌")")

            // Check Auth specifically
            let authInstance = Auth.auth()
            print("🔧 [DEBUG] Auth.auth() instance: \(authInstance)")
            print("🔧 [DEBUG] Auth.auth().app.name: \(authInstance.app?.name ?? "nil")")
            print("🔧 [DEBUG] Auth.auth().app.options.projectID: \(authInstance.app?.options.projectID ?? "nil")")
            print("🔧 [DEBUG] Auth.auth().app.options.clientID: \(authInstance.app?.options.clientID ?? "nil")")
            print("🔧 [DEBUG] Auth.auth().app.options.apiKey: \(authInstance.app?.options.apiKey ?? "nil")")
            print("🔧 [DEBUG] Auth.auth().app.options.bundleID: \(authInstance.app?.options.bundleID ?? "nil")")
            print("✅ Firebase configured successfully")
        } else {
            print("🔧 [DEBUG] Firebase already configured, skipping")
        }
    }
}
