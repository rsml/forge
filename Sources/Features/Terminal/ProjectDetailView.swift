import SwiftUI
import ForgeCore

struct ProjectDetailView: View {
    @Environment(ForgeConfigStore.self) private var configStore
    var project: Project
    var sidebarVisible: Bool = true
    var onToggleSidebar: () -> Void = {}
    @Environment(WorkspaceController.self) var controller
    @State private var isFullScreen = false

    private var tabBarPosition: String {
        configStore.config.general?.tabBarPosition ??
        configStore.config.terminal?.tabBarPosition ??
        configStore.config.appearance?.tabBarPosition ?? "top"
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isFullScreen {
                ZStack {
                    if let theme = configStore.resolvedTheme {
                        theme.background
                        Color.white.opacity(0.06)
                    } else {
                        Color(nsColor: .windowBackgroundColor)
                    }
                }
                .frame(height: configStore.titlebarHeight)
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
        configStore.config.general?.sidebarPosition ?? "left"
    }
}
