import SwiftUI

struct SessionDetailView: View {
    var session: Session
    @Environment(WorkspaceController.self) var controller

    var body: some View {
        VStack(spacing: 0) {
            WindowTabBar(session: session)
            TerminalArea(session: session)
        }
        .toolbar(.hidden, for: .automatic)
    }
}
