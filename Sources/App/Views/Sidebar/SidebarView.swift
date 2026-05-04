import SwiftUI

struct SidebarView: View {
    var onToggleSidebar: () -> Void = {}
    @Environment(WorkspaceController.self) var controller
    @State private var expandedSessions: Set<String> = []
    @State private var showNewProject = false
    @State private var renamingSessionId: String?
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Title bar zone — traffic lights live here; not interactive
            Color.clear.frame(height: 28)

            // Sidebar toolbar — each button fills half the row for maximum tap area
            HStack(spacing: 0) {
                IconButton(systemName: "plus") { showNewProject = true }
                    .help("New Project")

                IconButton(systemName: "sidebar.left") { onToggleSidebar() }
                    .help("Toggle Sidebar")
            }
            .frame(height: 28)

            // Project list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(controller.workspace.sessions) { session in
                        SessionRow(
                            session: session,
                            isActive: session.id == controller.workspace.activeSessionId,
                            activeWindowId: controller.workspace.activeWindowId,
                            isExpanded: Binding(
                                get: { expandedSessions.contains(session.id) },
                                set: { if $0 { expandedSessions.insert(session.id) } else { expandedSessions.remove(session.id) } }
                            ),
                            isRenaming: renamingSessionId == session.id,
                            renameText: $renameText,
                            onRenameCommit: {
                                if !renameText.isEmpty {
                                    controller.renameSession(session, to: renameText)
                                }
                                renamingSessionId = nil
                            },
                            onSelect: {
                                controller.selectSession(session)
                            },
                            onSelectWindow: { window in
                                controller.selectSession(session)
                                controller.selectWindow(window)
                            },
                            onMoveWindow: { source, destination in
                                session.windows.move(fromOffsets: source, toOffset: destination)
                            }
                        )
                        .contextMenu {
                            Button("Rename...") {
                                renameText = session.name
                                renamingSessionId = session.id
                            }
                            Divider()
                            Button("New Tab") { controller.addWindow(in: session) }
                            Divider()
                            Button("Close Project", role: .destructive) { controller.removeSession(session) }
                        }
                    }
                    .onMove { source, destination in
                        controller.workspace.sessions.move(fromOffsets: source, toOffset: destination)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.top, 4)
            }
        }
        .sheet(isPresented: $showNewProject) {
            ProjectPickerView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .forgeNewProject)) { _ in
            showNewProject = true
        }
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    showNewProject = true
                }
        }
    }
}
