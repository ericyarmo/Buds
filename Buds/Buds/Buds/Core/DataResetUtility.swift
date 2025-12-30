//
//  DataResetUtility.swift
//  Buds
//
//  Utility to completely reset all user data (for testing/fresh start)
//

import Foundation
import FirebaseAuth

enum DataResetUtility {
    /// Completely wipe all user data and start fresh
    /// WARNING: This is irreversible!
    static func resetAllData() async throws {
        print("🔥 [RESET] Starting complete data reset...")

        // 1. Sign out from Firebase Auth
        do {
            try Auth.auth().signOut()
            print("✅ [RESET] Signed out from Firebase")
        } catch {
            print("⚠️ [RESET] Firebase sign out failed: \(error)")
        }

        // 2. Delete GRDB database file
        let fileManager = FileManager.default
        do {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dbPath = appSupport.appendingPathComponent("buds.sqlite")

            if fileManager.fileExists(atPath: dbPath.path) {
                try fileManager.removeItem(at: dbPath)
                print("✅ [RESET] Deleted database at: \(dbPath.path)")
            }

            // Also delete WAL and SHM files if they exist
            let walPath = appSupport.appendingPathComponent("buds.sqlite-wal")
            if fileManager.fileExists(atPath: walPath.path) {
                try fileManager.removeItem(at: walPath)
                print("✅ [RESET] Deleted WAL file")
            }

            let shmPath = appSupport.appendingPathComponent("buds.sqlite-shm")
            if fileManager.fileExists(atPath: shmPath.path) {
                try fileManager.removeItem(at: shmPath)
                print("✅ [RESET] Deleted SHM file")
            }
        } catch {
            print("⚠️ [RESET] Failed to delete database: \(error)")
        }

        // 3. Reset identity (clear keychain)
        do {
            try await IdentityManager.shared.resetIdentity()
            print("✅ [RESET] Cleared keychain (identity keys)")
        } catch {
            print("⚠️ [RESET] Failed to reset identity: \(error)")
        }

        // 4. Clear UserDefaults
        let domain = Bundle.main.bundleIdentifier!
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.synchronize()
        print("✅ [RESET] Cleared UserDefaults")

        print("🎉 [RESET] Complete data reset finished!")
        print("⚠️  [RESET] Restart the app to complete the reset process")
    }
}
