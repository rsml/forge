import SwiftUI

struct SessionDetailView: View {
    var session: Session
    var sidebarVisible: Bool = true
    var onToggleSidebar: () -> Void = {}
    @Environment(WorkspaceController.self) var controller

    var body: some View {
        VStack(spacing: 0) {
            WindowTabBar(session: session, sidebarVisible: sidebarVisible, onToggleSidebar: onToggleSidebar)
            TerminalArea(session: session)
        }
        .toolbar(.hidden, for: .automatic)
    }
}
