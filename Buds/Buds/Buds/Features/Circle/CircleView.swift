//
//  CircleView.swift
//  Buds
//
//  Jar management screen (Phase 9: Rebuilt as jar list)
//

import SwiftUI

struct CircleView: View {
    @StateObject private var jarManager = JarManager.shared
    @State private var showingCreateJar = false
    @State private var selectedJar: Jar?

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                if jarManager.isLoading {
                    ProgressView("Loading jars...")
                        .tint(.budsPrimary)
                } else if jarManager.jars.isEmpty {
                    emptyState
                } else {
                    jarList
                }
            }
            .navigationTitle("Jars")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreateJar = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.budsPrimary)
                    }
                }
            }
            .sheet(isPresented: $showingCreateJar, onDismiss: {
                Task { await jarManager.loadJars() }
            }) {
                CreateJarView()
            }
            .task {
                await jarManager.loadJars()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 80))
                .foregroundColor(.budsPrimary.opacity(0.3))

            VStack(spacing: 12) {
                Text("No Jars Yet")
                    .font(.budsTitle)
                    .foregroundColor(.white)

                Text("Create jars to organize your buds and share with specific groups.")
                    .font(.budsBody)
                    .foregroundColor(.budsTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                showingCreateJar = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle")
                    Text("Create Jar")
                }
                .font(.budsBodyBold)
                .foregroundColor(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .background(Color.budsPrimary)
                .cornerRadius(12)
            }
        }
        .padding()
    }

    // MARK: - Jar List

    private var jarList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(jarManager.jars) { jar in
                    NavigationLink(destination: JarDetailView(jar: jar)) {
                        JarCard(jar: jar)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }
}

#Preview {
    CircleView()
}
