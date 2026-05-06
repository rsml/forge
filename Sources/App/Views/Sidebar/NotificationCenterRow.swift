import SwiftUI
import ForgeDomain

struct NotificationCenterRow: View {
    var position: String = "left"
    @Environment(WorkspaceController.self) var controller
    @State private var isFullScreen = false

    private var attentionCount: Int {
        controller.workspace.sessions.reduce(0) { total, session in
            total + session.windows.filter(\.needsAttention).count
        }
    }

    private var store: ForgeConfigStore { ForgeConfigStore.shared }

    private var iconName: String {
        store.isStackMode ? "list.bullet" : "square.stack.3d.up"
    }

    private var tooltipText: String {
        let shortcut = KeyboardShortcuts.toggleMode.hint
        return store.isStackMode
            ? "Toggle List Mode (\(shortcut))"
            : "Toggle Stack Mode (\(shortcut))"
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
            .overlay(alignment: .topTrailing) {
                if attentionCount > 0 {
                    Text("\(attentionCount)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(Color.red, in: Capsule())
                        .offset(x: 4, y: -2)
                }
            }
            .help(tooltipText)

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
