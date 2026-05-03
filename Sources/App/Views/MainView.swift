import SwiftUI

struct MainView: View {
    @Environment(WorkspaceController.self) var controller

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            if let session = controller.workspace.activeSession {
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
