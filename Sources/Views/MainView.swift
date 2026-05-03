import SwiftUI

struct MainView: View {
    @Environment(TmuxController.self) var tmux

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            if let session = tmux.state.activeSession {
                SessionDetailView(session: session)
            } else {
                ContentUnavailableView(
                    "No Project Selected",
                    systemImage: "hammer.fill",
                    description: Text("Press \u{2318}O to open a project, or click + in the sidebar.")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}
