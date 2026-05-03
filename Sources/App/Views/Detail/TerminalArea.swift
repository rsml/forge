import SwiftUI

struct TerminalArea: View {
    var session: Session
    @Environment(WorkspaceController.self) var controller

    var body: some View {
        // Key on session+window so terminal recreates only when actually switching.
        // Using GeometryReader ensures full size from the start (no resize flash).
        GeometryReader { geo in
            ForgeTerminalView(sessionName: session.name)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .id("\(session.id):\(controller.workspace.activeWindowId ?? "")")
        .background(Color(red: 0.1, green: 0.1, blue: 0.1))
    }
}
