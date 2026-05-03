import SwiftUI

struct MainView: View {
    @Environment(WorkspaceController.self) var controller
    @State private var sidebarWidth: CGFloat = 160

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            SidebarView()
                .frame(width: sidebarWidth)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))

            // Divider
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)

            // Detail
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 28)  // Match sidebar header for title bar clearance
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .onAppear {
            configureWindow()
        }
    }

    private func configureWindow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
        }
    }
}
