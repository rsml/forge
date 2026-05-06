import SwiftUI
import ForgeDomain

struct ProjectDetailView: View {
    var project: Project
    var sidebarVisible: Bool = true
    var onToggleSidebar: () -> Void = {}
    @Environment(WorkspaceController.self) var controller
    @State private var isFullScreen = false

    private var tabBarPosition: String {
        ForgeConfigStore.shared.config.general?.tabBarPosition ??
        ForgeConfigStore.shared.config.terminal?.tabBarPosition ??
        ForgeConfigStore.shared.config.appearance?.tabBarPosition ?? "top"
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isFullScreen {
                ZStack {
                    if let theme = ForgeConfigStore.shared.resolvedTheme {
                        theme.background
                        Color.white.opacity(0.06)
                    } else {
                        Color(nsColor: .windowBackgroundColor)
                    }
                }
                .frame(height: ForgeConfigStore.shared.titlebarHeight)
            }
            if tabBarPosition == "bottom" {
                TerminalArea(project: project)
                WindowTabBar(project: project, sidebarVisible: sidebarVisible, sidebarPosition: sidebarPosition, isFullScreen: isFullScreen, onToggleSidebar: onToggleSidebar)
            } else {
                WindowTabBar(project: project, sidebarVisible: sidebarVisible, sidebarPosition: sidebarPosition, isFullScreen: isFullScreen, onToggleSidebar: onToggleSidebar)
                TerminalArea(project: project)
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

    private var sidebarPosition: String {
        ForgeConfigStore.shared.config.general?.sidebarPosition ?? "left"
    }
}
