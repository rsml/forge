import SwiftUI

struct SidebarView: View {
    @Environment(WorkspaceController.self) var controller
    @State private var expandedSessions: Set<String> = []
    @State private var showNewProject = false
    @State private var selection: String?
    @State private var renamingSessionId: String?
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Top area — traffic lights sit here, + button on the right
            HStack {
                // Left space for traffic lights (close/min/fullscreen ~68px)
                Spacer()
                    .frame(width: 68)
                Spacer()
                Button { showNewProject = true } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("New Project")
                .padding(.trailing, 8)
            }
            .frame(height: 28)

            // Project list
            List(selection: $selection) {
                ForEach(controller.workspace.sessions) { session in
                    SessionRow(
                        session: session,
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
                        onSelectWindow: { window in
                            controller.selectSession(session)
                            controller.selectWindow(window)
                        }
                    )
                    .tag(session.id)
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
            .listStyle(.sidebar)
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
        .onChange(of: selection) { _, newId in
            if let newId, let session = controller.workspace.session(byId: newId) {
                controller.selectSession(session)
            }
        }
        .onChange(of: controller.workspace.activeSessionId) { _, newId in
            selection = newId
        }
        .onAppear {
            selection = controller.workspace.activeSessionId
        }
    }
}
