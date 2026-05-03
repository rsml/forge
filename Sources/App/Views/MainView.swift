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
                VStack {
                    Spacer()
                    Text("Click + to open a project")
                        .foregroundStyle(.secondary)
                        .font(.body)
                    Spacer()
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}
