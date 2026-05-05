import SwiftUI
import ForgeDomain

struct SessionDetailView: View {
    var session: Session
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
                    ForgeConfigStore.shared.resolvedTheme?.background ?? Color(nsColor: .windowBackgroundColor)
                    Color.white.opacity(0.06)
                }
                .frame(height: ForgeConfigStore.shared.titlebarHeight)
            }
            if tabBarPosition == "bottom" {
                TerminalArea(session: session)
                WindowTabBar(session: session, sidebarVisible: sidebarVisible, sidebarPosition: sidebarPosition, isFullScreen: isFullScreen, onToggleSidebar: onToggleSidebar)
            } else {
                WindowTabBar(session: session, sidebarVisible: sidebarVisible, sidebarPosition: sidebarPosition, isFullScreen: isFullScreen, onToggleSidebar: onToggleSidebar)
                TerminalArea(session: session)
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
