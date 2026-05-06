import SwiftUI
import ForgeDomain

struct StackView: View {
    @Environment(WorkspaceController.self) var controller
    @Environment(AttentionManager.self) var attention
    @State private var isFullScreen = false

    private var toolbarPosition: String {
        ForgeConfigStore.shared.config.stackView?.toolbarPosition ?? "bottom"
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isFullScreen {
                // Titlebar spacer (same as SessionDetailView)
                ZStack {
                    ForgeConfigStore.shared.resolvedTheme?.background ?? Color(nsColor: .windowBackgroundColor)
                    Color.white.opacity(0.06)
                }
                .frame(height: ForgeConfigStore.shared.titlebarHeight)
            }

            if let uuid = attention.currentWindowUUID,
               let (session, window) = controller.workspace.findWindow(byUUID: uuid) {
                // Show terminal + toolbar
                if toolbarPosition == "top" {
                    StackToolbar(session: session, window: window)
                    TerminalArea(session: session)
                } else {
                    TerminalArea(session: session)
                    StackToolbar(session: session, window: window)
                }
            } else if let staleUUID = attention.currentWindowUUID {
                // UUID in queue but window no longer exists — self-heal
                let _ = { attention.removeWindow(staleUUID) }()
                StackEmptyState()
            } else {
                // Nothing in queue
                StackEmptyState()
            }
        }
        .onChange(of: attention.currentWindowUUID) { _, newUUID in
            // When the queue front changes, tell tmux to show the new window
            if let uuid = newUUID,
               let (_, window) = controller.workspace.findWindow(byUUID: uuid) {
                controller.selectWindow(window)
            }
        }
        .toolbar(.hidden, for: .automatic)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) { _ in
            isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullScreen = false
        }
    }
}
