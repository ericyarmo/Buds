//
//  AuthManager.swift
//  Buds
//
//  Created by Eric Yarmolinsky on 12/18/25.
//
//
//  Manages Firebase Authentication (phone verification)
//  Firebase UID is separate from DID (cryptographic identity)
//

import Foundation
import Combine
import FirebaseCore
import FirebaseAuth

@MainActor
class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var verificationID: String?

    private init() {
        print("🔧 [DEBUG] AuthManager init started")

        // Check if Auth is available
        let authInstance = Auth.auth()
        print("🔧 [DEBUG] Auth.auth() in AuthManager init: \(authInstance)")

        self.currentUser = authInstance.currentUser
        self.isAuthenticated = currentUser != nil
        print("🔧 [DEBUG] Initial auth state - currentUser: \(currentUser?.uid ?? "nil"), isAuthenticated: \(isAuthenticated)")

        // Listen for auth state changes
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUser = user
                self?.isAuthenticated = user != nil

                if let user = user {
                    print("✅ User authenticated: \(user.uid)")
                    // Map Firebase UID to DID
                    Task {
                        await self?.syncFirebaseUIDtoDID()
                    }
                } else {
                    print("⚠️ User signed out")
                }
            }
        }

        print("🔧 [DEBUG] AuthManager init completed")
    }

    // MARK: - Phone Authentication

    /// Send verification code to phone number
    func sendVerificationCode(phoneNumber: String) async throws {
        print("🔧 [DEBUG] sendVerificationCode called with: \(phoneNumber)")

        // Check Firebase Auth state
        let authInstance = Auth.auth()
        print("🔧 [DEBUG] Auth.auth() instance: \(authInstance)")
        print("🔧 [DEBUG] Auth.auth().app: \(authInstance.app)")

        // Check app options
        if let app = authInstance.app {
            print("🔧 [DEBUG] App name: \(app.name)")
            print("🔧 [DEBUG] App options:")
            print("🔧 [DEBUG]   - projectID: \(app.options.projectID ?? "nil")")
            print("🔧 [DEBUG]   - clientID: \(app.options.clientID ?? "nil")")
            print("🔧 [DEBUG]   - apiKey: \(app.options.apiKey ?? "nil")")
            print("🔧 [DEBUG]   - bundleID: \(app.options.bundleID ?? "nil")")
            print("🔧 [DEBUG]   - googleAppID: \(app.options.googleAppID ?? "nil")")
        }

        do {
            print("🔧 [DEBUG] Creating PhoneAuthProvider with explicit Auth instance...")
            let provider = PhoneAuthProvider.provider(auth: authInstance)
            print("🔧 [DEBUG] PhoneAuthProvider created: \(provider)")

            print("🔧 [DEBUG] Calling verifyPhoneNumber...")
            let verificationID = try await provider.verifyPhoneNumber(phoneNumber, uiDelegate: nil)

            self.verificationID = verificationID
            print("✅ Verification code sent to \(phoneNumber)")
            print("🔧 [DEBUG] Verification ID: \(verificationID)")
        } catch {
            print("❌ Failed to send verification code: \(error)")
            print("🔧 [DEBUG] Error type: \(type(of: error))")
            print("🔧 [DEBUG] Error details: \(error)")
            if let nsError = error as NSError? {
                print("🔧 [DEBUG] Error domain: \(nsError.domain)")
                print("🔧 [DEBUG] Error code: \(nsError.code)")
                print("🔧 [DEBUG] Error userInfo: \(nsError.userInfo)")
            }
            throw AuthError.verificationFailed(error.localizedDescription)
        }
    }

    /// Verify the SMS code
    func verifyCode(_ code: String) async throws {
        guard let verificationID = verificationID else {
            throw AuthError.noVerificationID
        }

        do {
            let credential = PhoneAuthProvider.provider().credential(
                withVerificationID: verificationID,
                verificationCode: code
            )

            let result = try await Auth.auth().signIn(with: credential)
            print("✅ User signed in: \(result.user.uid)")

            // Sync Firebase UID to DID mapping
            await syncFirebaseUIDtoDID()
        } catch {
            print("❌ Failed to verify code: \(error)")
            throw AuthError.invalidVerificationCode
        }
    }

    // MARK: - Sign Out

    func signOut() throws {
        do {
            try Auth.auth().signOut()
            print("✅ User signed out")
        } catch {
            print("❌ Sign out failed: \(error)")
            throw AuthError.signOutFailed
        }
    }

    // MARK: - Delete Account

    func deleteAccount() async throws {
        guard let user = currentUser else {
            throw AuthError.noUser
        }

        do {
            try await user.delete()
            print("✅ Account deleted")
        } catch {
            print("❌ Failed to delete account: \(error)")
            throw AuthError.deleteFailed(error.localizedDescription)
        }
    }

    // MARK: - Firebase UID → DID Mapping

    /// Sync Firebase UID to DID mapping (for device discovery)
    /// This will be stored in the relay server for Circle invitation lookups
    private func syncFirebaseUIDtoDID() async {
        guard let firebaseUID = currentUser?.uid else { return }

        do {
            let did = try await IdentityManager.shared.getDID()

            // TODO: Send to relay server
            // POST /api/v1/identity/register
            // { "firebase_uid": firebaseUID, "did": did }

            print("✅ Firebase UID → DID mapping: \(firebaseUID) → \(did)")

            // For now, just store locally
            UserDefaults.standard.set(firebaseUID, forKey: "firebase_uid")
            UserDefaults.standard.set(did, forKey: "user_did")
        } catch {
            print("❌ Failed to sync UID → DID: \(error)")
        }
    }
}

// MARK: - Auth Errors

enum AuthError: Error, LocalizedError {
    case verificationFailed(String)
    case noVerificationID
    case invalidVerificationCode
    case signOutFailed
    case noUser
    case deleteFailed(String)

    var errorDescription: String? {
        switch self {
        case .verificationFailed(let message):
            return "Failed to send verification code: \(message)"
        case .noVerificationID:
            return "No verification ID found. Please request a new code."
        case .invalidVerificationCode:
            return "Invalid verification code. Please try again."
        case .signOutFailed:
            return "Failed to sign out"
        case .noUser:
            return "No user is currently signed in"
        case .deleteFailed(let message):
            return "Failed to delete account: \(message)"
        }
    }
}
