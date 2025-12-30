//
//  ProfileView.swift
//  Buds
//
//  User profile and account settings
//

import SwiftUI
import FirebaseAuth

struct ProfileView: View {
    @StateObject private var authManager = AuthManager.shared
    @State private var userDID: String?
    @State private var displayName: String = ""
    @State private var isEditingName = false
    @State private var showingSignOutAlert = false
    @State private var showingDeleteAlert = false
    @State private var isDeleting = false
    @State private var databaseSize: String = "Calculating..."
    @State private var showingResetAlert = false
    @State private var isResetting = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Profile header
                    profileHeader

                    // Display name
                    displayNameSection

                    // Identity section
                    identitySection

                    // Storage section
                    storageSection

                    // Account settings
                    accountSettingsSection

                    // App info
                    appInfoSection

                    // Privacy & Legal
                    privacyLegalSection

                    // Debug section (Phase 10 testing)
                    debugSection

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .background(Color.black)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await loadUserData()
            }
            .alert("Sign Out", isPresented: $showingSignOutAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) {
                    signOut()
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .alert("Delete Account", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    deleteAccount()
                }
            } message: {
                Text("This will permanently delete your account and all data. This action cannot be undone.")
            }
            .alert("Reset All Data", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    resetAllData()
                }
            } message: {
                Text("This will delete all local data (database, keychain, settings). The app will need to be restarted. This is for testing only.")
            }
        }
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: 16) {
            // Avatar with camera icon
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.budsPrimary.opacity(0.3), Color.budsPrimary.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .overlay(
                        Text("🌿")
                            .font(.system(size: 50))
                    )

                // Camera icon overlay
                Circle()
                    .fill(Color.budsPrimary)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "camera.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                    )
                    .offset(x: -4, y: -4)
            }

            // Phone number (from Firebase Auth)
            if let phoneNumber = authManager.currentUser?.phoneNumber {
                Text(phoneNumber)
                    .font(.budsHeadline)
                    .foregroundColor(.budsText)
            }

            // Member since
            if let creationDate = authManager.currentUser?.metadata.creationDate {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12))
                    Text("Member since \(creationDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.budsCaption)
                }
                .foregroundColor(.budsTextSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Display Name Section

    private var displayNameSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Display Name")
                    .font(.budsCaption)
                    .foregroundColor(.budsTextSecondary)
                    .textCase(.uppercase)

                Spacer()

                Button(action: {
                    isEditingName.toggle()
                }) {
                    Text(isEditingName ? "Done" : "Edit")
                        .font(.budsCaption)
                        .foregroundColor(.budsPrimary)
                }
            }
            .padding(.horizontal, 4)

            HStack {
                if isEditingName {
                    TextField("Enter your name", text: $displayName, onCommit: {
                        saveDisplayName()
                        isEditingName = false
                    })
                    .font(.budsBody)
                    .foregroundStyle(.black)
                    .textFieldStyle(.plain)
                } else {
                    Text(displayName.isEmpty ? "Tap Edit to add your name" : displayName)
                        .font(.budsBody)
                        .foregroundColor(displayName.isEmpty ? .budsTextSecondary : .budsText)
                }
            }
            .padding()
            .background(Color.budsCard)
            .cornerRadius(12)
        }
    }

    // MARK: - Identity Section

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Identity", icon: "key.fill")

            VStack(spacing: 12) {
                // DID (cryptographic identity)
                IdentityRow(
                    title: "DID",
                    value: userDID ?? "Loading...",
                    icon: "key.fill"
                )

                Divider()
                    .padding(.leading, 36)

                // Firebase UID (auth only)
                if let uid = authManager.currentUser?.uid {
                    IdentityRow(
                        title: "Firebase UID",
                        value: uid,
                        icon: "person.badge.shield.checkmark.fill"
                    )
                }
            }
            .padding()
            .background(Color.budsCard)
            .cornerRadius(12)

            Text("Your DID is derived from your cryptographic keys and is used to sign all receipts. Your phone number is only used for authentication.")
                .font(.budsCaption)
                .foregroundColor(.budsTextSecondary)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Storage Section

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Storage", icon: "internaldrive.fill")

            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "cylinder.fill")
                        .foregroundColor(.budsPrimary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Database Size")
                            .font(.budsBody)
                            .foregroundColor(.budsText)

                        Text(databaseSize)
                            .font(.budsCaption)
                            .foregroundColor(.budsTextSecondary)
                    }

                    Spacer()
                }
                .padding()
            }
            .background(Color.budsCard)
            .cornerRadius(12)
        }
    }

    // MARK: - Account Settings

    private var accountSettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Account", icon: "person.circle.fill")

            VStack(spacing: 0) {
                // Sign out
                SettingButton(
                    title: "Sign Out",
                    icon: "rectangle.portrait.and.arrow.right",
                    color: .budsPrimary
                ) {
                    showingSignOutAlert = true
                }

                Divider()
                    .padding(.leading, 44)

                // Delete account
                SettingButton(
                    title: "Delete Account",
                    icon: "trash",
                    color: .budsDanger
                ) {
                    showingDeleteAlert = true
                }
            }
            .background(Color.budsCard)
            .cornerRadius(12)
        }
    }

    // MARK: - App Info Section

    private var appInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "About", icon: "info.circle.fill")

            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "app.badge")
                        .foregroundColor(.budsPrimary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Version")
                            .font(.budsCaption)
                            .foregroundColor(.budsTextSecondary)

                        Text("\(appVersion) (\(appBuild))")
                            .font(.budsBody)
                            .foregroundColor(.budsText)
                    }

                    Spacer()
                }
                .padding()
            }
            .background(Color.budsCard)
            .cornerRadius(12)

            Text("Buds v0.1 - Private cannabis memory sharing for you and your circle. Built on ChaingeOS principles.")
                .font(.budsCaption)
                .foregroundColor(.budsTextSecondary)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Privacy & Legal Section

    private var privacyLegalSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Privacy & Legal", icon: "hand.raised.fill")

            VStack(spacing: 0) {
                Link(destination: URL(string: "https://getbuds.app/privacy")!) {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.budsPrimary)
                            .frame(width: 24)

                        Text("Privacy Policy")
                            .font(.budsBody)
                            .foregroundColor(.budsText)

                        Spacer()

                        Image(systemName: "arrow.up.right")
                            .foregroundColor(.budsTextSecondary)
                            .font(.system(size: 14))
                    }
                    .padding()
                }

                Divider()
                    .padding(.leading, 44)

                Link(destination: URL(string: "https://getbuds.app/terms")!) {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.text.fill")
                            .foregroundColor(.budsPrimary)
                            .frame(width: 24)

                        Text("Terms of Service")
                            .font(.budsBody)
                            .foregroundColor(.budsText)

                        Spacer()

                        Image(systemName: "arrow.up.right")
                            .foregroundColor(.budsTextSecondary)
                            .font(.system(size: 14))
                    }
                    .padding()
                }
            }
            .background(Color.budsCard)
            .cornerRadius(12)
        }
    }

    // MARK: - Debug Section (Phase 10 Testing)

    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Debug & Testing", icon: "wrench.and.screwdriver.fill")

            VStack(spacing: 12) {
                // E2EE Verification Test
                NavigationLink(destination: E2EETestView()) {
                    HStack {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundColor(.orange)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("E2EE Verification Test")
                                .font(.budsBody)
                                .foregroundColor(.budsText)

                            Text("Critical test for TestFlight readiness")
                                .font(.budsCaption)
                                .foregroundColor(.budsTextSecondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.budsCard)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)

                // Stress Test (Module 5 - uncomment after adding StressTestView to Xcode)
                /*
                NavigationLink(destination: StressTestView()) {
                    HStack {
                        Image(systemName: "chart.bar.fill")
                            .foregroundColor(.budsPrimary)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Stress Test")
                                .font(.budsBody)
                                .foregroundColor(.budsText)

                            Text("Generate 100+ test buds for performance testing")
                                .font(.budsCaption)
                                .foregroundColor(.budsTextSecondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.budsCard)
                    .cornerRadius(12)
                }
                */

                // Reset All Data
                Button {
                    showingResetAlert = true
                } label: {
                    HStack {
                        Image(systemName: "trash.circle.fill")
                            .foregroundColor(.red)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Reset All Data")
                                .font(.budsBody)
                                .foregroundColor(.red)

                            Text("Delete database, keychain, and settings")
                                .font(.budsCaption)
                                .foregroundColor(.budsTextSecondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.budsCard)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .disabled(isResetting)
            }

            Text("⚠️ Run E2EE test before TestFlight upload")
                .font(.budsCaption)
                .foregroundColor(.orange)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Computed Properties

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    // MARK: - Actions

    private func loadUserData() async {
        // Load DID
        do {
            let did = try await IdentityManager.shared.getDID()
            await MainActor.run {
                userDID = did
            }
        } catch {
            print("❌ Failed to load DID: \(error)")
        }

        // Load display name
        if let savedName = UserDefaults.standard.string(forKey: "user_display_name") {
            await MainActor.run {
                displayName = savedName
            }
        }

        // Calculate database size
        let dbPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("buds.sqlite")

        if let fileSize = try? FileManager.default.attributesOfItem(atPath: dbPath.path)[.size] as? Int64 {
            let sizeInMB = Double(fileSize) / 1_048_576 // Convert to MB
            await MainActor.run {
                databaseSize = String(format: "%.2f MB", sizeInMB)
            }
        }
    }

    private func saveDisplayName() {
        UserDefaults.standard.set(displayName, forKey: "user_display_name")
    }

    private func signOut() {
        do {
            try authManager.signOut()
        } catch {
            print("❌ Sign out failed: \(error)")
        }
    }

    private func deleteAccount() {
        isDeleting = true

        Task {
            do {
                try await authManager.deleteAccount()
            } catch {
                print("❌ Delete account failed: \(error)")
            }
            isDeleting = false
        }
    }

    private func resetAllData() {
        isResetting = true

        Task {
            do {
                try await DataResetUtility.resetAllData()
                // Note: App needs to be restarted for changes to take effect
            } catch {
                print("❌ Reset all data failed: \(error)")
            }
            isResetting = false
        }
    }
}

// MARK: - Section Header Component

struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.budsPrimary)

            Text(title)
                .font(.budsHeadline)
                .foregroundColor(.budsText)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Identity Row Component

struct IdentityRow: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.budsPrimary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.budsCaption)
                    .foregroundColor(.budsTextSecondary)

                Text(value)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.budsText)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: {
                UIPasteboard.general.string = value
            }) {
                Image(systemName: "doc.on.doc")
                    .foregroundColor(.budsPrimary)
                    .font(.system(size: 16))
            }
        }
    }
}

// MARK: - Setting Button Component

struct SettingButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .frame(width: 24)

                Text(title)
                    .font(.budsBody)
                    .foregroundColor(color)

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.budsTextSecondary)
                    .font(.system(size: 14))
            }
            .padding()
        }
    }
}

#Preview {
    ProfileView()
}
