import SwiftUI
import ForgeCore

struct StackView: View {
    @Environment(ForgeConfigStore.self) private var configStore
    @Environment(WorkspaceController.self) var controller
    @Environment(AttentionManager.self) var attention
    @Environment(AppState.self) private var appState
    @State private var isFullScreen = false
    @State private var isDismissing = false
    @State private var terminalSnapshot: NSImage?
    @State private var flyoutInfo: (project: Project, tab: ForgeCore.Tab)?

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

            GeometryReader { geo in
                ZStack {
                    // Base layer: always the current natural state
                    if let uuid = attention.currentTabUUID,
                       let (project, tab) = controller.workspace.findTab(byUUID: uuid) {
                        baseContent(
                            project: project,
                            tab: tab,
                            onDismiss: terminalSnapshot == nil ? { action in handleDismiss(action) } : nil
                        )
                        .clipped()
                        .overlay { Color.black.opacity(terminalSnapshot != nil ? (isDismissing ? 0.0 : 0.3) : 0.0) }
                        .scaleEffect(terminalSnapshot != nil ? (isDismissing ? 1.0 : 0.96) : 1.0)
                    } else if let staleUUID = attention.currentTabUUID {
                        let _ = { attention.removeTab(staleUUID) }()
                        StackEmptyState()
                    } else {
                        StackEmptyState()
                    }

                    // Flyout layer: independent of attention queue state
                    if let snapshot = terminalSnapshot, let info = flyoutInfo {
                        flyoutLayer(snapshot: snapshot, project: info.project, tab: info.tab)
                            .scaleEffect(isDismissing ? 0.92 : 1.0)
                            .offset(y: isDismissing ? -(geo.size.height + 100) : 0)
                            .shadow(color: .black.opacity(0.4), radius: 12, y: 3)
                    }
                }
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

    @ViewBuilder
    private func baseContent(
        project: Project,
        tab: ForgeCore.Tab,
        onDismiss: ((WorkspaceController.StackDismissAction) -> Void)?
    ) -> some View {
        VStack(spacing: 0) {
            if toolbarPosition == "top" {
                StackToolbar(project: project, tab: tab, onDismiss: onDismiss)
                TerminalArea(project: project)
            } else {
                TerminalArea(project: project)
                StackToolbar(project: project, tab: tab, onDismiss: onDismiss)
            }
        }
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

        // Save current item for flyout before advancing queue
        if let uuid = attention.currentTabUUID,
           let found = controller.workspace.findTab(byUUID: uuid) {
            flyoutInfo = found
        }

        terminalSnapshot = captureTerminalSnapshot()

        // Advance queue NOW — base layer immediately shows next item (or empty state)
        controller.stackDismiss(action)

        withAnimation(.easeOut(duration: 0.2)) {
            isDismissing = true
        } completion: {
            isDismissing = false
            terminalSnapshot = nil
            flyoutInfo = nil
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
