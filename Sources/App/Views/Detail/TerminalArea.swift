import SwiftUI

struct TerminalArea: View {
    var session: Session
    @Environment(WorkspaceController.self) var controller

    var body: some View {
        ForgeTerminalView(sessionName: session.name)
            .id(controller.workspace.activeWindowId)
            .background(Color(red: 0.1, green: 0.1, blue: 0.1))
    }
}
