import SwiftUI
import ForgeCore

struct StackView: View {
    @Environment(ForgeConfigStore.self) private var configStore
    @Environment(WorkspaceController.self) var controller
    @Environment(AttentionManager.self) var attention
    @Environment(AppState.self) private var appState
    @State private var isFullScreen = false
    @State private var isDismissing = false
    @State private var pendingAction: WorkspaceController.StackDismissAction?
    @State private var terminalSnapshot: NSImage?
    @State private var dismissToEmpty = false

    private var toolbarPosition: String {
        configStore.config.stackView?.toolbarPosition ?? "bottom"
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isFullScreen {
                ZStack {
                    configStore.resolvedTheme?.background.color ?? Color(nsColor: .windowBackgroundColor)
                    Color.white.opacity(0.06)
                }
                .frame(height: configStore.titlebarHeight)
            }

            if let uuid = attention.currentTabUUID,
               let (project, tab) = controller.workspace.findTab(byUUID: uuid) {
                GeometryReader { geo in
                    ZStack {
                        if terminalSnapshot != nil {
                            Color.black.opacity(0.5)
                                .ignoresSafeArea()
                        }

                        if terminalSnapshot != nil && dismissToEmpty {
                            StackEmptyState()
                        } else {
                            baseLayer(project: project, tab: tab)
                                .clipped()
                                .overlay { Color.black.opacity(terminalSnapshot != nil ? (isDismissing ? 0.0 : 0.3) : 0.0) }
                                .scaleEffect(terminalSnapshot != nil ? (isDismissing ? 1.0 : 0.96) : 1.0)
                        }

                        if let snapshot = terminalSnapshot {
                            flyoutLayer(snapshot: snapshot, project: project, tab: tab)
                                .scaleEffect(isDismissing ? 0.92 : 1.0)
                                .offset(y: isDismissing ? -(geo.size.height + 100) : 0)
                                .shadow(color: .black.opacity(0.4), radius: 12, y: 3)
                        }
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
        .onChange(of: appState.pendingStackAction) { _, action in
            guard let action else { return }
            handleDismiss(action)
            appState.pendingStackAction = nil
        }
    }

    private func baseLayer(project: Project, tab: ForgeCore.Tab) -> some View {
        let resolved = resolveBaseToolbar(fallbackProject: project, fallbackTab: tab)
        let dismissHandler: ((WorkspaceController.StackDismissAction) -> Void)? =
            terminalSnapshot == nil ? { action in self.handleDismiss(action) } : nil
        return baseContent(
            terminalProject: project,
            toolbarProject: resolved.project,
            toolbarTab: resolved.tab,
            onDismiss: dismissHandler
        )
    }

    @ViewBuilder
    private func baseContent(
        terminalProject: Project,
        toolbarProject: Project,
        toolbarTab: ForgeCore.Tab,
        onDismiss: ((WorkspaceController.StackDismissAction) -> Void)?
    ) -> some View {
        VStack(spacing: 0) {
            if toolbarPosition == "top" {
                StackToolbar(project: toolbarProject, tab: toolbarTab, onDismiss: onDismiss)
                TerminalArea(project: terminalProject)
            } else {
                TerminalArea(project: terminalProject)
                StackToolbar(project: toolbarProject, tab: toolbarTab, onDismiss: onDismiss)
            }
        }
    }

    private func resolveBaseToolbar(
        fallbackProject: Project, fallbackTab: ForgeCore.Tab
    ) -> (project: Project, tab: ForgeCore.Tab) {
        if terminalSnapshot != nil,
           let nextUUID = attention.nextWindowUUID,
           let next = controller.workspace.findTab(byUUID: nextUUID) {
            return next
        }
        return (fallbackProject, fallbackTab)
    }

    @ViewBuilder
    private func flyoutLayer(snapshot: NSImage, project: Project, tab: ForgeCore.Tab) -> some View {
        VStack(spacing: 0) {
            if toolbarPosition == "top" {
                StackToolbar(project: project, tab: tab)
                Image(nsImage: snapshot)
                    .resizable()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(nsImage: snapshot)
                    .resizable()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                StackToolbar(project: project, tab: tab)
            }
        }
        .allowsHitTesting(false)
    }

    private func handleDismiss(_ action: WorkspaceController.StackDismissAction) {
        guard !isDismissing else { return }
        pendingAction = action
        dismissToEmpty = (attention.nextWindowUUID == nil)
        terminalSnapshot = captureTerminalSnapshot()

        if let nextUUID = attention.nextWindowUUID,
           let (nextProject, nextTab) = controller.workspace.findTab(byUUID: nextUUID),
           let currentUUID = attention.currentTabUUID,
           let (currentProject, _) = controller.workspace.findTab(byUUID: currentUUID),
           nextProject.id == currentProject.id {
            controller.switchTerminalWindow(tabId: nextTab.id)
        }

        withAnimation(.easeOut(duration: 0.2)) {
            isDismissing = true
        } completion: {
            controller.stackDismiss(pendingAction ?? action)
            isDismissing = false
            terminalSnapshot = nil
            pendingAction = nil
            dismissToEmpty = false
        }
    }

    private func captureTerminalSnapshot() -> NSImage? {
        guard let window = NSApp.keyWindow else { return nil }
        guard let tv = findTerminalView(in: window.contentView) else { return nil }
        let bounds = tv.bounds
        guard bounds.width > 0, bounds.height > 0,
              let rep = tv.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        tv.cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }

    private func findTerminalView(in view: NSView?) -> NSView? {
        guard let view else { return nil }
        if String(describing: type(of: view)).contains("LocalProcessTerminalView") {
            return view
        }
        for sub in view.subviews {
            if let found = findTerminalView(in: sub) { return found }
        }
        return nil
    }
}
