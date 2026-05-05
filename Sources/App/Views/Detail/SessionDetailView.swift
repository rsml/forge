import SwiftUI

struct SessionDetailView: View {
    var session: Session
    var sidebarVisible: Bool = true
    var onToggleSidebar: () -> Void = {}
    @Environment(WorkspaceController.self) var controller

    private var tabBarPosition: String {
        ForgeConfigStore.shared.config.general?.tabBarPosition ??
        ForgeConfigStore.shared.config.terminal?.tabBarPosition ??
        ForgeConfigStore.shared.config.appearance?.tabBarPosition ?? "top"
    }

    var body: some View {
        VStack(spacing: 0) {
            if tabBarPosition == "bottom" {
                TerminalArea(session: session)
                WindowTabBar(session: session, sidebarVisible: sidebarVisible, sidebarPosition: sidebarPosition, onToggleSidebar: onToggleSidebar)
            } else {
                WindowTabBar(session: session, sidebarVisible: sidebarVisible, sidebarPosition: sidebarPosition, onToggleSidebar: onToggleSidebar)
                TerminalArea(session: session)
            }
        }
        .toolbar(.hidden, for: .automatic)
    }

    private var sidebarPosition: String {
        ForgeConfigStore.shared.config.general?.sidebarPosition ?? "left"
    }
}
