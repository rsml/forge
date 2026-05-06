import SwiftUI

/// macOS-style notification banner that slides in from the top-right corner.
struct NotificationToast: View {
    let title: String
    let message: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 320)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    }
}

/// Manages showing/hiding notification toasts with animation.
@Observable @MainActor
final class NotificationToastState {

    private(set) var current: ToastItem?
    private var dismissTask: Task<Void, Never>?

    struct ToastItem: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let icon: String
    }

    func show(title: String, message: String, icon: String = "bell.fill", duration: TimeInterval = 4) {
        dismissTask?.cancel()
        withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
            current = ToastItem(title: title, message: message, icon: icon)
        }
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                current = nil
            }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.3)) {
            current = nil
        }
    }
}

/// Overlay modifier that shows notification toasts at the top-right of the window.
struct NotificationToastOverlay: ViewModifier {
    let state: NotificationToastState

    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            if let toast = state.current {
                NotificationToast(title: toast.title, message: toast.message, icon: toast.icon)
                    .padding(.top, 8)
                    .padding(.trailing, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { state.dismiss() }
                    .zIndex(100)
            }
        }
    }
}
