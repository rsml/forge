import SwiftUI
import ForgeCore

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

            if let uuid = attention.currentTabUUID,
               let (project, tab) = controller.workspace.findTab(byUUID: uuid) {
                GeometryReader { geo in
                    ZStack {
                        // Background layer: next item card — visible through foreground padding
                        backgroundLayer
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .scaleEffect(isDismissing ? 1.0 : 0.96)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.black.opacity(isDismissing ? 0.0 : 0.3))
                                    .scaleEffect(isDismissing ? 1.0 : 0.96)
                            }

                        // Foreground layer: current terminal + toolbar
                        foregroundLayer(project: project, tab: tab)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(4)
                            .scaleEffect(isDismissing ? 0.92 : 1.0)
                            .offset(y: isDismissing ? -(geo.size.height + 100) : 0)
                            .shadow(color: .black.opacity(0.4), radius: 12, y: 3)
                    }
                }
            } else if let staleUUID = attention.currentTabUUID {
                let _ = { attention.removeTab(staleUUID) }()
                StackEmptyState()
            } else {
                StackEmptyState()
            }
        }
        .onChange(of: attention.currentTabUUID) { _, newUUID in
            if let uuid = newUUID,
               let (_, tab) = controller.workspace.findTab(byUUID: uuid) {
                controller.selectTab(tab)
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
           let (nextProject, nextTab) = controller.workspace.findTab(byUUID: nextUUID) {
            VStack(spacing: 0) {
                if toolbarPosition == "top" {
                    StackToolbar(project: nextProject, tab: nextTab)
                    terminalPlaceholder
                } else {
                    terminalPlaceholder
                    StackToolbar(project: nextProject, tab: nextTab)
                }
            }
            .allowsHitTesting(false)
        } else {
            StackEmptyState()
        }
    }

    /// Dark card backing for the background layer — avoids duplicate tmux sessions
    /// while giving the visual impression of a card behind the foreground.
    private var terminalPlaceholder: some View {
        (ForgeConfigStore.shared.resolvedTheme?.background ?? Color(red: 0.1, green: 0.1, blue: 0.1))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func foregroundLayer(project: Project, tab: ForgeCore.Tab) -> some View {
        VStack(spacing: 0) {
            if toolbarPosition == "top" {
                StackToolbar(project: project, tab: tab, onDismiss: handleDismiss)
                TerminalArea(project: project)
            } else {
                TerminalArea(project: project)
                StackToolbar(project: project, tab: tab, onDismiss: handleDismiss)
            }
        }
    }

    private func handleDismiss(_ action: WorkspaceController.StackDismissAction) {
        guard !isDismissing else { return }
        pendingAction = action
        withAnimation(.spring(duration: 0.25, bounce: 0)) {
            isDismissing = true
        } completion: {
            controller.stackDismiss(action)
            isDismissing = false
            pendingAction = nil
        }
    }
}
