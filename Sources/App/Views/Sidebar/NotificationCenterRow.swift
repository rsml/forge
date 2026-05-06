import SwiftUI
import ForgeDomain

struct NotificationCenterRow: View {
    var position: String = "left"
    @State private var isFullScreen = false

    private var store: ForgeConfigStore { ForgeConfigStore.shared }

    private var iconName: String {
        store.isStackMode ? "list.bullet" : "rectangle.stack"
    }

    private var modeLabel: String {
        store.isStackMode ? "Switch to List Mode" : "Switch to Stack Mode"
    }

    /// Center the icon unless: NOT fullscreen AND sidebar is left-aligned.
    /// In that case, push it right to avoid overlapping traffic lights.
    private var shouldCenter: Bool {
        if isFullScreen { return true }
        if position == "left" { return false }
        return true
    }

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            Button {
                NotificationCenter.default.post(name: .forgeToggleMode, object: nil)
            } label: {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tooltip(modeLabel, shortcut: KeyboardShortcuts.toggleMode)

            if shouldCenter {
                Spacer(minLength: 0)
            }
        }
        .frame(height: store.titlebarHeight)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) { _ in
            isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullScreen = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .forgeToggleMode)) { _ in
            // Handled by AppDelegate, which has access to AttentionManager.
        }
    }
}
