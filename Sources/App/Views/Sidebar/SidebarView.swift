import SwiftUI

struct SidebarView: View {
    @Environment(WorkspaceController.self) var controller
    @State private var expandedSessions: Set<String> = []
    @State private var showNewProject = false
    @State private var selection: String?
    @State private var renamingSessionId: String?
    @State private var renameText = ""

    var body: some View {
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
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showNewProject = true } label: {
                    Image(systemName: "plus")
                }
                .help("New Project")
            }
        }
        .sheet(isPresented: $showNewProject) {
            ProjectPickerView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .forgeNewProject)) { _ in
            showNewProject = true
        }
        .background {
            // Double-click empty area → new project
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
