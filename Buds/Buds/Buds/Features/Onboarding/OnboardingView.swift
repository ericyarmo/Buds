//
//  OnboardingView.swift
//  Buds
//
//  Created by Eric Yarmolinsky on 12/28/25.
//
//  Phase 10.1 Module 3.1: First-launch onboarding
//

import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool

    @State private var currentStep = 0
    private let totalSteps = 3

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // Current step content
                stepContent

                Spacer()

                // Pagination dots
                HStack(spacing: 8) {
                    ForEach(0..<totalSteps, id: \.self) { index in
                        Circle()
                            .fill(index == currentStep ? Color.budsPrimary : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }

                // Navigation buttons
                HStack(spacing: 16) {
                    if currentStep < totalSteps - 1 {
                        Button("Skip") {
                            completeOnboarding()
                        }
                        .foregroundColor(.budsTextSecondary)

                        Spacer()

                        Button("Next") {
                            withAnimation {
                                currentStep += 1
                            }
                        }
                        .font(.budsBodyBold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(Color.budsPrimary)
                        .cornerRadius(12)
                    } else {
                        Button("Get Started") {
                            completeOnboarding()
                        }
                        .font(.budsBodyBold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.budsPrimary)
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case 0:
            OnboardingStep(
                icon: "leaf.fill",
                title: "Welcome to Buds",
                description: "Track your cannabis journey with privacy-first memory keeping. Save strains, effects, and experiences."
            )
        case 1:
            OnboardingStep(
                icon: "square.stack.3d.up.fill",
                title: "Organize with Jars",
                description: "Buds live in jars. Keep a Solo jar for personal tracking, or create shared jars with friends."
            )
        case 2:
            OnboardingStep(
                icon: "lock.shield.fill",
                title: "Your Data is Private",
                description: "End-to-end encrypted. Your buds are yours. We can't read them, and nobody else can either."
            )
        default:
            EmptyView()
        }
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboarding_completed")
        withAnimation {
            isPresented = false
        }
    }
}

// MARK: - Onboarding Step Component

struct OnboardingStep: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: icon)
                .font(.system(size: 80))
                .foregroundColor(.budsPrimary)

            VStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                Text(description)
                    .font(.budsBody)
                    .foregroundColor(.budsTextSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 40)
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView(isPresented: .constant(true))
}
