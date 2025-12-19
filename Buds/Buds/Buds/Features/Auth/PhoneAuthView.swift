//
//  PhoneAuthView.swift
//  Buds
//
//  Phone number authentication flow
//

import SwiftUI

struct PhoneAuthView: View {
    @StateObject private var authManager = AuthManager.shared
    @State private var phoneNumber = ""
    @State private var verificationCode = ""
    @State private var isCodeSent = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 32) {
                // Logo / Header
                VStack(spacing: 12) {
                    Text("🌿")
                        .font(.system(size: 80))

                    Text("Welcome to Buds")
                        .font(.budsTitle)
                        .foregroundColor(.budsText)

                    Text("Private cannabis memories with friends")
                        .font(.budsBody)
                        .foregroundColor(.budsTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 60)

                Spacer()

                // Phone number or verification code input
                if !isCodeSent {
                    phoneNumberSection
                } else {
                    verificationCodeSection
                }

                // Error message
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.budsCaption)
                        .foregroundColor(.budsDanger)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()

                // Legal disclaimer
                Text("By continuing, you agree to our Terms of Service and Privacy Policy. 21+ only.")
                    .font(.budsCaption)
                    .foregroundColor(.budsTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 24)
            .navigationBarHidden(true)
        }
    }

    // MARK: - Phone Number Section

    private var phoneNumberSection: some View {
        VStack(spacing: 20) {
            Text("Enter your phone number")
                .font(.budsHeadline)
                .foregroundColor(.budsText)

            // Phone number input
            HStack {
                Text("+1")
                    .font(.budsBody)
                    .foregroundColor(.budsTextSecondary)

                TextField("(555) 123-4567", text: $phoneNumber)
                    .font(.budsBody)
                    .foregroundStyle(.black)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
            }
            .padding()
            .background(Color.budsCard)
            .cornerRadius(12)

            // Send code button
            Button(action: sendCode) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Text("Send Code")
                        .font(.budsBodyBold)
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(phoneNumber.isEmpty ? Color.budsTextSecondary : Color.budsPrimary)
            .cornerRadius(12)
            .disabled(phoneNumber.isEmpty || isLoading)
        }
    }

    // MARK: - Verification Code Section

    private var verificationCodeSection: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Enter verification code")
                    .font(.budsHeadline)
                    .foregroundColor(.budsText)

                Text("Sent to +1\(phoneNumber)")
                    .font(.budsCaption)
                    .foregroundColor(.budsTextSecondary)
            }

            // Verification code input
            TextField("123456", text: $verificationCode)
                .font(.budsBody)
                .foregroundStyle(.black)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .multilineTextAlignment(.center)
                .padding()
                .background(Color.budsCard)
                .cornerRadius(12)

            // Verify button
            Button(action: verifyCode) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Text("Verify")
                        .font(.budsBodyBold)
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(verificationCode.isEmpty ? Color.budsTextSecondary : Color.budsPrimary)
            .cornerRadius(12)
            .disabled(verificationCode.isEmpty || isLoading)

            // Resend code
            Button(action: {
                isCodeSent = false
                verificationCode = ""
                errorMessage = nil
            }) {
                Text("Use a different number")
                    .font(.budsCaption)
                    .foregroundColor(.budsPrimary)
            }
        }
    }

    // MARK: - Actions

    private func sendCode() {
        guard !phoneNumber.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        // Format phone number
        let formattedNumber = "+1" + phoneNumber.filter { $0.isNumber }

        Task {
            do {
                try await authManager.sendVerificationCode(phoneNumber: formattedNumber)
                isCodeSent = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func verifyCode() {
        guard !verificationCode.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await authManager.verifyCode(verificationCode)
                // Auth state change will automatically navigate to main app
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

#Preview {
    PhoneAuthView()
}
