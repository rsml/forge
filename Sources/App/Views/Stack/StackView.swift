import SwiftUI
import ForgeDomain

struct StackView: View {
    @Environment(WorkspaceController.self) var controller
    @Environment(AttentionManager.self) var attention
    @State private var isFullScreen = false
    @State private var isDismissing = false
    @State private var pendingAction: WorkspaceController.StackDismissAction?

    private var toolbarPosition: String {
        ForgeConfigStore.shared.config.stackView?.toolbarPosition ?? "bottom"
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isFullScreen {
                ZStack {
                    ForgeConfigStore.shared.resolvedTheme?.background ?? Color(nsColor: .windowBackgroundColor)
                    Color.white.opacity(0.06)
                }
                .frame(height: ForgeConfigStore.shared.titlebarHeight)
            }

            if let uuid = attention.currentWindowUUID,
               let (session, window) = controller.workspace.findWindow(byUUID: uuid) {
                ZStack {
                    // Background layer: next item preview or empty state
                    backgroundLayer

                    // Foreground layer: current terminal + toolbar with animation
                    foregroundLayer(session: session, window: window)
                        .scaleEffect(isDismissing ? 0.85 : 1.0)
                        .offset(y: isDismissing ? -800 : 0)
                        .opacity(isDismissing ? 0.5 : 1.0)
                }
            } else if let staleUUID = attention.currentWindowUUID {
                let _ = { attention.removeWindow(staleUUID) }()
                StackEmptyState()
            } else {
                StackEmptyState()
            }
        }
        .onChange(of: attention.currentWindowUUID) { _, newUUID in
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
        .onReceive(NotificationCenter.default.publisher(for: .forgeStackDone)) { _ in
            handleDismiss(.done)
        }
        .onReceive(NotificationCenter.default.publisher(for: .forgeStackHide)) { _ in
            handleDismiss(.hide)
        }
        .onReceive(NotificationCenter.default.publisher(for: .forgeStackMoveToBack)) { _ in
            handleDismiss(.moveToBack)
        }
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        if let nextUUID = attention.nextWindowUUID,
           let (nextSession, nextWindow) = controller.workspace.findWindow(byUUID: nextUUID) {
            VStack(spacing: 0) {
                if toolbarPosition == "top" {
                    StackToolbar(session: nextSession, window: nextWindow)
                    Color(red: 0.1, green: 0.1, blue: 0.1)
                } else {
                    Color(red: 0.1, green: 0.1, blue: 0.1)
                    StackToolbar(session: nextSession, window: nextWindow)
                }
            }
        } else {
            StackEmptyState()
        }
    }

    @ViewBuilder
    private func foregroundLayer(session: Session, window: ForgeDomain.Window) -> some View {
        VStack(spacing: 0) {
            if toolbarPosition == "top" {
                StackToolbar(session: session, window: window, onDismiss: handleDismiss)
                TerminalArea(session: session)
            } else {
                TerminalArea(session: session)
                StackToolbar(session: session, window: window, onDismiss: handleDismiss)
            }
        }
    }

    private func handleDismiss(_ action: WorkspaceController.StackDismissAction) {
        guard !isDismissing else { return }
        pendingAction = action
        withAnimation(.easeIn(duration: 0.35)) {
            isDismissing = true
        } completion: {
            controller.stackDismiss(action)
            isDismissing = false
            pendingAction = nil
        }
    }
}
