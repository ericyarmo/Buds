//
//  Toast.swift
//  Buds
//
//  Phase 10 Step 5: Toast notification system
//

import SwiftUI

// MARK: - Toast Model

struct Toast: Equatable {
    enum Style {
        case success
        case error
        case info
    }

    let message: String
    let style: Style
    let duration: TimeInterval

    init(message: String, style: Style = .info, duration: TimeInterval = 2.0) {
        self.message = message
        self.style = style
        self.duration = duration
    }
}

// MARK: - Toast View

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .foregroundColor(iconColor)

            Text(toast.message)
                .font(.budsBody)
                .foregroundColor(.white)

            Spacer()
        }
        .padding()
        .background(backgroundColor)
        .cornerRadius(12)
        .shadow(radius: 8)
        .padding(.horizontal)
    }

    private var iconName: String {
        switch toast.style {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private var iconColor: Color {
        switch toast.style {
        case .success: return .budsSuccess
        case .error: return .budsDanger
        case .info: return .budsPrimary
        }
    }

    private var backgroundColor: Color {
        switch toast.style {
        case .success: return Color.budsSuccess.opacity(0.2)
        case .error: return Color.budsDanger.opacity(0.2)
        case .info: return Color.budsPrimary.opacity(0.2)
        }
    }
}

// MARK: - Toast Modifier

struct ToastModifier: ViewModifier {
    @Binding var toast: Toast?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast = toast {
                    ToastView(toast: toast)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + toast.duration) {
                                withAnimation {
                                    self.toast = nil
                                }
                            }
                        }
                        .padding(.top, 8)
                }
            }
    }
}

// MARK: - View Extension

extension View {
    func toast(_ toast: Binding<Toast?>) -> some View {
        modifier(ToastModifier(toast: toast))
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        ToastView(toast: Toast(message: "Jar created successfully!", style: .success))
        ToastView(toast: Toast(message: "Failed to delete jar", style: .error))
        ToastView(toast: Toast(message: "Loading...", style: .info))
    }
    .padding()
    .background(Color.black)
}
